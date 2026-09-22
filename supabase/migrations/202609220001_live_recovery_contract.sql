begin;

create table private.create_requests (
  actor_user_id uuid not null references auth.users(id) on delete cascade,
  request_id uuid not null,
  client_build integer not null,
  match_id uuid not null references public.matches(id) on delete cascade,
  primary key (actor_user_id, request_id),
  constraint create_requests_build_check check (client_build between 1 and 2147483647)
);

revoke all on table private.create_requests from public, anon, authenticated;
grant all on table private.create_requests to service_role;

drop function public.create_match(uuid, integer, text);

create or replace function public.create_match(
  p_user_id uuid,
  p_client_build integer,
  p_ip_hash text,
  p_request_id uuid
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
    if v_receipt.client_build = p_client_build then
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

  insert into private.create_requests (
    actor_user_id,
    request_id,
    client_build,
    match_id
  )
  values (p_user_id, p_request_id, p_client_build, v_match_id);

  return jsonb_build_object('data', jsonb_build_object('match_id', v_match_id));
end;
$$;

revoke all on function public.create_match(uuid, integer, text, uuid)
from public, anon, authenticated;
grant execute on function public.create_match(uuid, integer, text, uuid)
to service_role;

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
        'is_self', coalesce(member.auth_user_id = p_user_id, false),
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

commit;
