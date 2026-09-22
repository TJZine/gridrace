begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at
)
values
  (
    '60000000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'recovery-host@example.test', 'unused',
    transaction_timestamp(), transaction_timestamp(), transaction_timestamp()
  ),
  (
    '60000000-0000-0000-0000-000000000002',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'recovery-member@example.test', 'unused',
    transaction_timestamp(), transaction_timestamp(), transaction_timestamp()
  );

select ok(
  to_regprocedure('public.create_match(uuid,integer,text)') is null,
  'obsolete three-argument create RPC is absent'
);
select is(
  (select pronargdefaults
   from pg_catalog.pg_proc
   where oid = 'public.create_match(uuid,integer,text,uuid)'::regprocedure),
  0::smallint,
  'new create RPC requires every request parameter explicitly'
);
select ok(
  has_function_privilege(
    'service_role',
    'public.create_match(uuid,integer,text,uuid)',
    'execute'
  ),
  'service role can execute the new create RPC'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.create_match(uuid,integer,text,uuid)',
    'execute'
  ),
  'authenticated clients cannot execute the create RPC'
);
select ok(
  not has_table_privilege(
    'authenticated',
    'private.create_requests',
    'select'
  ),
  'authenticated clients cannot read create receipts'
);
select ok(
  not has_table_privilege('anon', 'private.create_requests', 'select'),
  'anonymous clients cannot read create receipts'
);

create temporary table test_context (
  first_match_id uuid,
  second_match_id uuid,
  first_request_id uuid,
  second_request_id uuid,
  first_response jsonb,
  second_response jsonb,
  cascade_match_id uuid,
  round_id uuid,
  member_id uuid
);

insert into test_context (first_request_id, second_request_id)
values (
  '61000000-0000-0000-0000-000000000001',
  '61000000-0000-0000-0000-000000000002'
);

update test_context
set first_response = public.create_match(
      '60000000-0000-0000-0000-000000000001',
      1,
      null,
      first_request_id
    );

update test_context
set first_match_id = (first_response #>> '{data,match_id}')::uuid;

select ok(
  (select first_response ? 'data' from test_context),
  'valid create returns a success envelope'
);
select is(
  (select count(*) from public.matches),
  1::bigint,
  'valid create allocates one match'
);
select is(
  (select count(*) from public.match_members where match_id = (select first_match_id from test_context)),
  1::bigint,
  'valid create commits the creator membership'
);
select is(
  (select count(*) from public.rounds where match_id = (select first_match_id from test_context)),
  1::bigint,
  'valid create commits the pending round'
);
select is(
  (select count(*) from private.create_requests),
  1::bigint,
  'valid create commits one private receipt'
);
select is(
  (select client_build from private.create_requests),
  1,
  'receipt stores the accepted build'
);
select is(
  (select match_id from private.create_requests),
  (select first_match_id from test_context),
  'receipt stores the original match id'
);

create temporary table quota_before_retry as
select attempt_count
from private.user_rate_limits
where actor_user_id = '60000000-0000-0000-0000-000000000001'
  and action = 'create';

select is(
  public.create_match(
    '60000000-0000-0000-0000-000000000001',
    1,
    null,
    (select first_request_id from test_context)
  ) #>> '{data,match_id}',
  (select first_match_id::text from test_context),
  'identical retry returns the original match id'
);
select is(
  (select count(*) from public.matches),
  1::bigint,
  'identical retry allocates no second match'
);
select is(
  (select count(*) from private.create_requests),
  1::bigint,
  'identical retry stores no second receipt'
);
select is(
  (select attempt_count from private.user_rate_limits
   where actor_user_id = '60000000-0000-0000-0000-000000000001'
     and action = 'create'),
  (select attempt_count from quota_before_retry),
  'identical retry consumes no additional create quota'
);

select is(
  public.create_match(
    '60000000-0000-0000-0000-000000000001',
    2,
    null,
    (select first_request_id from test_context)
  ) #>> '{error,code}',
  'request_conflict',
  'same request id with a changed build conflicts'
);
select is(
  (select attempt_count from private.user_rate_limits
   where actor_user_id = '60000000-0000-0000-0000-000000000001'
     and action = 'create'),
  (select attempt_count from quota_before_retry),
  'conflicting reuse consumes no create quota'
);

select is(
  public.create_match(
    '60000000-0000-0000-0000-000000000001',
    0,
    null,
    '61000000-0000-0000-0000-000000000003'
  ) #>> '{error,code}',
  'client_update_required',
  'unsupported build is rejected before allocation'
);
select is(
  (select count(*) from private.create_requests),
  1::bigint,
  'rejected build leaves no receipt'
);
select is(
  public.create_match(
    '60000000-0000-0000-0000-000000000001',
    1,
    null,
    null
  ) #>> '{error,code}',
  'internal_error',
  'null request id is rejected before allocation'
);
select is(
  (select count(*) from private.create_requests),
  1::bigint,
  'null request id leaves no receipt'
);
select is(
  public.create_match(
    '60000000-0000-0000-0000-000000000099',
    1,
    null,
    '61000000-0000-0000-0000-000000000004'
  ) #>> '{error,code}',
  'not_authenticated',
  'missing active profile is rejected'
);

do $$
declare
  v_response jsonb;
begin
  v_response := public.create_match(
    '60000000-0000-0000-0000-000000000001',
    1,
    null,
    '61000000-0000-0000-0000-000000000005'
  );
  if not v_response ? 'data' then
    raise exception using message = 'rollback fixture did not create';
  end if;
  raise exception using message = 'rollback fixture';
exception when others then
  null;
end;
$$;

select is(
  (select count(*) from private.create_requests
   where request_id = '61000000-0000-0000-0000-000000000005'),
  0::bigint,
  'rolled-back creation leaves no receipt'
);
select is(
  (select count(*) from public.matches),
  1::bigint,
  'rolled-back creation leaves no match'
);

update test_context
set second_response = public.create_match(
      '60000000-0000-0000-0000-000000000001',
      1,
      null,
      second_request_id
    );
update test_context
set second_match_id = (second_response #>> '{data,match_id}')::uuid;

select is(
  (select count(*) from public.matches),
  2::bigint,
  'a distinct request id intentionally creates another room'
);
select is(
  (select attempt_count from private.user_rate_limits
   where actor_user_id = '60000000-0000-0000-0000-000000000001'
     and action = 'create'),
  2,
  'a distinct request id consumes one create quota'
);

update public.matches
set created_at = transaction_timestamp() - interval '2 hours',
    expires_at = transaction_timestamp() - interval '1 second'
where id = (select first_match_id from test_context);
select is(
  public.create_match(
    '60000000-0000-0000-0000-000000000001',
    1,
    null,
    (select first_request_id from test_context)
  ) #>> '{data,match_id}',
  (select first_match_id::text from test_context),
  'retry after lobby expiry returns the original match id'
);
select is(
  (select count(*) from public.matches),
  2::bigint,
  'expired-room retry does not allocate a replacement room'
);

select is(
  public.join_match(
    '60000000-0000-0000-0000-000000000002',
    1,
    (select join_code from public.matches where id = (select second_match_id from test_context)),
    null
  ) #>> '{data,match_id}',
  (select second_match_id::text from test_context),
  'survivor joins the second room'
);
select ok(
  public.start_match(
    '60000000-0000-0000-0000-000000000001',
    1,
    (select second_match_id from test_context)
  ) ? 'data',
  'creator starts the second room'
);
select is(
  public.create_match(
    '60000000-0000-0000-0000-000000000001',
    1,
    null,
    (select second_request_id from test_context)
  ) #>> '{data,match_id}',
  (select second_match_id::text from test_context),
  'retry after start returns the original match id'
);

update test_context
set round_id = round.id,
    member_id = member.id
from public.rounds as round, public.match_members as member
where round.match_id = (select second_match_id from test_context)
  and member.match_id = (select second_match_id from test_context)
  and member.seat = 2;
update public.rounds
set starts_at = transaction_timestamp() - interval '181 seconds',
    ends_at = transaction_timestamp() - interval '1 second'
where id = (select round_id from test_context);
select ok(
  private.finalize_round((select round_id from test_context)),
  'completed room finalizes through the existing server operation'
);
select is(
  public.create_match(
    '60000000-0000-0000-0000-000000000001',
    1,
    null,
    (select second_request_id from test_context)
  ) #>> '{data,match_id}',
  (select second_match_id::text from test_context),
  'retry after completion returns the original match id'
);

select ok(
  public.match_snapshot(
    '60000000-0000-0000-0000-000000000002',
    1,
    (select second_match_id from test_context)
  ) ? 'data',
  'rostered survivor can read the completed snapshot'
);

select ok(
  public.delete_account('60000000-0000-0000-0000-000000000001', 1) ? 'data',
  'account deletion preparation succeeds'
);
select is(
  (select count(*) from private.create_requests),
  0::bigint,
  'account deletion removes every create receipt for the actor'
);
select is(
  (select count(*) from public.matches where id = (select first_match_id from test_context)),
  0::bigint,
  'host lobby deletion removes its dependent match'
);
select is(
  (select count(*) from public.matches where id = (select second_match_id from test_context)),
  1::bigint,
  'completed match remains for the survivor'
);

create temporary table survivor_snapshot as
select public.match_snapshot(
  '60000000-0000-0000-0000-000000000002',
  1,
  (select second_match_id from test_context)
) as response;

select ok(
  (select jsonb_typeof(response #> '{data,members,0,is_self}') = 'boolean'
      and jsonb_typeof(response #> '{data,members,1,is_self}') = 'boolean'
   from survivor_snapshot),
  'survivor snapshot emits Boolean is_self values'
);
select is(
  (select response #>> '{data,members,0,is_self}' from survivor_snapshot),
  'false',
  'deleted member is never self'
);
select is(
  (select response #>> '{data,members,1,is_self}' from survivor_snapshot),
  'true',
  'surviving member remains self'
);
select is(
  (select count(*) from jsonb_array_elements(
    (select response #> '{data,members}' from survivor_snapshot)
  ) as member
   where (member.value ->> 'is_self')::boolean),
  1::bigint,
  'survivor snapshot contains exactly one self'
);
select is(
  (select response #>> '{data,members,0,display_name}' from survivor_snapshot),
  'Deleted Player',
  'survivor snapshot preserves deleted-member anonymization'
);
select is(
  (select response #>> '{data,round,state}' from survivor_snapshot),
  'revealed',
  'survivor snapshot preserves the completed round state'
);

update test_context
set cascade_match_id = (
  public.create_match(
    '60000000-0000-0000-0000-000000000002',
    1,
    null,
    '61000000-0000-0000-0000-000000000007'
  ) #>> '{data,match_id}'
)::uuid;
delete from public.matches
where id = (select cascade_match_id from test_context);
select is(
  (select count(*) from private.create_requests
   where request_id = '61000000-0000-0000-0000-000000000007'),
  0::bigint,
  'match deletion removes its dependent create receipt'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"60000000-0000-0000-0000-000000000002","role":"authenticated"}',
  true
);
select throws_ok(
  'select count(*) from private.create_requests',
  '42501',
  'permission denied for schema private',
  'authenticated clients cannot inspect create receipts directly'
);
select throws_ok(
  $$select public.create_match(
    '60000000-0000-0000-0000-000000000002', 1, null,
    '61000000-0000-0000-0000-000000000006'
  )$$,
  '42501',
  'permission denied for function create_match',
  'authenticated clients cannot invoke the service-only create RPC'
);
reset role;

select * from finish();
rollback;
