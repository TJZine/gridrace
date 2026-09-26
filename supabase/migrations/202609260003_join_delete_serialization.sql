begin;

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

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_user_id::text, 1)
  );

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

commit;
