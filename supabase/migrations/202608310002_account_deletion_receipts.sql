begin;

create table private.account_deletion_receipts (
  token_hash text primary key,
  deletion_id uuid not null default extensions.gen_random_uuid(),
  user_id uuid references auth.users(id) on delete set null,
  status text not null default 'pending',
  created_at timestamptz not null default transaction_timestamp(),
  completed_at timestamptz,
  constraint account_deletion_receipts_hash_check check (
    token_hash ~ '^[0-9a-f]{64}$'
  ),
  constraint account_deletion_receipts_status_check check (
    (status = 'pending' and completed_at is null)
    or (status = 'completed' and user_id is null and completed_at is not null)
  )
);

create index account_deletion_receipts_pending_user_idx
on private.account_deletion_receipts (user_id)
where status = 'pending' and user_id is not null;

create or replace function public.account_deletion_status(p_token_hash text)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_receipt private.account_deletion_receipts%rowtype;
begin
  if (p_token_hash ~ '^[0-9a-f]{64}$') is not true then
    return private.error_response('internal_error');
  end if;

  select * into v_receipt
  from private.account_deletion_receipts
  where token_hash = p_token_hash;

  if not found then
    return jsonb_build_object('data', jsonb_build_object('status', 'missing'));
  end if;

  return jsonb_build_object(
    'data', jsonb_strip_nulls(jsonb_build_object(
      'status', v_receipt.status,
      'user_id', v_receipt.user_id
    ))
  );
end;
$$;

create or replace function public.begin_account_deletion(
  p_user_id uuid,
  p_client_build integer,
  p_token_hash text
)
returns jsonb
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  v_receipt private.account_deletion_receipts%rowtype;
  v_deleted jsonb;
  v_deletion_id uuid;
begin
  if p_user_id is null
    or (p_client_build between 1 and 2147483647) is not true
    or (p_token_hash ~ '^[0-9a-f]{64}$') is not true
  then
    return private.error_response('internal_error');
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_user_id::text, 1)
  );

  select deletion_id into v_deletion_id
  from private.account_deletion_receipts
  where user_id = p_user_id and status = 'pending'
  order by created_at, token_hash
  limit 1
  for update;

  insert into private.account_deletion_receipts (
    token_hash,
    deletion_id,
    user_id
  )
  values (
    p_token_hash,
    coalesce(v_deletion_id, extensions.gen_random_uuid()),
    p_user_id
  )
  on conflict (token_hash) do nothing;

  select * into v_receipt
  from private.account_deletion_receipts
  where token_hash = p_token_hash
  for update;

  if v_receipt.status = 'completed' then
    return jsonb_build_object('data', jsonb_build_object('status', 'completed'));
  end if;

  if v_receipt.user_id is distinct from p_user_id then
    return private.error_response('request_conflict');
  end if;

  v_deleted := public.delete_account(p_user_id, p_client_build);
  if v_deleted #>> '{data,deleted}' is distinct from 'true' then
    raise exception using errcode = 'P0001', message = 'account deletion preparation failed';
  end if;

  return jsonb_build_object(
    'data', jsonb_build_object('status', 'pending', 'user_id', p_user_id)
  );
end;
$$;

create or replace function public.complete_account_deletion(p_token_hash text)
returns jsonb
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  v_receipt private.account_deletion_receipts%rowtype;
begin
  if (p_token_hash ~ '^[0-9a-f]{64}$') is not true then
    return private.error_response('internal_error');
  end if;

  select * into v_receipt
  from private.account_deletion_receipts
  where token_hash = p_token_hash
  for update;

  if not found then
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

revoke all on table private.account_deletion_receipts
from public, anon, authenticated;
revoke execute on function public.account_deletion_status(text)
from public, anon, authenticated;
revoke execute on function public.begin_account_deletion(uuid, integer, text)
from public, anon, authenticated;
revoke execute on function public.complete_account_deletion(text)
from public, anon, authenticated;

grant all on table private.account_deletion_receipts to service_role;
grant execute on function public.account_deletion_status(text) to service_role;
grant execute on function public.begin_account_deletion(uuid, integer, text)
to service_role;
grant execute on function public.complete_account_deletion(text) to service_role;

commit;
