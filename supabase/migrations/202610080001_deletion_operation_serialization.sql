begin;

create or replace function public.complete_account_deletion(p_token_hash text)
returns jsonb
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  v_receipt private.account_deletion_receipts%rowtype;
  v_deletion_id uuid;
begin
  if (p_token_hash ~ '^[0-9a-f]{64}$') is not true then
    return private.error_response('internal_error');
  end if;

  -- Discover the operation without locking a token: rotated tokens must acquire
  -- the same operation lock before either holds a row needed by group completion.
  select deletion_id into v_deletion_id
  from private.account_deletion_receipts
  where token_hash = p_token_hash;

  if not found then
    return private.error_response('request_conflict');
  end if;

  -- Seed 2 separates completion from account (1) and Daily puzzle (0) locks.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(v_deletion_id::text, 2)
  );

  -- The unlocked lookup grants no authority. Revalidate after waiting, including
  -- the immutable operation identity, before applying the existing preconditions.
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

-- CREATE OR REPLACE retains the existing service-only ACL and invoker boundary.
commit;
