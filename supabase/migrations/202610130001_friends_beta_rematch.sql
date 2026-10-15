begin;

do $$ begin
  if exists (select 1 from public.matches m join public.rounds r
    on r.match_id=m.id and r.round_number=m.round_count
    where m.status='completed' and (r.state <> 'revealed' or r.completed_at is distinct from m.completed_at
      or (select count(*) from public.rounds x where x.match_id=m.id and x.state='revealed' and x.revealed_answer is not null) <> m.round_count)) then
    raise exception 'inconsistent completed match requires adjudication';
  end if;
end;
$$;

create table private.live_feature_configuration (
  singleton boolean primary key default true check (singleton),
  allow_new_rematches boolean not null default false
);
insert into private.live_feature_configuration values (true,false);
create table private.participation_cursors (
  actor_user_id uuid primary key references public.profiles(id) on delete cascade,
  selected_match_id uuid,
  epoch bigint not null default 0 check (epoch between 0 and 9007199254740991)
);
create table private.live_command_receipts (
  actor_user_id uuid not null references public.profiles(id) on delete cascade,
  request_id uuid not null,
  kind text not null check (kind in ('join','rematch')),
  payload jsonb not null,
  response jsonb not null,
  primary key(actor_user_id,request_id)
);
create table private.rematch_contexts (
  predecessor_match_id uuid primary key references public.matches(id) on delete cascade,
  generation integer not null default 1 check(generation>0),
  state text not null default 'eligible' check(state in ('eligible','offered','closed','expired','unavailable','accepted')),
  reason text check(reason in ('cancelled','declined','participation_changed','expired','account_deleted','ineligible','feature_disabled')),
  initiator_member_id uuid,
  consenting_member_ids uuid[] not null default '{}',
  actor_epochs jsonb not null default '{}',
  revision bigint not null default 1 check(revision>0),
  deadline timestamptz not null,
  successor_match_id uuid unique
);
create table private.rematch_successors (
  match_id uuid primary key references public.matches(id) on delete cascade,
  predecessor_match_id uuid not null unique,
  excluded_answers text[] not null
);
create table public.match_rematch_signals (
  predecessor_match_id uuid primary key references public.matches(id) on delete cascade,
  revision bigint not null check(revision>0)
);
alter table public.match_rematch_signals enable row level security;
create policy rematch_signal_member_read on public.match_rematch_signals
  for select to authenticated using(app_rls.is_match_member(predecessor_match_id));
revoke all on public.match_rematch_signals from public,anon,authenticated;
grant select(predecessor_match_id,revision) on public.match_rematch_signals to authenticated;
grant all on public.match_rematch_signals to service_role;
alter publication supabase_realtime add table public.match_rematch_signals(predecessor_match_id,revision);
revoke all on private.live_feature_configuration,private.participation_cursors,
  private.live_command_receipts,private.rematch_contexts,private.rematch_successors from public,anon,authenticated;
grant all on private.live_feature_configuration,private.participation_cursors,
  private.live_command_receipts,private.rematch_contexts,private.rematch_successors to service_role;

create function private.lock_live_actors(p_actors uuid[])
returns void language plpgsql volatile security invoker set search_path='' as $$
declare v_key bigint; v_actor uuid;
begin
  for v_key in select distinct pg_catalog.hashtextextended(x::text,1) from unnest(p_actors) x
    where x is not null order by 1 loop
    perform pg_catalog.pg_advisory_xact_lock(v_key);
  end loop;
  for v_actor in select distinct x from unnest(p_actors) x where x is not null order by x loop
    if exists(select 1 from public.profiles where id=v_actor) then
      insert into private.participation_cursors(actor_user_id) values(v_actor) on conflict do nothing;
      perform 1 from private.participation_cursors where actor_user_id=v_actor for update;
    end if;
  end loop;
end;
$$;
create function private.select_live_match(p_actor uuid,p_match uuid)
returns bigint language plpgsql volatile security invoker set search_path='' as $$
declare v_epoch bigint;
begin
  update private.participation_cursors set selected_match_id=p_match,epoch=epoch+1
    where actor_user_id=p_actor and selected_match_id is distinct from p_match returning epoch into v_epoch;
  if not found then select epoch into v_epoch from private.participation_cursors where actor_user_id=p_actor;
  end if;
  return v_epoch;
end;
$$;
create function private.publish_rematch_revision()
returns trigger language plpgsql security invoker set search_path='' as $$
begin
  insert into public.match_rematch_signals values(new.predecessor_match_id,new.revision)
    on conflict(predecessor_match_id) do update set revision=excluded.revision;
  return new;
end;
$$;
create trigger rematch_revision_signal after insert or update on private.rematch_contexts
  for each row execute function private.publish_rematch_revision();
create or replace function private.error_response(p_code text)
returns jsonb
language sql
immutable
security invoker
set search_path = ''
as $$
  select jsonb_build_object(
    'error', jsonb_build_object(
      'code', p_code,
      'message', case p_code
        when 'rematch_unavailable' then 'This rematch is unavailable.'
        when 'rematch_expired' then 'This rematch opportunity has expired.'
        when 'answer_pool_unavailable' then 'There are not enough available answers for this rematch.'
        when 'participation_changed' then 'Your selected race changed. Refresh and try again.'
        when 'invalid_match_configuration' then 'Choose 1, 3, or 5 rounds.'
        when 'match_incomplete' then 'This match cannot continue because a player account was deleted.'
        when 'not_authenticated' then 'Sign in and try again.'
        when 'not_a_match_member' then 'You are not part of this match.'
        when 'match_not_joinable' then 'This match cannot be joined.'
        when 'room_full' then 'This room is full.'
        when 'room_expired' then 'This room has expired.'
        when 'not_host' then 'Only the creator can start this match.'
        when 'not_enough_players' then 'Two players are required.'
        when 'round_not_active' then 'This round is not active.'
        when 'round_already_finished' then 'This round has already finished.'
        when 'invalid_guess_format' then 'Enter a five-letter word.'
        when 'word_not_accepted' then 'That word is not accepted.'
        when 'rate_limited' then 'Too many attempts. Try again shortly.'
        when 'client_update_required' then 'Update the app to continue.'
        when 'request_conflict' then 'This request conflicts with an earlier attempt.'
        else 'Something went wrong. Try again.'
      end
    )
  );
$$;

create or replace function public.create_match(
  p_user_id uuid,
  p_client_build integer,
  p_ip_hash text,
  p_request_id uuid,
  p_round_count smallint
)
returns jsonb
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  v_now timestamptz := transaction_timestamp();
  v_match_id uuid := extensions.gen_random_uuid();
  v_member_id uuid := extensions.gen_random_uuid();
  v_code text;
  v_constraint_name text;
  v_profile public.profiles%rowtype;
  v_receipt private.create_requests%rowtype;
begin
  if p_user_id is null then
    return private.error_response('not_authenticated');
  end if;

  if p_client_build is null or p_client_build < 3 then
    return private.error_response('client_update_required');
  end if;

  if p_round_count is null or p_round_count not in (1, 3, 5) then
    return private.error_response('invalid_match_configuration');
  end if;

  if p_request_id is null then
    return private.error_response('internal_error');
  end if;

  perform private.lock_live_actors(array[p_user_id]);

  select * into v_profile
  from public.profiles
  where id = p_user_id;
  if not found then
    return private.error_response('not_authenticated');
  end if;

  select * into v_receipt
  from private.create_requests
  where actor_user_id = p_user_id and request_id = p_request_id;
  if found then
    if v_receipt.client_build = p_client_build and v_receipt.round_count = p_round_count then
      return jsonb_build_object(
        'data', jsonb_build_object('match_id', v_receipt.match_id)
      );
    end if;
    return private.error_response('request_conflict');
  end if;

  if not private.consume_rate_limit(p_user_id, p_ip_hash, 'create', v_now) then
    return private.error_response('rate_limited');
  end if;

  loop
    v_code := private.random_join_code();
    begin
      insert into public.matches (
        id,
        join_code,
        creator_member_id,
        created_at,
        updated_at,
        expires_at,
        minimum_client_build,
        round_count
      )
      values (
        v_match_id,
        v_code,
        v_member_id,
        v_now,
        v_now,
        v_now + interval '60 minutes',
        3,
        p_round_count
      );
      exit;
    exception when unique_violation then
      get stacked diagnostics v_constraint_name = constraint_name;
      if v_constraint_name <> 'matches_join_code_key' then
        raise;
      end if;
    end;
  end loop;

  insert into public.match_members (
    id,
    match_id,
    auth_user_id,
    seat,
    joined_at,
    display_name_snapshot,
    avatar_seed_snapshot
  )
  values (
    v_member_id,
    v_match_id,
    p_user_id,
    1,
    v_now,
    v_profile.display_name,
    v_profile.avatar_seed
  );

  insert into public.rounds (match_id, round_number, state)
  select v_match_id, number, 'pending' from generate_series(1, p_round_count) as number;

  insert into private.create_requests (
    actor_user_id,
    request_id,
    client_build,
    match_id,
    round_count
  )
  values (p_user_id, p_request_id, p_client_build, v_match_id, p_round_count);

  perform private.select_live_match(p_user_id,v_match_id);
  return jsonb_build_object('data', jsonb_build_object('match_id', v_match_id));
end;
$$;

create or replace function public.start_match(
  p_user_id uuid,
  p_client_build integer,
  p_match_id uuid,
  p_round_number smallint
)
returns jsonb
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  v_now timestamptz := transaction_timestamp();
  v_match public.matches%rowtype;
  v_member_id uuid;
  v_member_count integer;
  v_round_id uuid;
  v_round public.rounds%rowtype;
  v_answer text;
  v_exclusions text[];
  v_capacity integer;
begin
  if p_client_build is null or p_client_build < 3 then
    return private.error_response('client_update_required');
  end if;

  if p_user_id is null then
    return private.error_response('not_authenticated');
  end if;

  perform private.lock_live_actors(array[p_user_id]);
  if not exists (select 1 from public.profiles where id = p_user_id) then
    return private.error_response('not_authenticated');
  end if;

  select * into v_match from public.matches where id = p_match_id for update;
  if not found then
    return private.error_response('not_a_match_member');
  end if;

  if p_client_build is null or p_client_build < v_match.minimum_client_build then
    return private.error_response('client_update_required');
  end if;

  select id into v_member_id
  from public.match_members
  where match_id = p_match_id and auth_user_id = p_user_id;
  if not found then
    return private.error_response('not_a_match_member');
  end if;

  if v_member_id <> v_match.creator_member_id then
    return private.error_response('not_host');
  end if;

  if p_round_number is null or p_round_number < 1 or p_round_number > v_match.round_count then
    return private.error_response('round_not_active');
  end if;

  select * into v_round from public.rounds
  where match_id = p_match_id and round_number = p_round_number for update;
  if not found then
    return private.error_response('round_not_active');
  end if;
  v_round_id := v_round.id;
  if v_round.starts_at is not null then
    return jsonb_build_object('data', jsonb_build_object('match_id', p_match_id));
  end if;

  if v_match.terminal_reason = 'account_deleted' or exists (
    select 1 from public.match_members where match_id = p_match_id and deleted_at is not null
  ) then
    return private.error_response('match_incomplete');
  end if;

  if p_round_number = 1 then
    if v_match.status <> 'lobby' then
      return private.error_response('round_not_active');
    end if;
    if v_now >= v_match.expires_at then
      return private.error_response('room_expired');
    end if;
  elsif v_match.status <> 'in_progress' or p_round_number <> v_match.current_round + 1 then
    return private.error_response('round_not_active');
  elsif not exists (
    select 1 from public.rounds where match_id = p_match_id
      and round_number = v_match.current_round and state = 'revealed'
  ) then
    return private.error_response('round_not_active');
  end if;

  select count(*) into v_member_count from public.match_members
  where match_id = p_match_id and deleted_at is null;
  if v_member_count <> 2 then
    return private.error_response('not_enough_players');
  end if;

  perform 1
  from public.match_members
  where match_id = p_match_id
  order by seat
  for update;

  select excluded_answers into v_exclusions from private.rematch_successors where match_id=p_match_id;
  if found then
    perform 1 from private.words where is_active and is_answer order by word for share;
    select count(*) into v_capacity from private.words w where is_active and is_answer
      and not(w.word=any(v_exclusions)) and not exists(
        select 1 from private.round_secrets s join public.rounds r on r.id=s.round_id
        where r.match_id=p_match_id and s.answer=w.word);
    if v_capacity < v_match.round_count-p_round_number+1 then
      return private.error_response('answer_pool_unavailable');
    end if;
  end if;
  select word into v_answer from private.words w where is_active and is_answer
    and (v_exclusions is null or not(w.word=any(v_exclusions))) and not exists(
      select 1 from private.round_secrets s join public.rounds r on r.id=s.round_id
      where r.match_id=p_match_id and s.answer=w.word)
    order by random() limit 1;
  if v_answer is null then
    return private.error_response('internal_error');
  end if;

  update public.matches
  set status = 'in_progress', current_round = p_round_number,
      started_at = coalesce(started_at, v_now), updated_at = v_now
  where id = p_match_id;

  update public.rounds
  set state = 'countdown',
      starts_at = v_now + interval '3 seconds',
      ends_at = v_now + interval '183 seconds'
  where id = v_round_id;

  insert into private.round_secrets (round_id, answer, selected_at)
  values (v_round_id, v_answer, v_now);

  insert into public.player_rounds (round_id, member_id, started_at)
  select v_round_id, member.id, v_now + interval '3 seconds'
  from public.match_members as member
  where member.match_id = p_match_id
  order by member.seat;

  perform private.select_live_match(p_user_id,p_match_id);
  return jsonb_build_object('data', jsonb_build_object('match_id', p_match_id));
end;
$$;

create or replace function public.submit_guess(
  p_user_id uuid,
  p_client_build integer,
  p_match_id uuid,
  p_round_number smallint,
  p_request_id uuid,
  p_guess text,
  p_ip_hash text default null
)
returns jsonb
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  v_now timestamptz := transaction_timestamp();
  v_normalized text := private.normalize_guess(p_guess);
  v_receipt private.guess_requests%rowtype;
  v_match public.matches%rowtype;
  v_round public.rounds%rowtype;
  v_member_id uuid;
  v_player public.player_rounds%rowtype;
  v_answer text;
  v_feedback smallint[];
  v_sequence smallint;
  v_player_state text;
  v_solve_duration_us bigint;
  v_efficiency smallint;
  v_guess_id uuid := extensions.gen_random_uuid();
  v_response jsonb;
begin
  if p_client_build is null or p_client_build < 3 then
    return private.error_response('client_update_required');
  end if;

  if p_user_id is null then
    return private.error_response('not_authenticated');
  end if;

  perform private.lock_live_actors(array[p_user_id]);

  if not exists (select 1 from public.profiles where id = p_user_id) then
    return private.error_response('not_authenticated');
  end if;

  select * into v_receipt
  from private.guess_requests
  where actor_user_id = p_user_id and request_id = p_request_id;
  if found then
    if v_normalized is not null
      and v_receipt.match_id = p_match_id
      and v_receipt.round_number = p_round_number
      and v_receipt.normalized_guess = v_normalized
    then
      return jsonb_build_object('data', v_receipt.response_data);
    end if;
    return private.error_response('request_conflict');
  end if;

  select * into v_match from public.matches where id = p_match_id for update;
  if not found then
    return private.error_response('not_a_match_member');
  end if;

  select * into v_receipt
  from private.guess_requests
  where actor_user_id = p_user_id and request_id = p_request_id;
  if found then
    if v_normalized is not null
      and v_receipt.match_id = p_match_id
      and v_receipt.round_number = p_round_number
      and v_receipt.normalized_guess = v_normalized
    then
      return jsonb_build_object('data', v_receipt.response_data);
    end if;
    return private.error_response('request_conflict');
  end if;

  if not private.consume_rate_limit(p_user_id, p_ip_hash, 'submit_guess', v_now) then
    return private.error_response('rate_limited');
  end if;

  if p_client_build is null or p_client_build < v_match.minimum_client_build then
    return private.error_response('client_update_required');
  end if;

  select id into v_member_id
  from public.match_members
  where match_id = p_match_id and auth_user_id = p_user_id;
  if not found then
    return private.error_response('not_a_match_member');
  end if;

  if p_round_number is null or p_round_number < 1 or p_round_number > v_match.round_count then
    return private.error_response('round_not_active');
  end if;

  select * into v_round
  from public.rounds
  where match_id = p_match_id and round_number = p_round_number
  for update;

  if v_round.state = 'revealed' or v_match.status = 'completed' then
    return private.error_response('round_already_finished');
  elsif not found or p_round_number <> v_match.current_round
    or v_round.state <> 'countdown' or v_now < v_round.starts_at then
    return private.error_response('round_not_active');
  end if;

  select * into v_player
  from public.player_rounds
  where round_id = v_round.id and member_id = v_member_id
  for update;

  if v_now >= v_round.ends_at then
    perform private.finalize_round(v_round.id);
    return private.error_response('round_already_finished');
  end if;

  if v_player.state <> 'playing' then
    return private.error_response('round_already_finished');
  end if;

  if v_normalized is null then
    return private.error_response('invalid_guess_format');
  end if;

  if not exists (
    select 1 from private.words
    where word = v_normalized and is_active and is_accepted
  ) then
    return private.error_response('word_not_accepted');
  end if;

  select answer into v_answer
  from private.round_secrets
  where round_id = v_round.id;
  if not found then
    return private.error_response('internal_error');
  end if;

  v_feedback := private.evaluate_guess(v_answer, v_normalized);
  v_sequence := v_player.accepted_guess_count + 1;

  if v_feedback = array[2, 2, 2, 2, 2]::smallint[] then
    v_player_state := 'solved';
    v_solve_duration_us := floor(
      extract(epoch from (v_now - v_round.starts_at)) * 1000000
    )::bigint;
    v_efficiency := 7 - v_sequence;
  elsif v_sequence = 6 then
    v_player_state := 'failed';
    v_efficiency := 0;
  else
    v_player_state := 'playing';
  end if;

  insert into public.guesses (
    id,
    request_id,
    round_id,
    member_id,
    sequence,
    normalized_guess,
    feedback,
    submitted_at
  )
  values (
    v_guess_id,
    p_request_id,
    v_round.id,
    v_member_id,
    v_sequence,
    v_normalized,
    v_feedback,
    v_now
  );

  update public.player_rounds
  set accepted_guess_count = v_sequence,
      state = v_player_state,
      finished_at = case when v_player_state = 'playing' then null else v_now end,
      solve_duration_us = v_solve_duration_us,
      efficiency_points = v_efficiency
  where round_id = v_round.id and member_id = v_member_id;

  v_response := jsonb_build_object(
    'accepted', true,
    'sequence', v_sequence,
    'feedback', to_jsonb(v_feedback),
    'player_state', v_player_state,
    'accepted_guess_count', v_sequence,
    'solve_duration_ms', case
      when v_solve_duration_us is null then null
      else v_solve_duration_us / 1000
    end,
    'efficiency_points', case when v_player_state = 'solved' then v_efficiency else null end,
    'server_time', v_now,
    'round_end_time', v_round.ends_at
  );

  insert into private.guess_requests (
    actor_user_id,
    request_id,
    match_id,
    round_number,
    normalized_guess,
    guess_id,
    response_data
  )
  values (
    p_user_id,
    p_request_id,
    p_match_id,
    p_round_number,
    v_normalized,
    v_guess_id,
    v_response
  );

  update public.matches set updated_at = v_now where id = p_match_id;

  if v_player_state <> 'playing'
    and not exists (
      select 1 from public.player_rounds
      where round_id = v_round.id and state = 'playing'
    )
  then
    perform private.finalize_round(v_round.id);
  end if;

  perform private.select_live_match(p_user_id,p_match_id);
  return jsonb_build_object('data', v_response);
end;
$$;

create or replace function public.delete_account(
  p_user_id uuid,
  p_client_build integer
)
returns jsonb
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  v_now timestamptz := transaction_timestamp();
  v_match_id uuid;
  v_match public.matches%rowtype;
  v_member_id uuid;
  v_round_id uuid;
begin
  if p_user_id is null then
    return private.error_response('not_authenticated');
  end if;

  if p_client_build < 1 then
    return private.error_response('client_update_required');
  end if;

  perform private.lock_live_actors(array[p_user_id]);
  delete from private.live_command_receipts where actor_user_id=p_user_id;
  delete from private.participation_cursors where actor_user_id=p_user_id;

  delete from public.daily_progress where user_id = p_user_id;
  delete from public.daily_imported_results where user_id = p_user_id;
  delete from private.user_rate_limits where actor_user_id = p_user_id;
  delete from private.create_requests where actor_user_id = p_user_id;

  for v_match_id in
    select member.match_id
    from public.match_members as member
    where member.auth_user_id = p_user_id
    order by member.match_id
  loop
    select * into v_match from public.matches where id = v_match_id for update;
    update private.rematch_contexts set state='unavailable',reason='account_deleted',
      consenting_member_ids='{}',actor_epochs='{}',initiator_member_id=null,revision=revision+1
      where predecessor_match_id=v_match_id and state not in ('accepted','unavailable','expired');

    select id into v_member_id
    from public.match_members
    where match_id = v_match_id and auth_user_id = p_user_id;

    if v_match.status = 'lobby' then
      if v_member_id = v_match.creator_member_id then
        delete from public.matches where id = v_match_id;
      else
        delete from public.match_members where id = v_member_id;
        update public.matches set updated_at = v_now where id = v_match_id;
      end if;
      continue;
    end if;

    select id into v_round_id
    from public.rounds
    where match_id = v_match_id and round_number = v_match.current_round
    for update;

    perform 1
    from public.player_rounds as player
    join public.match_members as member on member.id = player.member_id
    where player.round_id = v_round_id
    order by member.seat
    for update of player;

    if v_match.status = 'in_progress' then
      update public.player_rounds
      set state = 'forfeited',
          finished_at = v_now,
          solve_duration_us = null,
          efficiency_points = 0
      where round_id = v_round_id and member_id = v_member_id and state = 'playing';
    end if;

    update public.match_members
    set auth_user_id = null,
        display_name_snapshot = 'Deleted Player',
        avatar_seed_snapshot = 'deleted-player',
        deleted_at = v_now
    where id = v_member_id;

    update public.matches
    set updated_at = v_now,
        terminal_reason = case when current_round < round_count and status <> 'completed'
          then 'account_deleted' else null end,
        status = case when current_round < round_count and exists (
          select 1 from public.rounds where id = v_round_id and state = 'revealed'
        ) then 'incomplete' else status end
    where id = v_match_id;

    if v_match.status = 'in_progress'
      and not exists (
        select 1 from public.player_rounds
        where round_id = v_round_id and state = 'playing'
      )
    then
      perform private.finalize_round(v_round_id);
    end if;
  end loop;

  delete from private.guess_requests where actor_user_id = p_user_id;
  delete from public.profiles where id = p_user_id;

  return jsonb_build_object('data', jsonb_build_object('deleted', true));
end;
$$;


create function private.join_live_match(
  p_user_id uuid,p_client_build integer,p_join_code text,p_ip_hash text,p_expected_match_id uuid
) returns jsonb language plpgsql volatile security invoker set search_path='' as $$
declare
  v_now timestamptz := clock_timestamp(); v_match public.matches%rowtype;
  v_profile public.profiles%rowtype; v_member uuid; v_count integer;
begin
  select * into v_profile from public.profiles where id=p_user_id;
  if not found then
    return private.error_response('not_authenticated');
  end if;
  if p_client_build is null or p_client_build<3 then
    return private.error_response('client_update_required');
  end if;
  if p_join_code is null or p_join_code !~ '^[A-HJ-NP-Z2-9]{6}$' then
    return private.error_response('match_not_joinable');
  end if;
  select * into v_match from public.matches where join_code=p_join_code for update;
  if not found then
    return private.error_response('match_not_joinable');
  end if;
  if p_expected_match_id is not null and v_match.id<>p_expected_match_id then
    return private.error_response('match_not_joinable');
  end if;
  if p_client_build<v_match.minimum_client_build then
    return private.error_response('client_update_required');
  end if;
  select id into v_member from public.match_members where match_id=v_match.id and auth_user_id=p_user_id;
  if p_expected_match_id is not null and v_member is null then
    return private.error_response('not_a_match_member');
  end if;
  if not private.consume_rate_limit(p_user_id,p_ip_hash,'join',v_now) then
    return private.error_response('rate_limited');
  end if;
  if v_member is not null then
    perform private.select_live_match(p_user_id,v_match.id);
    return jsonb_build_object('data',jsonb_build_object('match_id',v_match.id));
  end if;
  if exists(select 1 from private.rematch_successors where match_id=v_match.id) then
    return private.error_response('match_not_joinable');
  end if;
  if v_now>=v_match.expires_at then
    return private.error_response('room_expired');
  end if;
  if v_match.status<>'lobby' then
    return private.error_response('match_not_joinable');
  end if;
  select count(*) into v_count from public.match_members where match_id=v_match.id;
  if v_count>=2 then
    return private.error_response('room_full');
  end if;
  insert into public.match_members(match_id,auth_user_id,seat,joined_at,display_name_snapshot,avatar_seed_snapshot)
    values(v_match.id,p_user_id,2,v_now,v_profile.display_name,v_profile.avatar_seed);
  update public.matches set updated_at=v_now where id=v_match.id;
  perform private.select_live_match(p_user_id,v_match.id);
  return jsonb_build_object('data',jsonb_build_object('match_id',v_match.id));
end;
$$;

create function public.join_match(p_user_id uuid,p_client_build integer,p_join_code text,p_ip_hash text,p_request_id uuid,p_expected_match_id uuid)
returns jsonb language plpgsql volatile security invoker set search_path='' as $$
declare v_payload jsonb; v_receipt private.live_command_receipts%rowtype; v_response jsonb;
begin
  if p_user_id is null then
    return private.error_response('not_authenticated');
  end if;
  perform private.lock_live_actors(array[p_user_id]);
  if not exists(select 1 from public.profiles where id=p_user_id) then
    return private.error_response('not_authenticated');
  end if;
  if p_client_build is null or p_client_build<3 then
    return private.error_response('client_update_required');
  end if;
  if p_request_id is null then
    return private.error_response('internal_error');
  end if;
  v_payload:=jsonb_build_object('client_build',p_client_build,'join_code',upper(p_join_code),'expected_match_id',p_expected_match_id);
  select * into v_receipt from private.live_command_receipts where actor_user_id=p_user_id and request_id=p_request_id;
  if found then
    if v_receipt.kind='join' and v_receipt.payload=v_payload then return v_receipt.response;
  end if;
    return private.error_response('request_conflict');
  end if;
  v_response:=private.join_live_match(p_user_id,p_client_build,upper(p_join_code),p_ip_hash,p_expected_match_id);
  if coalesce(v_response->'error'->>'code','') not in ('rate_limited','internal_error','not_authenticated') then
    insert into private.live_command_receipts values(p_user_id,p_request_id,'join',v_payload,v_response);
  end if;
  return v_response;
end;
$$;

create function private.normalize_rematch(p_match_id uuid,p_now timestamptz)
returns void language plpgsql volatile security invoker set search_path='' as $$
declare v_match public.matches%rowtype; v_context private.rematch_contexts%rowtype;
  v_reason text; v_enabled boolean;
begin
  select * into v_match from public.matches where id=p_match_id;
  if v_match.status<>'completed' then return;
  end if;
  insert into private.rematch_contexts(predecessor_match_id,deadline)
    values(p_match_id,v_match.completed_at+interval '5 minutes') on conflict do nothing;
  select * into v_context from private.rematch_contexts where predecessor_match_id=p_match_id for update;
  if v_context.state='accepted' then return;
  end if;
  select allow_new_rematches into v_enabled from private.live_feature_configuration where singleton;
  if (select count(*) from public.match_members m join public.profiles p on p.id=m.auth_user_id
      where m.match_id=p_match_id and m.deleted_at is null)<>2 then v_reason:='account_deleted';
  elsif (select count(*) from public.rounds where match_id=p_match_id and state='revealed' and revealed_answer is not null)<>v_match.round_count
    or not exists(select 1 from public.rounds where match_id=p_match_id and round_number=v_match.round_count
      and completed_at=v_match.completed_at) then v_reason:='ineligible';
  elsif p_now>=v_context.deadline then v_reason:='expired';
  elsif not v_enabled then v_reason:='feature_disabled';
  elsif v_context.state='offered' and exists(
    select 1 from public.match_members m join private.participation_cursors c on c.actor_user_id=m.auth_user_id
      where m.match_id=p_match_id and (v_context.actor_epochs->>m.id::text)::bigint is distinct from c.epoch
  ) then v_reason:='participation_changed';
  end if;
  if v_reason is not null and (v_context.reason is distinct from v_reason or v_context.state not in ('closed','expired','unavailable')) then
    update private.rematch_contexts set
      state=case when v_reason='expired' then 'expired' when v_reason='participation_changed' then 'closed' else 'unavailable' end,
      reason=v_reason,consenting_member_ids='{}',actor_epochs='{}',initiator_member_id=null,revision=revision+1
      where predecessor_match_id=p_match_id;
  end if;
end;
$$;

create function private.rematch_projection(p_actor uuid,p_match_id uuid,p_now timestamptz)
returns jsonb language plpgsql volatile security invoker set search_path='' as $$
declare v_context private.rematch_contexts%rowtype; v_selected uuid; v_available boolean; v_eligible boolean;
begin
  perform private.normalize_rematch(p_match_id,p_now);
  select * into v_context from private.rematch_contexts where predecessor_match_id=p_match_id;
  if not found then return null;
  end if;
  select selected_match_id into v_selected from private.participation_cursors where actor_user_id=p_actor;
  v_eligible:=v_context.state in ('eligible','offered','closed') and p_now<v_context.deadline;
  v_available:=v_context.successor_match_id is not null and exists(
    select 1 from public.matches s where s.id=v_context.successor_match_id and (
      s.status<>'lobby' or (select count(*) from public.match_members m join public.profiles p on p.id=m.auth_user_id
        where m.match_id=s.id and m.deleted_at is null)=2));
  return jsonb_build_object('revision',v_context.revision,'is_eligible',v_eligible,'state',v_context.state,
    'reason',v_context.reason,'generation',v_context.generation,
    'next_generation',case when v_context.state='closed' and v_eligible and v_context.generation<2147483647 then v_context.generation+1 else null end,
    'initiator_member_id',v_context.initiator_member_id,'consenting_member_ids',to_jsonb(v_context.consenting_member_ids),
    'selected_elsewhere',v_selected is not null and v_selected<>p_match_id and v_selected is distinct from v_context.successor_match_id,
    'deadline',v_context.deadline,'evaluated_at',p_now,'successor_match_id',v_context.successor_match_id,'successor_available',v_available);
end;
$$;

create function private.rematch_command_result(p_actor uuid,p_match_id uuid,p_generation integer,p_action text,p_epoch bigint)
returns jsonb language plpgsql volatile security invoker set search_path='' as $$
declare v_match public.matches%rowtype; v_ctx private.rematch_contexts%rowtype;
  v_member uuid; v_now timestamptz; v_epoch bigint; v_exclusions text[]; v_capacity integer;
  v_successor uuid:=extensions.gen_random_uuid(); v_code text; v_constraint text;
  v_new_creator uuid:=extensions.gen_random_uuid(); v_other_member uuid:=extensions.gen_random_uuid();
begin
  select * into v_match from public.matches where id=p_match_id for update;
  select id into v_member from public.match_members where match_id=p_match_id and auth_user_id=p_actor;
  if v_member is null then
    return private.error_response('not_a_match_member');
  end if;
  if v_match.status<>'completed' then
    return private.error_response('rematch_unavailable');
  end if;
  v_now:=clock_timestamp();
  perform private.normalize_rematch(p_match_id,v_now);
  select * into v_ctx from private.rematch_contexts where predecessor_match_id=p_match_id for update;
  if v_ctx.state='accepted' then
    if p_generation<>v_ctx.generation then
    return private.error_response('rematch_unavailable');
  end if;
    return jsonb_build_object('data',jsonb_build_object('predecessor_match_id',p_match_id,'generation',v_ctx.generation,
      'state','accepted','successor_match_id',v_ctx.successor_match_id));
  end if;
  if v_ctx.state='expired' then
    return private.error_response('rematch_expired');
  end if;
  select epoch into v_epoch from private.participation_cursors where actor_user_id=p_actor;
  if v_epoch is distinct from p_epoch then
    return private.error_response('participation_changed');
  end if;
  if p_action in ('cancel','decline') then
    if p_generation<>v_ctx.generation then
    return private.error_response('rematch_unavailable');
  end if;
    if v_ctx.state='unavailable' then
      return jsonb_build_object('data',jsonb_build_object('predecessor_match_id',p_match_id,'generation',v_ctx.generation,'state',v_ctx.state,'successor_match_id',null));
    end if;
    if v_ctx.state<>'offered' or (p_action='cancel')<>(v_member=any(v_ctx.consenting_member_ids)) then
      return private.error_response('rematch_unavailable');
    end if;
    update private.rematch_contexts set state='closed',reason=case when p_action='cancel' then 'cancelled' else 'declined' end,
      consenting_member_ids='{}',actor_epochs='{}',initiator_member_id=null,revision=revision+1 where predecessor_match_id=p_match_id;
  else
    if v_ctx.state='unavailable' then
    return private.error_response('rematch_unavailable');
  end if;
    if v_ctx.state='closed' and v_ctx.reason='participation_changed' and p_generation=v_ctx.generation then
      return private.error_response('participation_changed');
    end if;
    if v_ctx.state='closed' then
      if p_action<>'offer' or v_ctx.generation=2147483647 or p_generation<>v_ctx.generation+1 then
    return private.error_response('rematch_unavailable');
  end if;
    elsif p_generation<>v_ctx.generation or (v_ctx.state='eligible' and p_action<>'offer') then
      return private.error_response('rematch_unavailable');
    end if;
    if p_action='accept' and v_member=any(v_ctx.consenting_member_ids) then
    return private.error_response('rematch_unavailable');
  end if;
    select array_agg(revealed_answer order by round_number) into v_exclusions from public.rounds where match_id=p_match_id;
    perform 1 from private.words where is_active and is_answer order by word for share;
    select count(*) into v_capacity from private.words where is_active and is_answer and not(word=any(v_exclusions));
    if v_capacity<v_match.round_count then
    return private.error_response('answer_pool_unavailable');
  end if;
    v_now:=clock_timestamp();
    if v_now>=v_ctx.deadline then
      perform private.normalize_rematch(p_match_id,v_now);
      return private.error_response('rematch_expired');
    end if;
    if not private.consume_rate_limit(p_actor,null,'create',v_now) then
    return private.error_response('rate_limited');
  end if;
    if v_ctx.state in ('eligible','closed') then
      perform private.select_live_match(p_actor,p_match_id);
      update private.rematch_contexts set generation=p_generation,state='offered',reason=null,initiator_member_id=v_member,
        consenting_member_ids=array[v_member],actor_epochs=(select jsonb_object_agg(m.id::text,c.epoch)
          from public.match_members m join private.participation_cursors c on c.actor_user_id=m.auth_user_id where m.match_id=p_match_id),
        revision=revision+1 where predecessor_match_id=p_match_id;
    elsif not(v_member=any(v_ctx.consenting_member_ids)) then
      perform private.select_live_match(p_actor,p_match_id);
      loop
        v_code:=private.random_join_code();
        begin
          insert into public.matches(id,join_code,creator_member_id,created_at,updated_at,expires_at,minimum_client_build,round_count)
            values(v_successor,v_code,v_new_creator,v_now,v_now,v_now+interval '60 minutes',3,v_match.round_count);
          exit;
        exception when unique_violation then
          get stacked diagnostics v_constraint=constraint_name;
          if v_constraint<>'matches_join_code_key' then raise;
  end if;
        end;
      end loop;
      insert into public.match_members(id,match_id,auth_user_id,seat,joined_at,display_name_snapshot,avatar_seed_snapshot)
        select case when m.id=v_match.creator_member_id then v_new_creator else v_other_member end,v_successor,m.auth_user_id,
          case when m.id=v_match.creator_member_id then 1 else 2 end,v_now,p.display_name,p.avatar_seed
        from public.match_members m join public.profiles p on p.id=m.auth_user_id where m.match_id=p_match_id order by m.seat;
      insert into public.rounds(match_id,round_number,state) select v_successor,n,'pending' from generate_series(1,v_match.round_count) n;
      insert into private.rematch_successors values(v_successor,p_match_id,v_exclusions);
      perform private.select_live_match(m.auth_user_id,v_successor) from public.match_members m where m.match_id=p_match_id order by m.seat;
      update private.rematch_contexts set state='accepted',reason=null,successor_match_id=v_successor,
        consenting_member_ids=(select array_agg(id order by seat) from public.match_members where match_id=p_match_id),
        actor_epochs='{}',revision=revision+1 where predecessor_match_id=p_match_id;
    end if;
  end if;
  select * into v_ctx from private.rematch_contexts where predecessor_match_id=p_match_id;
  return jsonb_build_object('data',jsonb_build_object('predecessor_match_id',p_match_id,'generation',v_ctx.generation,
    'state',v_ctx.state,'successor_match_id',v_ctx.successor_match_id));
end;
$$;

create function public.rematch_command(p_user_id uuid,p_client_build integer,p_request_id uuid,p_predecessor_match_id uuid,
  p_generation integer,p_action text,p_expected_participation_epoch bigint)
returns jsonb language plpgsql volatile security invoker set search_path='' as $$
declare v_actors uuid[]; v_receipt private.live_command_receipts%rowtype; v_payload jsonb; v_response jsonb; v_current uuid[];
begin
  if p_user_id is null then
    return private.error_response('not_authenticated');
  end if;
  select array_agg(auth_user_id order by auth_user_id) into v_actors from public.match_members where match_id=p_predecessor_match_id and auth_user_id is not null;
  perform private.lock_live_actors(coalesce(v_actors,'{}')||array[p_user_id]);
  if not exists(select 1 from public.profiles where id=p_user_id) then
    return private.error_response('not_authenticated');
  end if;
  if p_client_build is null or p_client_build<3 then
    return private.error_response('client_update_required');
  end if;
  if p_request_id is null or p_predecessor_match_id is null or p_generation is null or p_generation<1
    or p_action is null or p_action not in ('offer','accept','cancel','decline') or p_expected_participation_epoch is null
    or p_expected_participation_epoch not between 0 and 9007199254740991 then
    return private.error_response('internal_error');
  end if;
  v_payload:=jsonb_build_object('client_build',p_client_build,'predecessor_match_id',p_predecessor_match_id,
    'generation',p_generation,'action',p_action,'expected_participation_epoch',p_expected_participation_epoch);
  select * into v_receipt from private.live_command_receipts where actor_user_id=p_user_id and request_id=p_request_id;
  if found then
    if v_receipt.kind='rematch' and v_receipt.payload=v_payload then return v_receipt.response;
  end if;
    return private.error_response('request_conflict');
  end if;
  perform 1 from public.matches where id=p_predecessor_match_id for update;
  select array_agg(auth_user_id order by auth_user_id) into v_current from public.match_members where match_id=p_predecessor_match_id and auth_user_id is not null;
  if exists(select 1 from unnest(v_current) x where not(x=any(coalesce(v_actors,'{}')))) then
    raise exception using errcode='40001',message='rematch_roster_changed';
  end if;
  v_response:=private.rematch_command_result(p_user_id,p_predecessor_match_id,p_generation,p_action,p_expected_participation_epoch);
  if coalesce(v_response->'error'->>'code','') not in ('rate_limited','internal_error','not_authenticated') then
    insert into private.live_command_receipts values(p_user_id,p_request_id,'rematch',v_payload,v_response);
  end if;
  return v_response;
end;
$$;
create or replace function public.match_snapshot(
  p_user_id uuid,
  p_client_build integer,
  p_match_id uuid
)
returns jsonb
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  v_now timestamptz := transaction_timestamp();
  v_match public.matches%rowtype;
  v_round public.rounds%rowtype;
  v_members jsonb;
  v_players jsonb;
  v_effective_state text;
  v_current jsonb;
  v_history jsonb := '[]'::jsonb;
  v_standings jsonb;
  v_through smallint;
  v_match_data jsonb;
  v_result jsonb;
  v_actors uuid[]; v_current_actors uuid[]; v_epoch bigint; v_selected uuid;
begin
  if p_client_build is null or p_client_build < 3 then
    return private.error_response('client_update_required');
  end if;
  if p_user_id is null or not exists(select 1 from public.profiles where id=p_user_id) then
    return private.error_response('not_authenticated');
  end if;
  if not exists(select 1 from public.match_members where match_id=p_match_id and auth_user_id=p_user_id) then
    return private.error_response('not_a_match_member');
  end if;
  select array_agg(auth_user_id order by auth_user_id) into v_actors
  from public.match_members where match_id=p_match_id and auth_user_id is not null;
  perform private.lock_live_actors(coalesce(v_actors,'{}')||array[p_user_id]);
  select * into v_match from public.matches where id=p_match_id for update;
  select array_agg(auth_user_id order by auth_user_id) into v_current_actors
  from public.match_members where match_id=p_match_id and auth_user_id is not null;
  if v_current_actors is distinct from v_actors then
    raise exception using errcode='40001',message='snapshot_roster_changed';
  end if;
  if not exists(select 1 from public.profiles where id=p_user_id) then
    return private.error_response('not_authenticated');
  end if;
  if v_match.id is null or not exists(select 1 from public.match_members
      where match_id=p_match_id and auth_user_id=p_user_id) then
    return private.error_response('not_a_match_member');
  end if;
  if p_client_build < v_match.minimum_client_build then
    return private.error_response('client_update_required');
  end if;

  select * into v_round
  from public.rounds
  where match_id = p_match_id and round_number = v_match.current_round
  for update;

  if v_round.state = 'countdown' and v_now >= v_round.ends_at then
    perform private.finalize_round(v_round.id);
    select * into v_match from public.matches where id = p_match_id;
    select * into v_round from public.rounds where id = v_round.id;
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', member.id,
        'seat', member.seat,
        'display_name', member.display_name_snapshot,
        'avatar_seed', member.avatar_seed_snapshot,
        'is_self', coalesce(member.auth_user_id = p_user_id, false),
        'is_deleted', member.deleted_at is not null
      ) order by member.seat
    ),
    '[]'::jsonb
  ) into v_members
  from public.match_members as member
  where member.match_id = p_match_id;

  for v_round in
    select * from public.rounds where match_id = p_match_id
      and (round_number = v_match.current_round or state = 'revealed')
    order by round_number
  loop
    v_effective_state := case
      when v_round.state = 'countdown' and v_now >= v_round.starts_at then 'playing'
      else v_round.state
    end;

    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'member_id', player.member_id,
          'state', player.state,
          'accepted_guess_count', player.accepted_guess_count,
          'solve_duration_ms', case
            when v_round.state = 'revealed' or member.auth_user_id = p_user_id
              then player.solve_duration_us / 1000
            else null
          end,
          'efficiency_points', case
            when v_round.state = 'revealed' or member.auth_user_id = p_user_id
              then player.efficiency_points
            else null
          end,
          'placement', case
            when v_round.state = 'revealed' then player.placement
            else null
          end,
          'board', case
            when v_round.state = 'revealed' or member.auth_user_id = p_user_id then
              coalesce(
                (
                  select jsonb_agg(
                    jsonb_build_object(
                      'sequence', guess.sequence,
                      'guess', guess.normalized_guess,
                      'feedback', to_jsonb(guess.feedback),
                      'submitted_at', guess.submitted_at
                    ) order by guess.sequence
                  )
                  from public.guesses as guess
                  where guess.round_id = player.round_id
                    and guess.member_id = player.member_id
                ),
                '[]'::jsonb
              )
            else null
          end
        ) order by member.seat
      ),
      '[]'::jsonb
    ) into v_players
    from public.player_rounds as player
    join public.match_members as member on member.id = player.member_id
    where player.round_id = v_round.id;

    v_result := jsonb_build_object(
        'number', v_round.round_number,
        'state', v_effective_state,
        'starts_at', v_round.starts_at,
        'ends_at', v_round.ends_at,
        'completed_at', v_round.completed_at,
        'answer', case when v_round.state = 'revealed' then v_round.revealed_answer else null end,
        'players', v_players
      );
    if v_round.round_number = v_match.current_round then v_current := v_result;
  end if;
    if v_round.state = 'revealed' then
      v_history := v_history || jsonb_build_array(v_result);
      v_through := v_round.round_number;
    end if;
  end loop;

  if v_through is not null then
    with totals as (
      select member.id as member_id, member.seat,
        count(*) filter (where player.state = 'solved') as rounds_solved,
        coalesce(sum(player.efficiency_points), 0) as efficiency_points,
        coalesce(sum(player.solve_duration_us), 0) as duration_us
      from public.match_members as member
      join public.player_rounds as player on player.member_id = member.id
      join public.rounds as round on round.id = player.round_id and round.state = 'revealed'
      where member.match_id = p_match_id
      group by member.id, member.seat
    ), ranked as (
      select *, rank() over (
        order by rounds_solved desc, efficiency_points desc, duration_us
      ) as placement from totals
    )
    select jsonb_build_object(
      'through_round', v_through,
      'is_final', v_match.status = 'completed',
      'players', jsonb_agg(jsonb_build_object(
        'member_id', member_id, 'rounds_solved', rounds_solved,
        'efficiency_points', efficiency_points,
        'total_solve_duration_ms', floor(duration_us / 1000),
        'placement', placement
      ) order by seat)
    ) into v_standings from ranked;
  end if;

  v_now:=clock_timestamp();
  select epoch,selected_match_id into v_epoch,v_selected
  from private.participation_cursors where actor_user_id=p_user_id;
  v_match_data := jsonb_build_object(
    'id', v_match.id, 'join_code', v_match.join_code,
    'creator_member_id', v_match.creator_member_id, 'mode', v_match.mode,
    'round_count', v_match.round_count, 'current_round', v_match.current_round,
    'status', v_match.status, 'expires_at', v_match.expires_at,
    'minimum_client_build', v_match.minimum_client_build,
    'revision', v_match.revision, 'started_at', v_match.started_at,
    'completed_at', v_match.completed_at, 'terminal_reason', v_match.terminal_reason,
    'admission',case when exists(select 1 from private.rematch_successors where match_id=p_match_id)
      then 'rematch' else 'code' end
  );
  v_result := jsonb_build_object(
    'version',3,'server_time',v_now,'match',v_match_data,
    'members',v_members,'round',v_current,'revealed_rounds',v_history,'standings',v_standings,
    'selection',jsonb_build_object('epoch',v_epoch,'is_selected',coalesce(v_selected=p_match_id,false)),
    'rematch',case when v_match.status='completed'
      then private.rematch_projection(p_user_id,p_match_id,v_now) else null end
  );
  return jsonb_build_object('data', v_result);
end;
$$;


-- Existing CREATE OR REPLACE ACLs stay unchanged.
revoke all on function private.lock_live_actors(uuid[]),private.select_live_match(uuid,uuid),private.publish_rematch_revision(),
  private.join_live_match(uuid,integer,text,text,uuid),private.normalize_rematch(uuid,timestamptz),private.rematch_projection(uuid,uuid,timestamptz),
  private.rematch_command_result(uuid,uuid,integer,text,bigint),
  public.join_match(uuid,integer,text,text,uuid,uuid),public.rematch_command(uuid,integer,uuid,uuid,integer,text,bigint) from public,anon,authenticated;
grant execute on function private.lock_live_actors(uuid[]),private.select_live_match(uuid,uuid),private.publish_rematch_revision(),
  private.join_live_match(uuid,integer,text,text,uuid),private.normalize_rematch(uuid,timestamptz),private.rematch_projection(uuid,uuid,timestamptz),
  private.rematch_command_result(uuid,uuid,integer,text,bigint),
  public.join_match(uuid,integer,text,text,uuid,uuid),public.rematch_command(uuid,integer,uuid,uuid,integer,text,bigint) to service_role;
drop function public.create_match(uuid,integer,text,uuid);
drop function public.start_match(uuid,integer,uuid);
drop function public.join_match(uuid,integer,text,text);
commit;
