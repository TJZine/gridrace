begin;

create extension if not exists pgcrypto with schema extensions;
create extension if not exists pg_cron;

create schema if not exists private;
create schema if not exists app_rls;

revoke all on schema private, app_rls from public, anon, authenticated;
revoke create on schema public from public;

alter default privileges for role postgres in schema public
  revoke all on tables from public, anon, authenticated;
alter default privileges for role postgres in schema public
  revoke execute on functions from public, anon, authenticated;
alter default privileges for role postgres in schema private
  revoke all on tables from public, anon, authenticated;
alter default privileges for role postgres in schema private
  revoke execute on functions from public, anon, authenticated;
alter default privileges for role postgres in schema app_rls
  revoke execute on functions from public, anon, authenticated;

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null,
  avatar_seed text not null,
  created_at timestamptz not null default transaction_timestamp(),
  updated_at timestamptz not null default transaction_timestamp(),
  constraint profiles_display_name_check check (
    char_length(display_name) between 2 and 16
    and display_name ~ '^[A-Za-z0-9][A-Za-z0-9 ''-]*[A-Za-z0-9]$'
    and display_name not like '%  %'
  ),
  constraint profiles_avatar_seed_check check (char_length(avatar_seed) between 1 and 64)
);

create table public.matches (
  id uuid primary key default extensions.gen_random_uuid(),
  join_code text not null unique,
  creator_member_id uuid not null,
  mode text not null default 'classic_live_v1',
  round_count smallint not null default 1,
  current_round smallint not null default 1,
  status text not null default 'lobby',
  created_at timestamptz not null default transaction_timestamp(),
  updated_at timestamptz not null default transaction_timestamp(),
  started_at timestamptz,
  completed_at timestamptz,
  expires_at timestamptz not null,
  minimum_client_build integer not null default 1,
  constraint matches_join_code_check check (join_code ~ '^[A-HJ-NP-Z2-9]{6}$'),
  constraint matches_mode_check check (mode = 'classic_live_v1'),
  constraint matches_round_count_check check (round_count = 1),
  constraint matches_current_round_check check (current_round = 1),
  constraint matches_status_check check (status in ('lobby', 'in_progress', 'completed')),
  constraint matches_build_check check (minimum_client_build >= 1),
  constraint matches_expiration_check check (expires_at > created_at),
  constraint matches_state_timestamps_check check (
    (status = 'lobby' and started_at is null and completed_at is null)
    or (status = 'in_progress' and started_at is not null and completed_at is null)
    or (status = 'completed' and started_at is not null and completed_at is not null)
  )
);

create table public.match_members (
  id uuid primary key default extensions.gen_random_uuid(),
  match_id uuid not null references public.matches(id) on delete cascade,
  auth_user_id uuid references auth.users(id) on delete set null,
  seat smallint not null,
  joined_at timestamptz not null default transaction_timestamp(),
  display_name_snapshot text not null,
  avatar_seed_snapshot text not null,
  deleted_at timestamptz,
  constraint match_members_match_id_id_key unique (match_id, id),
  constraint match_members_match_seat_key unique (match_id, seat),
  constraint match_members_seat_check check (seat between 1 and 2),
  constraint match_members_identity_check check (
    (auth_user_id is not null and deleted_at is null)
    or (
      auth_user_id is null
      and deleted_at is not null
      and display_name_snapshot = 'Deleted Player'
      and avatar_seed_snapshot = 'deleted-player'
    )
  )
);

create unique index match_members_match_user_key
  on public.match_members (match_id, auth_user_id)
  where auth_user_id is not null;
create index match_members_user_match_idx
  on public.match_members (auth_user_id, match_id)
  where auth_user_id is not null;

alter table public.matches
  add constraint matches_creator_member_fkey
  foreign key (id, creator_member_id)
  references public.match_members(match_id, id)
  deferrable initially deferred;

create table public.rounds (
  id uuid primary key default extensions.gen_random_uuid(),
  match_id uuid not null references public.matches(id) on delete cascade,
  round_number smallint not null default 1,
  state text not null default 'pending',
  starts_at timestamptz,
  ends_at timestamptz,
  completed_at timestamptz,
  revealed_answer text,
  constraint rounds_match_number_key unique (match_id, round_number),
  constraint rounds_number_check check (round_number = 1),
  constraint rounds_state_check check (state in ('pending', 'countdown', 'revealed')),
  constraint rounds_answer_check check (
    revealed_answer is null or revealed_answer ~ '^[a-z]{5}$'
  ),
  constraint rounds_timing_check check (
    (state = 'pending' and starts_at is null and ends_at is null and completed_at is null and revealed_answer is null)
    or (
      state = 'countdown'
      and starts_at is not null
      and ends_at = starts_at + interval '180 seconds'
      and completed_at is null
      and revealed_answer is null
    )
    or (
      state = 'revealed'
      and starts_at is not null
      and ends_at = starts_at + interval '180 seconds'
      and completed_at is not null
      and revealed_answer is not null
    )
  )
);

create index rounds_elapsed_idx
  on public.rounds (ends_at, id)
  where state = 'countdown';

create table public.player_rounds (
  round_id uuid not null references public.rounds(id) on delete cascade,
  member_id uuid not null references public.match_members(id) on delete cascade,
  state text not null default 'playing',
  started_at timestamptz not null,
  finished_at timestamptz,
  accepted_guess_count smallint not null default 0,
  solve_duration_us bigint,
  efficiency_points smallint,
  placement smallint,
  primary key (round_id, member_id),
  constraint player_rounds_state_check check (
    state in ('playing', 'solved', 'failed', 'timed_out', 'forfeited')
  ),
  constraint player_rounds_count_check check (accepted_guess_count between 0 and 6),
  constraint player_rounds_placement_check check (placement is null or placement between 1 and 2),
  constraint player_rounds_result_check check (
    (
      state = 'playing'
      and accepted_guess_count between 0 and 5
      and finished_at is null
      and solve_duration_us is null
      and efficiency_points is null
      and placement is null
    )
    or (
      state = 'solved'
      and accepted_guess_count between 1 and 6
      and finished_at is not null
      and solve_duration_us is not null
      and solve_duration_us >= 0
      and efficiency_points = 7 - accepted_guess_count
    )
    or (
      state = 'failed'
      and accepted_guess_count = 6
      and finished_at is not null
      and solve_duration_us is null
      and efficiency_points = 0
    )
    or (
      state in ('timed_out', 'forfeited')
      and finished_at is not null
      and solve_duration_us is null
      and efficiency_points = 0
    )
  )
);

create index player_rounds_round_state_idx
  on public.player_rounds (round_id, state);

create table public.guesses (
  id uuid primary key default extensions.gen_random_uuid(),
  request_id uuid not null,
  round_id uuid not null,
  member_id uuid not null,
  sequence smallint not null,
  normalized_guess text not null,
  feedback smallint[] not null,
  submitted_at timestamptz not null,
  constraint guesses_player_round_fkey
    foreign key (round_id, member_id)
    references public.player_rounds(round_id, member_id)
    on delete cascade,
  constraint guesses_round_member_sequence_key unique (round_id, member_id, sequence),
  constraint guesses_round_member_request_key unique (round_id, member_id, request_id),
  constraint guesses_sequence_check check (sequence between 1 and 6),
  constraint guesses_word_check check (normalized_guess ~ '^[a-z]{5}$'),
  constraint guesses_feedback_check check (
    array_ndims(feedback) = 1
    and array_length(feedback, 1) = 5
    and feedback <@ array[0, 1, 2]::smallint[]
  )
);

create table private.words (
  word text primary key,
  is_accepted boolean not null,
  is_answer boolean not null,
  is_active boolean not null,
  pack_version integer not null,
  constraint words_word_check check (word ~ '^[a-z]{5}$'),
  constraint words_answer_accepted_check check (not is_answer or is_accepted),
  constraint words_pack_version_check check (pack_version >= 1)
);

create index words_active_answer_idx
  on private.words (word)
  where is_active and is_answer;

create table private.round_secrets (
  round_id uuid primary key references public.rounds(id) on delete cascade,
  answer text not null references private.words(word),
  selected_at timestamptz not null
);

create table private.guess_requests (
  actor_user_id uuid not null references auth.users(id) on delete cascade,
  request_id uuid not null,
  match_id uuid not null references public.matches(id) on delete cascade,
  round_number smallint not null,
  normalized_guess text not null,
  guess_id uuid not null unique references public.guesses(id) on delete cascade,
  response_data jsonb not null,
  primary key (actor_user_id, request_id),
  constraint guess_requests_round_check check (round_number = 1),
  constraint guess_requests_word_check check (normalized_guess ~ '^[a-z]{5}$'),
  constraint guess_requests_response_check check (jsonb_typeof(response_data) = 'object')
);

create table private.user_rate_limits (
  actor_user_id uuid not null references auth.users(id) on delete cascade,
  action text not null,
  window_started_at timestamptz not null,
  attempt_count integer not null,
  primary key (actor_user_id, action, window_started_at),
  constraint user_rate_limits_action_check check (action in ('create', 'join', 'submit_guess')),
  constraint user_rate_limits_count_check check (attempt_count > 0)
);

create table private.ip_rate_limits (
  ip_hash text not null,
  action text not null,
  window_started_at timestamptz not null,
  attempt_count integer not null,
  primary key (ip_hash, action, window_started_at),
  constraint ip_rate_limits_hash_check check (ip_hash ~ '^[0-9a-f]{64}$'),
  constraint ip_rate_limits_action_check check (action in ('create', 'join', 'submit_guess')),
  constraint ip_rate_limits_count_check check (attempt_count > 0)
);

create or replace function private.touch_profile_updated_at()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.updated_at := transaction_timestamp();
  return new;
end;
$$;

create trigger profiles_touch_updated_at
before update on public.profiles
for each row execute function private.touch_profile_updated_at();

create or replace function private.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, display_name, avatar_seed)
  values (
    new.id,
    'Player ' || substring(replace(new.id::text, '-', '') from 1 for 6),
    extensions.gen_random_uuid()::text
  );
  return new;
end;
$$;

create trigger gridrace_create_profile
after insert on auth.users
for each row execute function private.handle_new_auth_user();

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

create or replace function private.normalize_guess(p_guess text)
returns text
language plpgsql
immutable
strict
security invoker
set search_path = ''
as $$
declare
  v_index integer;
  v_normalized text;
begin
  for v_index in 1..char_length(p_guess) loop
    if ascii(substring(p_guess from v_index for 1)) > 127 then
      return null;
    end if;
  end loop;

  v_normalized := translate(
    p_guess,
    'ABCDEFGHIJKLMNOPQRSTUVWXYZ',
    'abcdefghijklmnopqrstuvwxyz'
  );

  if char_length(v_normalized) <> 5 or v_normalized !~ '^[a-z]{5}$' then
    return null;
  end if;

  return v_normalized;
end;
$$;

create or replace function private.evaluate_guess(p_answer text, p_guess text)
returns smallint[]
language plpgsql
immutable
strict
security invoker
set search_path = ''
as $$
declare
  v_feedback smallint[] := array_fill(0::smallint, array[5]);
  v_remaining integer[] := array_fill(0, array[26]);
  v_index integer;
  v_letter_index integer;
begin
  if p_answer !~ '^[a-z]{5}$' or p_guess !~ '^[a-z]{5}$' then
    raise exception using errcode = '22023', message = 'invalid evaluator input';
  end if;

  for v_index in 1..5 loop
    v_letter_index := ascii(substring(p_answer from v_index for 1)) - 96;
    v_remaining[v_letter_index] := v_remaining[v_letter_index] + 1;
  end loop;

  for v_index in 1..5 loop
    if substring(p_answer from v_index for 1) = substring(p_guess from v_index for 1) then
      v_feedback[v_index] := 2;
      v_letter_index := ascii(substring(p_guess from v_index for 1)) - 96;
      v_remaining[v_letter_index] := v_remaining[v_letter_index] - 1;
    end if;
  end loop;

  for v_index in 1..5 loop
    if v_feedback[v_index] = 0 then
      v_letter_index := ascii(substring(p_guess from v_index for 1)) - 96;
      if v_remaining[v_letter_index] > 0 then
        v_feedback[v_index] := 1;
        v_remaining[v_letter_index] := v_remaining[v_letter_index] - 1;
      end if;
    end if;
  end loop;

  return v_feedback;
end;
$$;

create or replace function private.random_join_code()
returns text
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  v_alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  v_bytes bytea := extensions.gen_random_bytes(6);
  v_code text := '';
  v_index integer;
begin
  for v_index in 0..5 loop
    v_code := v_code || substring(v_alphabet from (get_byte(v_bytes, v_index) % 32) + 1 for 1);
  end loop;
  return v_code;
end;
$$;

create or replace function private.consume_rate_limit(
  p_actor_user_id uuid,
  p_ip_hash text,
  p_action text,
  p_now timestamptz
)
returns boolean
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  v_window_seconds integer;
  v_user_limit integer;
  v_ip_limit integer;
  v_window_start timestamptz;
  v_user_count integer;
  v_ip_count integer := 0;
begin
  case p_action
    when 'create' then
      v_window_seconds := 600;
      v_user_limit := 5;
      v_ip_limit := 30;
    when 'join' then
      v_window_seconds := 600;
      v_user_limit := 20;
      v_ip_limit := 100;
    when 'submit_guess' then
      v_window_seconds := 60;
      v_user_limit := 30;
      v_ip_limit := 120;
    else
      raise exception using errcode = '22023', message = 'unknown rate-limit action';
  end case;

  if p_ip_hash is not null and p_ip_hash !~ '^[0-9a-f]{64}$' then
    raise exception using errcode = '22023', message = 'invalid keyed IP hash';
  end if;

  v_window_start := to_timestamp(
    floor(extract(epoch from p_now) / v_window_seconds) * v_window_seconds
  );

  insert into private.user_rate_limits (
    actor_user_id,
    action,
    window_started_at,
    attempt_count
  )
  values (p_actor_user_id, p_action, v_window_start, 1)
  on conflict (actor_user_id, action, window_started_at)
  do update set attempt_count = private.user_rate_limits.attempt_count + 1
  returning attempt_count into v_user_count;

  if p_ip_hash is not null then
    insert into private.ip_rate_limits (
      ip_hash,
      action,
      window_started_at,
      attempt_count
    )
    values (p_ip_hash, p_action, v_window_start, 1)
    on conflict (ip_hash, action, window_started_at)
    do update set attempt_count = private.ip_rate_limits.attempt_count + 1
    returning attempt_count into v_ip_count;
  end if;

  return v_user_count <= v_user_limit
    and (p_ip_hash is null or v_ip_count <= v_ip_limit);
end;
$$;

create or replace function app_rls.is_match_member(p_match_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select (select auth.uid()) is not null
    and exists (
      select 1
      from public.match_members as member
      where member.match_id = p_match_id
        and member.auth_user_id = (select auth.uid())
    );
$$;

create or replace function app_rls.is_round_member(p_round_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select (select auth.uid()) is not null
    and exists (
      select 1
      from public.rounds as round
      join public.match_members as member on member.match_id = round.match_id
      where round.id = p_round_id
        and member.auth_user_id = (select auth.uid())
    );
$$;

create or replace function app_rls.owns_member(p_member_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select (select auth.uid()) is not null
    and exists (
      select 1
      from public.match_members as member
      where member.id = p_member_id
        and member.auth_user_id = (select auth.uid())
    );
$$;

create or replace function app_rls.can_read_guess(p_round_id uuid, p_member_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select app_rls.owns_member(p_member_id)
    or (
      app_rls.is_round_member(p_round_id)
      and exists (
        select 1
        from public.rounds as round
        where round.id = p_round_id and round.state = 'revealed'
      )
    );
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
  set status = 'completed', completed_at = v_now, updated_at = v_now
  where id = v_match_id;

  return true;
end;
$$;

create or replace function private.finalize_expired_rounds()
returns integer
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  v_round_id uuid;
  v_count integer := 0;
begin
  for v_round_id in
    select id
    from public.rounds
    where state = 'countdown' and ends_at <= transaction_timestamp()
    order by ends_at, id
  loop
    if private.finalize_round(v_round_id) then
      v_count := v_count + 1;
    end if;
  end loop;
  return v_count;
end;
$$;

create or replace function public.create_match(
  p_user_id uuid,
  p_client_build integer,
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
  v_match_id uuid := extensions.gen_random_uuid();
  v_member_id uuid := extensions.gen_random_uuid();
  v_code text;
  v_constraint_name text;
  v_profile public.profiles%rowtype;
begin
  if p_user_id is null then
    return private.error_response('not_authenticated');
  end if;

  select * into v_profile from public.profiles where id = p_user_id;
  if not found then
    return private.error_response('not_authenticated');
  end if;

  if not private.consume_rate_limit(p_user_id, p_ip_hash, 'create', v_now) then
    return private.error_response('rate_limited');
  end if;

  if p_client_build < 1 then
    return private.error_response('client_update_required');
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
        minimum_client_build
      )
      values (
        v_match_id,
        v_code,
        v_member_id,
        v_now,
        v_now,
        v_now + interval '60 minutes',
        1
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
  values (v_match_id, 1, 'pending');

  return jsonb_build_object('data', jsonb_build_object('match_id', v_match_id));
end;
$$;

create or replace function public.join_match(
  p_user_id uuid,
  p_client_build integer,
  p_join_code text,
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
  v_code text;
  v_match public.matches%rowtype;
  v_profile public.profiles%rowtype;
  v_existing_member uuid;
  v_member_count integer;
begin
  if p_user_id is null then
    return private.error_response('not_authenticated');
  end if;

  select * into v_profile from public.profiles where id = p_user_id;
  if not found then
    return private.error_response('not_authenticated');
  end if;

  if not private.consume_rate_limit(p_user_id, p_ip_hash, 'join', v_now) then
    return private.error_response('rate_limited');
  end if;

  if p_client_build < 1 then
    return private.error_response('client_update_required');
  end if;

  if p_join_code is null then
    return private.error_response('match_not_joinable');
  end if;

  v_code := translate(
    p_join_code,
    'abcdefghijklmnopqrstuvwxyz',
    'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
  );
  if v_code !~ '^[A-HJ-NP-Z2-9]{6}$' then
    return private.error_response('match_not_joinable');
  end if;

  select * into v_match
  from public.matches
  where join_code = v_code
  for update;

  if not found then
    return private.error_response('match_not_joinable');
  end if;

  if p_client_build < v_match.minimum_client_build then
    return private.error_response('client_update_required');
  end if;

  select id into v_existing_member
  from public.match_members
  where match_id = v_match.id and auth_user_id = p_user_id;
  if found then
    return jsonb_build_object('data', jsonb_build_object('match_id', v_match.id));
  end if;

  if v_now >= v_match.expires_at then
    return private.error_response('room_expired');
  end if;

  if v_match.status <> 'lobby' then
    return private.error_response('match_not_joinable');
  end if;

  select count(*) into v_member_count
  from public.match_members
  where match_id = v_match.id;
  if v_member_count >= 2 then
    return private.error_response('room_full');
  end if;

  insert into public.match_members (
    match_id,
    auth_user_id,
    seat,
    joined_at,
    display_name_snapshot,
    avatar_seed_snapshot
  )
  values (
    v_match.id,
    p_user_id,
    2,
    v_now,
    v_profile.display_name,
    v_profile.avatar_seed
  );

  update public.matches set updated_at = v_now where id = v_match.id;
  return jsonb_build_object('data', jsonb_build_object('match_id', v_match.id));
end;
$$;

create or replace function public.start_match(
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
  v_member_id uuid;
  v_member_count integer;
  v_round_id uuid;
  v_answer text;
begin
  if p_user_id is null or not exists (select 1 from public.profiles where id = p_user_id) then
    return private.error_response('not_authenticated');
  end if;

  select * into v_match from public.matches where id = p_match_id for update;
  if not found then
    return private.error_response('not_a_match_member');
  end if;

  if p_client_build < v_match.minimum_client_build then
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

  if v_match.status = 'in_progress' then
    return jsonb_build_object('data', jsonb_build_object('match_id', p_match_id));
  elsif v_match.status = 'completed' then
    return private.error_response('round_already_finished');
  end if;

  if v_now >= v_match.expires_at then
    return private.error_response('room_expired');
  end if;

  select count(*) into v_member_count
  from public.match_members
  where match_id = p_match_id;
  if v_member_count <> 2 then
    return private.error_response('not_enough_players');
  end if;

  select id into v_round_id
  from public.rounds
  where match_id = p_match_id and round_number = 1
  for update;

  perform 1
  from public.match_members
  where match_id = p_match_id
  order by seat
  for update;

  select word into v_answer
  from private.words
  where is_active and is_answer
  order by random()
  limit 1;
  if v_answer is null then
    return private.error_response('internal_error');
  end if;

  update public.matches
  set status = 'in_progress', started_at = v_now, updated_at = v_now
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
  if p_user_id is null or not exists (select 1 from public.profiles where id = p_user_id) then
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

  if p_client_build < v_match.minimum_client_build then
    return private.error_response('client_update_required');
  end if;

  select id into v_member_id
  from public.match_members
  where match_id = p_match_id and auth_user_id = p_user_id;
  if not found then
    return private.error_response('not_a_match_member');
  end if;

  if p_round_number <> 1 then
    return private.error_response('round_not_active');
  end if;

  select * into v_round
  from public.rounds
  where match_id = p_match_id and round_number = p_round_number
  for update;

  if v_round.state = 'revealed' or v_match.status = 'completed' then
    return private.error_response('round_already_finished');
  elsif v_round.state <> 'countdown' or v_now < v_round.starts_at then
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
    'efficiency_points', v_efficiency,
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

  if p_client_build < v_match.minimum_client_build then
    return private.error_response('client_update_required');
  end if;

  select * into v_round
  from public.rounds
  where match_id = p_match_id and round_number = 1
  for update;

  if v_round.state = 'countdown' and v_now >= v_round.ends_at then
    perform private.finalize_round(v_round.id);
    select * into v_match from public.matches where id = p_match_id;
    select * into v_round from public.rounds where id = v_round.id;
  end if;

  v_effective_state := case
    when v_round.state = 'countdown' and v_now >= v_round.starts_at then 'playing'
    else v_round.state
  end;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', member.id,
        'seat', member.seat,
        'display_name', member.display_name_snapshot,
        'avatar_seed', member.avatar_seed_snapshot,
        'is_self', member.auth_user_id = p_user_id,
        'is_deleted', member.deleted_at is not null
      ) order by member.seat
    ),
    '[]'::jsonb
  ) into v_members
  from public.match_members as member
  where member.match_id = p_match_id;

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

  return jsonb_build_object(
    'data', jsonb_build_object(
      'version', 1,
      'server_time', v_now,
      'match', jsonb_build_object(
        'id', v_match.id,
        'join_code', v_match.join_code,
        'creator_member_id', v_match.creator_member_id,
        'mode', v_match.mode,
        'round_count', v_match.round_count,
        'current_round', v_match.current_round,
        'status', v_match.status,
        'expires_at', v_match.expires_at,
        'minimum_client_build', v_match.minimum_client_build
      ),
      'members', v_members,
      'round', jsonb_build_object(
        'number', v_round.round_number,
        'state', v_effective_state,
        'starts_at', v_round.starts_at,
        'ends_at', v_round.ends_at,
        'completed_at', v_round.completed_at,
        'answer', case when v_round.state = 'revealed' then v_round.revealed_answer else null end,
        'players', v_players
      )
    )
  );
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

  if not exists (select 1 from public.profiles where id = p_user_id) then
    return jsonb_build_object('data', jsonb_build_object('deleted', true));
  end if;

  delete from private.user_rate_limits where actor_user_id = p_user_id;

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
    where match_id = v_match_id and round_number = 1
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

    update public.matches set updated_at = v_now where id = v_match_id;

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

alter table public.profiles enable row level security;
alter table public.matches enable row level security;
alter table public.match_members enable row level security;
alter table public.rounds enable row level security;
alter table public.player_rounds enable row level security;
alter table public.guesses enable row level security;

create policy profiles_select_own
on public.profiles for select to authenticated
using ((select auth.uid()) is not null and id = (select auth.uid()));

create policy profiles_update_own
on public.profiles for update to authenticated
using ((select auth.uid()) is not null and id = (select auth.uid()))
with check ((select auth.uid()) is not null and id = (select auth.uid()));

create policy matches_select_rostered
on public.matches for select to authenticated
using ((select app_rls.is_match_member(id)));

create policy match_members_select_rostered
on public.match_members for select to authenticated
using ((select app_rls.is_match_member(match_id)));

create policy rounds_select_rostered
on public.rounds for select to authenticated
using ((select app_rls.is_match_member(match_id)));

create policy player_rounds_select_rostered
on public.player_rounds for select to authenticated
using ((select app_rls.is_round_member(round_id)));

create policy guesses_select_visible
on public.guesses for select to authenticated
using ((select app_rls.can_read_guess(round_id, member_id)));

revoke all on all tables in schema public from public, anon, authenticated;
revoke all on all tables in schema private from public, anon, authenticated;
revoke execute on all functions in schema public from public, anon, authenticated;
revoke execute on all functions in schema private from public, anon, authenticated;
revoke execute on all functions in schema app_rls from public, anon, authenticated;
revoke all on schema cron from public, anon, authenticated;
revoke all on all tables in schema cron from public, anon, authenticated;
revoke execute on all routines in schema cron from public, anon, authenticated;

grant usage on schema public to authenticated, service_role;
grant usage on schema private to service_role;
grant usage on schema app_rls to authenticated, service_role;

grant select (id, display_name, avatar_seed, created_at, updated_at),
  update (display_name, avatar_seed)
on public.profiles to authenticated;

grant select on public.matches to authenticated;
grant select (
  id,
  match_id,
  seat,
  joined_at,
  display_name_snapshot,
  avatar_seed_snapshot,
  deleted_at
) on public.match_members to authenticated;
grant select on public.rounds to authenticated;
grant select (round_id, member_id, state, accepted_guess_count)
  on public.player_rounds to authenticated;
grant select on public.guesses to authenticated;

grant all on all tables in schema public to service_role;
grant all on all tables in schema private to service_role;

grant execute on function app_rls.is_match_member(uuid) to authenticated, service_role;
grant execute on function app_rls.is_round_member(uuid) to authenticated, service_role;
grant execute on function app_rls.owns_member(uuid) to authenticated, service_role;
grant execute on function app_rls.can_read_guess(uuid, uuid) to authenticated, service_role;

grant execute on function public.create_match(uuid, integer, text) to service_role;
grant execute on function public.join_match(uuid, integer, text, text) to service_role;
grant execute on function public.start_match(uuid, integer, uuid) to service_role;
grant execute on function public.submit_guess(uuid, integer, uuid, smallint, uuid, text, text)
  to service_role;
grant execute on function public.match_snapshot(uuid, integer, uuid) to service_role;
grant execute on function public.delete_account(uuid, integer) to service_role;

grant execute on all functions in schema private to service_role;

alter publication supabase_realtime add table public.matches;

select cron.schedule(
  'gridrace-finalize-rounds',
  '* * * * *',
  'select private.finalize_expired_rounds()'
);

commit;
