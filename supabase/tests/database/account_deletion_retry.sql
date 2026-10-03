begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at
)
values (
  '40000000-0000-0000-0000-000000000001',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'delete-retry@example.test', 'unused',
  transaction_timestamp(), transaction_timestamp(), transaction_timestamp()
);

insert into public.daily_progress (
  user_id,
  puzzle_id,
  puzzle_number,
  puzzle_day,
  word_pack_id,
  schedule_version,
  hard_mode_enabled,
  guesses
)
values (
  '40000000-0000-0000-0000-000000000001',
  'daily-classic-2026-08-31',
  1,
  20696,
  'daily-classic-en-US-v1',
  1,
  false,
  '[]'
);

select ok(
  not has_table_privilege(
    'authenticated',
    'private.account_deletion_receipts',
    'select'
  ),
  'authenticated clients have no receipt-table grant'
);
select ok(
  not has_table_privilege(
    'anon',
    'private.account_deletion_receipts',
    'select'
  ),
  'anonymous clients have no receipt-table grant'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.account_deletion_status(text)',
    'execute'
  ),
  'authenticated clients cannot inspect deletion receipts directly'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.begin_account_deletion(uuid,integer,text)',
    'execute'
  ),
  'authenticated clients cannot begin deletion through the service RPC'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.complete_account_deletion(text)',
    'execute'
  ),
  'authenticated clients cannot complete deletion receipts'
);

set local role anon;
select throws_ok(
  $$select public.account_deletion_status(repeat('a', 64))$$,
  '42501',
  'permission denied for function account_deletion_status',
  'anonymous clients cannot use receipt continuation'
);
reset role;

set local role service_role;
select is(
  public.account_deletion_status(repeat('a', 64)) #>> '{data,status}',
  'missing',
  'unknown token hash has no receipt'
);
select is(
  public.begin_account_deletion(
    '40000000-0000-0000-0000-000000000001',
    1,
    repeat('a', 64)
  ) #>> '{data,status}',
  'pending',
  'authenticated preparation creates a pending receipt'
);
select is(
  public.begin_account_deletion(
    '40000000-0000-0000-0000-000000000001',
    1,
    repeat('a', 64)
  ) #>> '{data,status}',
  'pending',
  'repeated preparation is idempotent'
);
select is(
  public.begin_account_deletion(
    '40000000-0000-0000-0000-000000000001',
    1,
    repeat('b', 64)
  ) #>> '{data,status}',
  'pending',
  'a refreshed bearer joins the existing pending deletion'
);
select is(
  public.complete_account_deletion(repeat('a', 64)) #>> '{error,code}',
  'request_conflict',
  'receipt cannot complete while the Auth identity still exists'
);
reset role;

select is(
  (select count(*) from public.profiles where id = '40000000-0000-0000-0000-000000000001'),
  0::bigint,
  'begin deletes the profile atomically with receipt creation'
);
select is(
  (select count(*) from public.daily_progress where user_id = '40000000-0000-0000-0000-000000000001'),
  0::bigint,
  'begin deletes synchronized app data atomically with receipt creation'
);
select is(
  (
    select count(distinct deletion_id)
    from private.account_deletion_receipts
    where user_id = '40000000-0000-0000-0000-000000000001'
  ),
  1::bigint,
  'rotated bearer receipts share one deletion operation'
);

delete from auth.users where id = '40000000-0000-0000-0000-000000000001';
select is(
  (
    select count(*)
    from private.account_deletion_receipts
    where user_id is not null
  ),
  0::bigint,
  'hard Auth deletion removes every receipt-to-user mapping'
);

set local role service_role;
select is(
  public.complete_account_deletion(repeat('b', 64)) #>> '{data,status}',
  'completed',
  'a rotated bearer can complete after hard Auth deletion'
);
select is(
  public.account_deletion_status(repeat('a', 64)) #>> '{data,status}',
  'completed',
  'the older bearer also observes terminal completion'
);
select is(
  public.complete_account_deletion(repeat('a', 64)) #>> '{data,status}',
  'completed',
  'receipt completion is idempotent'
);
reset role;

select is(
  (
    select count(*)
    from private.account_deletion_receipts
    where status <> 'completed' or user_id is not null or completed_at is null
  ),
  0::bigint,
  'completion terminalizes every rotated receipt without retaining a user link'
);
select ok(
  (
    select bool_and(token_hash ~ '^[0-9a-f]{64}$')
    from private.account_deletion_receipts
  ),
  'receipts store only fixed-length token digests'
);

select * from finish();
rollback;
