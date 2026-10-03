begin;

-- Keep failed-player storage at zero while command receipts follow the wire
-- contract: duration and efficiency are present only for solved submissions.
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

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_user_id::text, 1)
  );

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

commit;
