begin;

-- A missing service configuration must disable new consent just like false.
-- Accepted tombstones and original receipts keep their existing early returns.
create or replace function private.normalize_rematch_with_locked_participation(p_match_id uuid,p_now timestamptz)
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
  elsif v_enabled is not true then v_reason:='feature_disabled';
  elsif v_context.state='offered' and exists(
    select 1 from public.match_members m join private.participation_cursors c on c.actor_user_id=m.auth_user_id
      where m.match_id=p_match_id and (v_context.participation_epochs_by_member_id->>m.id::text)::bigint is distinct from c.epoch
  ) then v_reason:='participation_changed';
  end if;
  if v_reason is not null and (v_context.reason is distinct from v_reason or v_context.state not in ('closed','expired','unavailable')) then
    update private.rematch_contexts set
      state=case when v_reason='expired' then 'expired' when v_reason='participation_changed' then 'closed' else 'unavailable' end,
      reason=v_reason,consenting_member_ids='{}',participation_epochs_by_member_id='{}',initiator_member_id=null,revision=revision+1
      where predecessor_match_id=p_match_id;
  end if;
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

  -- Keep active phase and server_time at the same transaction instant. Only
  -- completed matches use wall time to enforce the separate rematch deadline.
  if v_match.status='completed' then
    v_now:=clock_timestamp();
  end if;
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
      then private.rematch_projection_with_locked_participation(p_user_id,p_match_id,v_now) else null end
  );
  return jsonb_build_object('data', v_result);
end;
$$;

-- CREATE OR REPLACE preserves each existing function identity and service ACL.
commit;
