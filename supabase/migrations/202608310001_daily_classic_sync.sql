begin;

create or replace function private.daily_sync_error(p_code text)
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
        when 'invalid_daily_payload' then 'This Daily Classic data could not be synchronized.'
        else 'Something went wrong. Try again.'
      end
    )
  );
$$;

create or replace function private.valid_daily_identity(
  p_puzzle_id text,
  p_puzzle_number integer,
  p_puzzle_day integer,
  p_word_pack_id text,
  p_schedule_version integer
)
returns boolean
language sql
immutable
security invoker
set search_path = ''
as $$
  select p_puzzle_day between 0 and 100000
    and p_puzzle_number between 1 and 1000000
    and p_schedule_version between 1 and 1000000
    and p_word_pack_id ~ '^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$'
    and p_puzzle_id = 'daily-classic-'
      || to_char(date '1970-01-01' + p_puzzle_day, 'YYYY-MM-DD');
$$;

create or replace function private.valid_daily_guesses(
  p_guesses jsonb,
  p_max_count integer,
  p_allow_final_solve boolean
)
returns boolean
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_guess jsonb;
  v_accepted_at timestamptz;
  v_previous_at timestamptz;
  v_count integer;
begin
  if jsonb_typeof(p_guesses) <> 'array' then
    return false;
  end if;

  v_count := jsonb_array_length(p_guesses);
  if v_count < 0 or v_count > p_max_count then
    return false;
  end if;

  for v_index in 0..v_count - 1 loop
    v_guess := p_guesses -> v_index;
    if jsonb_typeof(v_guess) <> 'object'
      or (v_guess - array['word', 'feedback', 'accepted_at']) <> '{}'::jsonb
      or not (v_guess ?& array['word', 'feedback', 'accepted_at'])
      or jsonb_typeof(v_guess -> 'word') <> 'string'
      or (v_guess ->> 'word') !~ '^[a-z]{5}$'
      or jsonb_typeof(v_guess -> 'feedback') <> 'array'
      or jsonb_array_length(v_guess -> 'feedback') <> 5
      or jsonb_typeof(v_guess -> 'accepted_at') <> 'string'
      or (v_guess ->> 'accepted_at') !~
        '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?(Z|[+-][0-9]{2}:[0-9]{2})$'
      or exists (
        select 1
        from jsonb_array_elements(v_guess -> 'feedback') as value
        where jsonb_typeof(value) <> 'number'
          or value #>> '{}' !~ '^[0-2]$'
      )
    then
      return false;
    end if;

    v_accepted_at := (v_guess ->> 'accepted_at')::timestamptz;
    if not isfinite(v_accepted_at)
      or (v_previous_at is not null and v_accepted_at < v_previous_at)
      or (
        not p_allow_final_solve
        and not exists (
          select 1
          from jsonb_array_elements(v_guess -> 'feedback') as value
          where value <> '2'::jsonb
        )
      )
      or (
        p_allow_final_solve
        and v_index < v_count - 1
        and not exists (
          select 1
          from jsonb_array_elements(v_guess -> 'feedback') as value
          where value <> '2'::jsonb
        )
      )
    then
      return false;
    end if;
    v_previous_at := v_accepted_at;
  end loop;

  return true;
exception when others then
  return false;
end;
$$;

create or replace function private.normalize_daily_guesses(p_guesses jsonb)
returns jsonb
language sql
stable
strict
security invoker
set search_path = ''
as $$
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'word', item.value ->> 'word',
        'feedback', item.value -> 'feedback',
        'accepted_at', to_char(
          (item.value ->> 'accepted_at')::timestamptz at time zone 'UTC',
          'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'
        )
      )
      order by item.ordinality
    ),
    '[]'::jsonb
  )
  from jsonb_array_elements(p_guesses) with ordinality as item(value, ordinality);
$$;

create or replace function private.daily_guesses_are_prefix(
  p_shorter jsonb,
  p_longer jsonb
)
returns boolean
language plpgsql
immutable
strict
security invoker
set search_path = ''
as $$
declare
  v_shorter_count integer;
begin
  if jsonb_typeof(p_shorter) <> 'array' or jsonb_typeof(p_longer) <> 'array' then
    return false;
  end if;

  v_shorter_count := jsonb_array_length(p_shorter);
  if v_shorter_count > jsonb_array_length(p_longer) then
    return false;
  end if;

  for v_index in 0..v_shorter_count - 1 loop
    if p_shorter -> v_index is distinct from p_longer -> v_index then
      return false;
    end if;
  end loop;
  return true;
exception when others then
  return false;
end;
$$;

create or replace function private.valid_daily_result(
  p_guesses jsonb,
  p_outcome text,
  p_guess_count integer,
  p_client_completed_at timestamptz
)
returns boolean
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_last_feedback jsonb;
  v_last_accepted_at timestamptz;
  v_solved boolean;
begin
  if p_guess_count not between 1 and 6
    or p_outcome not in ('solved', 'failed')
    or not isfinite(p_client_completed_at)
    or not private.valid_daily_guesses(p_guesses, 6, true)
    or jsonb_array_length(p_guesses) <> p_guess_count
  then
    return false;
  end if;

  v_last_feedback := p_guesses -> (p_guess_count - 1) -> 'feedback';
  v_solved := not exists (
    select 1 from jsonb_array_elements(v_last_feedback) as value
    where value <> '2'::jsonb
  );
  v_last_accepted_at := (p_guesses -> (p_guess_count - 1) ->> 'accepted_at')::timestamptz;

  return v_last_accepted_at <= p_client_completed_at
    and (
      (p_outcome = 'solved' and v_solved)
      or (p_outcome = 'failed' and p_guess_count = 6 and not v_solved)
    );
exception when others then
  return false;
end;
$$;

create table public.daily_progress (
  user_id uuid not null references auth.users(id) on delete cascade,
  puzzle_id text not null,
  puzzle_number integer not null,
  puzzle_day integer not null,
  word_pack_id text not null,
  schedule_version integer not null,
  hard_mode_enabled boolean not null,
  guesses jsonb not null,
  revision bigint not null default 1,
  server_updated_at timestamptz not null default transaction_timestamp(),
  primary key (user_id, puzzle_id),
  constraint daily_progress_identity_check check (
    private.valid_daily_identity(
      puzzle_id,
      puzzle_number,
      puzzle_day,
      word_pack_id,
      schedule_version
    )
  ),
  constraint daily_progress_guesses_check check (
    private.valid_daily_guesses(guesses, 5, false)
  ),
  constraint daily_progress_revision_check check (revision > 0)
);

create table public.daily_imported_results (
  user_id uuid not null references auth.users(id) on delete cascade,
  puzzle_id text not null,
  puzzle_number integer not null,
  puzzle_day integer not null,
  word_pack_id text not null,
  schedule_version integer not null,
  hard_mode_enabled boolean not null,
  guesses jsonb not null,
  outcome text not null,
  guess_count smallint not null,
  client_completed_at timestamptz not null,
  server_imported_at timestamptz not null default transaction_timestamp(),
  primary key (user_id, puzzle_id),
  constraint daily_imported_results_identity_check check (
    private.valid_daily_identity(
      puzzle_id,
      puzzle_number,
      puzzle_day,
      word_pack_id,
      schedule_version
    )
  ),
  constraint daily_imported_results_payload_check check (
    private.valid_daily_result(guesses, outcome, guess_count, client_completed_at)
  )
);

alter table public.daily_progress enable row level security;
alter table public.daily_imported_results enable row level security;

create policy daily_progress_select_own
on public.daily_progress for select to authenticated
using ((select auth.uid()) is not null and user_id = (select auth.uid()));

create policy daily_imported_results_select_own
on public.daily_imported_results for select to authenticated
using ((select auth.uid()) is not null and user_id = (select auth.uid()));

create or replace function public.sync_daily_progress(
  p_puzzle_id text,
  p_puzzle_number integer,
  p_puzzle_day integer,
  p_word_pack_id text,
  p_schedule_version integer,
  p_hard_mode_enabled boolean,
  p_guesses jsonb,
  p_expected_revision bigint default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_guesses jsonb;
  v_progress public.daily_progress%rowtype;
  v_result public.daily_imported_results%rowtype;
  v_same_identity boolean;
begin
  if v_user_id is null then
    return private.daily_sync_error('not_authenticated');
  end if;

  if private.valid_daily_identity(
      p_puzzle_id,
      p_puzzle_number,
      p_puzzle_day,
      p_word_pack_id,
      p_schedule_version
    ) is not true
    or p_hard_mode_enabled is null
    or private.valid_daily_guesses(p_guesses, 5, false) is not true
    or (p_expected_revision is not null and p_expected_revision < 1)
  then
    return private.daily_sync_error('invalid_daily_payload');
  end if;

  v_guesses := private.normalize_daily_guesses(p_guesses);
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(v_user_id::text || ':' || p_puzzle_id, 0)
  );

  select * into v_result
  from public.daily_imported_results
  where user_id = v_user_id and puzzle_id = p_puzzle_id;

  if found then
    v_same_identity := v_result.puzzle_number = p_puzzle_number
      and v_result.puzzle_day = p_puzzle_day
      and v_result.word_pack_id = p_word_pack_id
      and v_result.schedule_version = p_schedule_version
      and v_result.hard_mode_enabled = p_hard_mode_enabled;

    if v_same_identity
      and private.daily_guesses_are_prefix(v_guesses, v_result.guesses)
    then
      delete from public.daily_progress
      where user_id = v_user_id and puzzle_id = p_puzzle_id;
      return jsonb_build_object(
        'status', 'completed',
        'result', to_jsonb(v_result)
      );
    end if;

    return jsonb_build_object(
      'status', 'conflict',
      'result', to_jsonb(v_result)
    );
  end if;

  select * into v_progress
  from public.daily_progress
  where user_id = v_user_id and puzzle_id = p_puzzle_id
  for update;

  if not found then
    insert into public.daily_progress (
      user_id,
      puzzle_id,
      puzzle_number,
      puzzle_day,
      word_pack_id,
      schedule_version,
      hard_mode_enabled,
      guesses
    ) values (
      v_user_id,
      p_puzzle_id,
      p_puzzle_number,
      p_puzzle_day,
      p_word_pack_id,
      p_schedule_version,
      p_hard_mode_enabled,
      v_guesses
    )
    returning * into v_progress;

    return jsonb_build_object('status', 'inserted', 'progress', to_jsonb(v_progress));
  end if;

  v_same_identity := v_progress.puzzle_number = p_puzzle_number
    and v_progress.puzzle_day = p_puzzle_day
    and v_progress.word_pack_id = p_word_pack_id
    and v_progress.schedule_version = p_schedule_version
    and v_progress.hard_mode_enabled = p_hard_mode_enabled;

  if not v_same_identity
    and not (
      v_progress.puzzle_number = p_puzzle_number
      and v_progress.puzzle_day = p_puzzle_day
      and v_progress.word_pack_id = p_word_pack_id
      and v_progress.schedule_version = p_schedule_version
      and jsonb_array_length(v_progress.guesses) = 0
      and jsonb_array_length(v_guesses) = 0
    )
  then
    return jsonb_build_object('status', 'conflict', 'progress', to_jsonb(v_progress));
  end if;

  if not v_same_identity then
    if p_expected_revision is not null and p_expected_revision <> v_progress.revision then
      return jsonb_build_object('status', 'conflict', 'progress', to_jsonb(v_progress));
    end if;

    update public.daily_progress
    set hard_mode_enabled = p_hard_mode_enabled,
        revision = revision + 1,
        server_updated_at = transaction_timestamp()
    where user_id = v_user_id and puzzle_id = p_puzzle_id
    returning * into v_progress;

    return jsonb_build_object('status', 'advanced', 'progress', to_jsonb(v_progress));
  end if;

  if v_guesses = v_progress.guesses then
    return jsonb_build_object('status', 'exact', 'progress', to_jsonb(v_progress));
  end if;

  if jsonb_array_length(v_guesses) < jsonb_array_length(v_progress.guesses)
    and private.daily_guesses_are_prefix(v_guesses, v_progress.guesses)
  then
    return jsonb_build_object('status', 'server_ahead', 'progress', to_jsonb(v_progress));
  end if;

  if jsonb_array_length(v_progress.guesses) < jsonb_array_length(v_guesses)
    and private.daily_guesses_are_prefix(v_progress.guesses, v_guesses)
  then
    if p_expected_revision is not null and p_expected_revision <> v_progress.revision then
      return jsonb_build_object('status', 'conflict', 'progress', to_jsonb(v_progress));
    end if;

    update public.daily_progress
    set guesses = v_guesses,
        revision = revision + 1,
        server_updated_at = transaction_timestamp()
    where user_id = v_user_id and puzzle_id = p_puzzle_id
    returning * into v_progress;

    return jsonb_build_object('status', 'advanced', 'progress', to_jsonb(v_progress));
  end if;

  return jsonb_build_object('status', 'conflict', 'progress', to_jsonb(v_progress));
end;
$$;

create or replace function public.import_daily_result(
  p_puzzle_id text,
  p_puzzle_number integer,
  p_puzzle_day integer,
  p_word_pack_id text,
  p_schedule_version integer,
  p_hard_mode_enabled boolean,
  p_guesses jsonb,
  p_outcome text,
  p_guess_count integer,
  p_client_completed_at timestamptz
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_guesses jsonb;
  v_progress public.daily_progress%rowtype;
  v_result public.daily_imported_results%rowtype;
  v_payload jsonb;
begin
  if v_user_id is null then
    return private.daily_sync_error('not_authenticated');
  end if;

  if private.valid_daily_identity(
      p_puzzle_id,
      p_puzzle_number,
      p_puzzle_day,
      p_word_pack_id,
      p_schedule_version
    ) is not true
    or p_hard_mode_enabled is null
    or private.valid_daily_result(
      p_guesses,
      p_outcome,
      p_guess_count,
      p_client_completed_at
    ) is not true
  then
    return private.daily_sync_error('invalid_daily_payload');
  end if;

  v_guesses := private.normalize_daily_guesses(p_guesses);
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(v_user_id::text || ':' || p_puzzle_id, 0)
  );

  select * into v_result
  from public.daily_imported_results
  where user_id = v_user_id and puzzle_id = p_puzzle_id;

  if found then
    v_payload := to_jsonb(v_result) - 'server_imported_at';
    if v_payload = jsonb_build_object(
      'user_id', v_user_id,
      'puzzle_id', p_puzzle_id,
      'puzzle_number', p_puzzle_number,
      'puzzle_day', p_puzzle_day,
      'word_pack_id', p_word_pack_id,
      'schedule_version', p_schedule_version,
      'hard_mode_enabled', p_hard_mode_enabled,
      'guesses', v_guesses,
      'outcome', p_outcome,
      'guess_count', p_guess_count,
      'client_completed_at', p_client_completed_at
    ) then
      return jsonb_build_object('status', 'exact', 'result', to_jsonb(v_result));
    end if;

    return jsonb_build_object('status', 'conflict', 'result', to_jsonb(v_result));
  end if;

  select * into v_progress
  from public.daily_progress
  where user_id = v_user_id and puzzle_id = p_puzzle_id
  for update;

  if found and not (
    v_progress.puzzle_number = p_puzzle_number
    and v_progress.puzzle_day = p_puzzle_day
    and v_progress.word_pack_id = p_word_pack_id
    and v_progress.schedule_version = p_schedule_version
    and v_progress.hard_mode_enabled = p_hard_mode_enabled
    and private.daily_guesses_are_prefix(v_progress.guesses, v_guesses)
  ) then
    return jsonb_build_object('status', 'conflict', 'progress', to_jsonb(v_progress));
  end if;

  insert into public.daily_imported_results (
    user_id,
    puzzle_id,
    puzzle_number,
    puzzle_day,
    word_pack_id,
    schedule_version,
    hard_mode_enabled,
    guesses,
    outcome,
    guess_count,
    client_completed_at
  ) values (
    v_user_id,
    p_puzzle_id,
    p_puzzle_number,
    p_puzzle_day,
    p_word_pack_id,
    p_schedule_version,
    p_hard_mode_enabled,
    v_guesses,
    p_outcome,
    p_guess_count,
    p_client_completed_at
  )
  returning * into v_result;

  delete from public.daily_progress
  where user_id = v_user_id and puzzle_id = p_puzzle_id;

  return jsonb_build_object('status', 'inserted', 'result', to_jsonb(v_result));
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

  delete from public.daily_progress where user_id = p_user_id;
  delete from public.daily_imported_results where user_id = p_user_id;
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

revoke all on table public.daily_progress from public, anon, authenticated;
revoke all on table public.daily_imported_results from public, anon, authenticated;
revoke execute on function public.sync_daily_progress(
  text, integer, integer, text, integer, boolean, jsonb, bigint
) from public, anon;
revoke execute on function public.import_daily_result(
  text, integer, integer, text, integer, boolean, jsonb, text, integer, timestamptz
) from public, anon;

grant select on public.daily_progress to authenticated;
grant select on public.daily_imported_results to authenticated;
grant all on public.daily_progress to service_role;
grant all on public.daily_imported_results to service_role;
grant execute on function public.sync_daily_progress(
  text, integer, integer, text, integer, boolean, jsonb, bigint
) to authenticated, service_role;
grant execute on function public.import_daily_result(
  text, integer, integer, text, integer, boolean, jsonb, text, integer, timestamptz
) to authenticated, service_role;

commit;
