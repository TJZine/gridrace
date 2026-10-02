begin;

-- Existing rooms and receipts remain one-round/floor-1. No secret is selected
-- until the creator starts that specific round under the match lock.
alter table public.matches
  add column terminal_reason text,
  drop constraint matches_round_count_check,
  drop constraint matches_current_round_check,
  drop constraint matches_status_check,
  drop constraint matches_state_timestamps_check,
  add constraint matches_round_count_check check (round_count in (1, 3, 5)),
  add constraint matches_current_round_check check (current_round between 1 and round_count),
  add constraint matches_status_check check (status in ('lobby', 'in_progress', 'completed', 'incomplete')),
  add constraint matches_state_timestamps_check check (
    (status = 'lobby' and current_round = 1 and started_at is null and completed_at is null and terminal_reason is null)
    or (status = 'in_progress' and started_at is not null and completed_at is null
        and (terminal_reason is null or (terminal_reason = 'account_deleted' and current_round < round_count)))
    or (status = 'incomplete' and started_at is not null and completed_at is null
        and terminal_reason is not distinct from 'account_deleted' and current_round < round_count)
    or (status = 'completed' and current_round = round_count and started_at is not null
        and completed_at is not null and terminal_reason is null)
  );
alter table public.rounds drop constraint rounds_number_check,
  add constraint rounds_number_check check (round_number between 1 and 5);
alter table private.guess_requests drop constraint guess_requests_round_check,
  add constraint guess_requests_round_check check (round_number between 1 and 5);
alter table private.create_requests add column round_count smallint not null default 1,
  add constraint create_requests_round_count_check check (round_count in (1, 3, 5));

-- terminal_reason intentionally has no authenticated column grant/publication.
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

  if p_client_build is null or p_client_build < 1 then
    return private.error_response('client_update_required');
  end if;

  if p_round_count is null or p_round_count not in (1, 3, 5) or (p_client_build = 1 and p_round_count <> 1) then
    return private.error_response('invalid_match_configuration');
  end if;

  if p_request_id is null then
    return private.error_response('internal_error');
  end if;

  -- Serialize creation with account deletion and same-actor retries.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_user_id::text, 1)
  );

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
        case when p_client_build = 1 then 1 else 2 end,
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

  return jsonb_build_object('data', jsonb_build_object('match_id', v_match_id));
end;
$$;

create or replace function public.create_match(
  p_user_id uuid, p_client_build integer, p_ip_hash text, p_request_id uuid
)
returns jsonb language sql volatile security invoker set search_path = ''
as $$
  select public.create_match(p_user_id, p_client_build, p_ip_hash, p_request_id, 1::smallint);
$$;

create or replace function private.finalize_round(p_round_id uuid)
returns boolean
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  v_match_id uuid;
  v_round public.rounds%rowtype;
  v_now timestamptz := transaction_timestamp();
begin
  select round.match_id into v_match_id
  from public.rounds as round
  where round.id = p_round_id;

  if v_match_id is null then
    return false;
  end if;

  perform 1 from public.matches where id = v_match_id for update;
  select * into v_round from public.rounds where id = p_round_id for update;

  if v_round.state = 'revealed' then
    return true;
  end if;

  if v_round.state <> 'countdown' then
    return false;
  end if;

  perform 1
  from public.player_rounds as player
  join public.match_members as member on member.id = player.member_id
  where player.round_id = p_round_id
  order by member.seat
  for update of player;

  if v_now >= v_round.ends_at then
    update public.player_rounds
    set state = 'timed_out',
        finished_at = v_now,
        efficiency_points = 0
    where round_id = p_round_id and state = 'playing';
  elsif exists (
    select 1 from public.player_rounds
    where round_id = p_round_id and state = 'playing'
  ) then
    return false;
  end if;

  with ranked as (
    select
      player.member_id,
      rank() over (
        order by
          case when player.state = 'solved' then 0 else 1 end,
          player.accepted_guess_count,
          case when player.state = 'solved' then player.solve_duration_us else 0 end
      )::smallint as placement
    from public.player_rounds as player
    where player.round_id = p_round_id
  )
  update public.player_rounds as player
  set placement = ranked.placement
  from ranked
  where player.round_id = p_round_id
    and player.member_id = ranked.member_id;

  update public.rounds as round
  set state = 'revealed',
      completed_at = v_now,
      revealed_answer = secret.answer
  from private.round_secrets as secret
  where round.id = p_round_id and secret.round_id = round.id;

  if not found then
    raise exception using errcode = '23514', message = 'round secret missing';
  end if;

  update public.matches
  set status = case
        when current_round = round_count then 'completed'
        when terminal_reason = 'account_deleted' then 'incomplete'
        else 'in_progress' end,
      completed_at = case when current_round = round_count then v_now else null end,
      terminal_reason = case when current_round = round_count then null else terminal_reason end,
      updated_at = v_now
  where id = v_match_id;

  return true;
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
begin
  if p_user_id is null then
    return private.error_response('not_authenticated');
  end if;

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_user_id::text, 1));
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
  if not found then return private.error_response('round_not_active'); end if;
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

  select word into v_answer
  from private.words
  where is_active and is_answer and not exists (
    select 1 from private.round_secrets as secret
    join public.rounds as prior on prior.id = secret.round_id
    where prior.match_id = p_match_id and secret.answer = words.word
  )
  order by random()
  limit 1;
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

  return jsonb_build_object('data', jsonb_build_object('match_id', p_match_id));
end;
$$;

-- The legacy entry always targets round 1 and preserves its completed error.
create or replace function public.start_match(
  p_user_id uuid, p_client_build integer, p_match_id uuid
)
returns jsonb language plpgsql volatile security invoker set search_path = ''
as $$
declare v_response jsonb;
begin
  v_response := public.start_match(p_user_id, p_client_build, p_match_id, 1::smallint);
  if v_response ? 'data' and exists (
    select 1 from public.matches where id = p_match_id and status = 'completed'
  ) then
    return private.error_response('round_already_finished');
  end if;
  return v_response;
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
  if p_user_id is null then
    return private.error_response('not_authenticated');
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_user_id::text, 1)
  );

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

  if p_round_number is null or p_round_number < 1 or p_round_number > v_match.round_count
    or (p_client_build = 1 and p_round_number <> 1) then
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

  return jsonb_build_object('data', v_response);
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
begin
  if p_user_id is null or not exists (select 1 from public.profiles where id = p_user_id) then
    return private.error_response('not_authenticated');
  end if;

  select * into v_match from public.matches where id = p_match_id for update;
  if not found or not exists (
    select 1 from public.match_members
    where match_id = p_match_id and auth_user_id = p_user_id
  ) then
    return private.error_response('not_a_match_member');
  end if;

  if p_client_build is null or p_client_build < v_match.minimum_client_build then
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
    if v_round.round_number = v_match.current_round then v_current := v_result; end if;
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

  v_match_data := jsonb_build_object(
    'id', v_match.id, 'join_code', v_match.join_code,
    'creator_member_id', v_match.creator_member_id, 'mode', v_match.mode,
    'round_count', v_match.round_count, 'current_round', v_match.current_round,
    'status', v_match.status, 'expires_at', v_match.expires_at,
    'minimum_client_build', v_match.minimum_client_build
  );
  v_result := jsonb_build_object(
    'version', case when p_client_build = 1 then 1 else 2 end,
    'server_time', v_now, 'match', v_match_data,
    'members', v_members, 'round', v_current
  );
  if p_client_build >= 2 then
    v_result := v_result || jsonb_build_object(
      'match', v_match_data || jsonb_build_object(
        'revision', v_match.revision, 'started_at', v_match.started_at,
        'completed_at', v_match.completed_at, 'terminal_reason', v_match.terminal_reason
      ),
      'revealed_rounds', v_history, 'standings', v_standings
    );
  end if;
  return jsonb_build_object('data', v_result);
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

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_user_id::text, 1)
  );

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

revoke all on function public.create_match(uuid, integer, text, uuid, smallint),
  public.start_match(uuid, integer, uuid, smallint) from public, anon, authenticated;
grant execute on function public.create_match(uuid, integer, text, uuid, smallint),
  public.start_match(uuid, integer, uuid, smallint) to service_role;

commit;
