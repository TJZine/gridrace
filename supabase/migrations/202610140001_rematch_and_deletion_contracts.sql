begin;

alter table private.rematch_contexts rename column actor_epochs to participation_epochs_by_member_id;

alter function private.normalize_rematch(uuid,timestamptz) rename to normalize_rematch_with_locked_participation;

alter function private.rematch_projection(uuid,uuid,timestamptz) rename to rematch_projection_with_locked_participation;

alter function private.rematch_command_result(uuid,uuid,integer,text,bigint) rename to rematch_command_result_with_locked_participation;

create or replace function public.complete_account_deletion(p_token_hash text)
returns jsonb
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  deletion_operation_lock_namespace constant bigint := 2;
  v_receipt private.account_deletion_receipts%rowtype;
  v_deletion_id uuid;
begin
  if (p_token_hash ~ '^[0-9a-f]{64}$') is not true then
    return private.error_response('internal_error');
  end if;

  select deletion_id into v_deletion_id
  from private.account_deletion_receipts
  where token_hash = p_token_hash;

  if not found then
    return private.error_response('request_conflict');
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(v_deletion_id::text, deletion_operation_lock_namespace)
  );

  select * into v_receipt
  from private.account_deletion_receipts
  where token_hash = p_token_hash
  for update;

  if not found or v_receipt.deletion_id is distinct from v_deletion_id then
    return private.error_response('request_conflict');
  end if;

  if v_receipt.status = 'pending' and v_receipt.user_id is not null then
    return private.error_response('request_conflict');
  end if;

  if v_receipt.status = 'pending' then
    update private.account_deletion_receipts
    set status = 'completed', completed_at = transaction_timestamp()
    where deletion_id = v_receipt.deletion_id and status = 'pending';
  end if;

  return jsonb_build_object('data', jsonb_build_object('status', 'completed'));
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
      consenting_member_ids='{}',participation_epochs_by_member_id='{}',initiator_member_id=null,revision=revision+1
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
  elsif not v_enabled then v_reason:='feature_disabled';
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

create or replace function private.rematch_projection_with_locked_participation(p_actor uuid,p_match_id uuid,p_now timestamptz)
returns jsonb language plpgsql volatile security invoker set search_path='' as $$
declare v_context private.rematch_contexts%rowtype; v_selected uuid; v_available boolean; v_eligible boolean;
begin
  perform private.normalize_rematch_with_locked_participation(p_match_id,p_now);
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

create or replace function private.rematch_command_result_with_locked_participation(p_actor uuid,p_match_id uuid,p_generation integer,p_action text,p_epoch bigint)
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
  perform private.normalize_rematch_with_locked_participation(p_match_id,v_now);
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
      consenting_member_ids='{}',participation_epochs_by_member_id='{}',initiator_member_id=null,revision=revision+1 where predecessor_match_id=p_match_id;
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
      perform private.normalize_rematch_with_locked_participation(p_match_id,v_now);
      return private.error_response('rematch_expired');
    end if;
    if not private.consume_rate_limit(p_actor,null,'create',v_now) then
    return private.error_response('rate_limited');
  end if;
    if v_ctx.state in ('eligible','closed') then
      perform private.select_live_match(p_actor,p_match_id);
      update private.rematch_contexts set generation=p_generation,state='offered',reason=null,initiator_member_id=v_member,
        consenting_member_ids=array[v_member],participation_epochs_by_member_id=(select jsonb_object_agg(m.id::text,c.epoch)
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
        participation_epochs_by_member_id='{}',revision=revision+1 where predecessor_match_id=p_match_id;
    end if;
  end if;
  select * into v_ctx from private.rematch_contexts where predecessor_match_id=p_match_id;
  return jsonb_build_object('data',jsonb_build_object('predecessor_match_id',p_match_id,'generation',v_ctx.generation,
    'state',v_ctx.state,'successor_match_id',v_ctx.successor_match_id));
end;
$$;

create or replace function public.rematch_command(p_user_id uuid,p_client_build integer,p_request_id uuid,p_predecessor_match_id uuid,
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
  v_response:=private.rematch_command_result_with_locked_participation(p_user_id,p_predecessor_match_id,p_generation,p_action,p_expected_participation_epoch);
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
      then private.rematch_projection_with_locked_participation(p_user_id,p_match_id,v_now) else null end
  );
  return jsonb_build_object('data', v_result);
end;
$$;

commit;
