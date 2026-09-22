begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

-- GR-06: the timing-bearing matches.updated_at signal is replaced by a
-- timestamp-free monotonic matches.revision signal. This file proves grants,
-- RLS, the Realtime publication projection, revision movement on every
-- canonical mutation, and revision stability on idempotent replay.

insert into auth.users (
  id,
  instance_id,
  aud,
  role,
  email,
  encrypted_password,
  email_confirmed_at,
  created_at,
  updated_at
)
values
  (
    '50000000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    'revision-host@example.test',
    'unused',
    transaction_timestamp(),
    transaction_timestamp(),
    transaction_timestamp()
  ),
  (
    '50000000-0000-0000-0000-000000000002',
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    'revision-member@example.test',
    'unused',
    transaction_timestamp(),
    transaction_timestamp(),
    transaction_timestamp()
  ),
  (
    '50000000-0000-0000-0000-000000000003',
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    'revision-outsider@example.test',
    'unused',
    transaction_timestamp(),
    transaction_timestamp(),
    transaction_timestamp()
  );

select is((select count(*) from public.profiles), 3::bigint, 'auth trigger creates profiles for the revision fixtures');

-- Grants: the exact-action timestamp is unreadable, the revision is readable.
select ok(
  not has_column_privilege('authenticated', 'public.matches', 'updated_at', 'SELECT'),
  'authenticated role cannot select matches.updated_at'
);
select ok(
  has_column_privilege('authenticated', 'public.matches', 'revision', 'SELECT'),
  'authenticated role can select matches.revision'
);
select ok(
  not has_column_privilege('anon', 'public.matches', 'revision', 'SELECT'),
  'anonymous role cannot select matches.revision'
);

-- Signal shape: timestamp-free and monotonic-ready.
select is(
  (select data_type from information_schema.columns
   where table_schema = 'public' and table_name = 'matches' and column_name = 'revision'),
  'bigint',
  'matches.revision is a timestamp-free integer signal'
);

-- Publication: the match row stays published, but the Realtime projection is
-- an explicit timing-free column list.
select ok(
  exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'matches'
  ),
  'the match row stays in the realtime publication'
);
select ok(
  (select prattrs is not null from pg_publication_rel
   where prrelid = 'public.matches'::regclass
     and prpubid = (select oid from pg_publication where pubname = 'supabase_realtime')),
  'the match publication uses an explicit column list'
);

create temporary table published_match_columns as
select a.attname
from pg_publication_rel as r
cross join lateral unnest(string_to_array(r.prattrs::text, ' ')::integer[]) as published(attnum)
join pg_attribute as a
  on a.attrelid = r.prrelid and a.attnum = published.attnum
where r.prrelid = 'public.matches'::regclass
  and r.prpubid = (select oid from pg_publication where pubname = 'supabase_realtime');

select ok(
  not exists (select 1 from published_match_columns where attname = 'updated_at'),
  'matches.updated_at is excluded from the realtime projection'
);
select ok(
  exists (select 1 from published_match_columns where attname = 'revision'),
  'matches.revision is included in the realtime projection'
);
select is(
  (select count(*) from published_match_columns),
  13::bigint,
  'the realtime projection carries exactly the timing-free column set'
);

create temporary table test_context (
  match_id uuid,
  round_id uuid,
  host_member_id uuid,
  member_member_id uuid,
  request_id uuid,
  first_response jsonb,
  completed_at timestamptz
);

with created as (
  select public.create_match(
    '50000000-0000-0000-0000-000000000001',
    1,
    repeat('b', 64),
    '51000000-0000-0000-0000-000000000001'
  ) as response
)
insert into test_context (match_id, request_id, first_response)
select
  (response #>> '{data,match_id}')::uuid,
  '50000000-0000-0000-0000-000000000001',
  response
from created;

update test_context as context
set round_id = round.id,
    host_member_id = host_member.id
from public.rounds as round,
     public.match_members as host_member
where round.match_id = context.match_id
  and host_member.match_id = context.match_id
  and host_member.seat = 1;

select is(
  (select revision from public.matches where id = (select match_id from test_context)),
  1::bigint,
  'creation starts the revision at one'
);

select ok(
  public.join_match(
    '50000000-0000-0000-0000-000000000002',
    1,
    (select join_code from public.matches where id = (select match_id from test_context)),
    null
  ) ? 'data',
  'second player joins the room'
);
select is(
  (select revision from public.matches where id = (select match_id from test_context)),
  2::bigint,
  'join increments the revision'
);

update test_context as context
set member_member_id = member.id
from public.match_members as member
where member.match_id = context.match_id and member.seat = 2;

select is(
  public.join_match(
    '50000000-0000-0000-0000-000000000002',
    1,
    (select join_code from public.matches where id = (select match_id from test_context)),
    null
  ) #>> '{data,match_id}',
  (select match_id::text from test_context),
  'duplicate join returns the existing match'
);
select is(
  (select revision from public.matches where id = (select match_id from test_context)),
  2::bigint,
  'duplicate join leaves the revision untouched'
);

select is(
  public.start_match(
    '50000000-0000-0000-0000-000000000002',
    1,
    (select match_id from test_context)
  ) #>> '{error,code}',
  'not_host',
  'non-host cannot start'
);
select is(
  (select revision from public.matches where id = (select match_id from test_context)),
  2::bigint,
  'rejected start leaves the revision untouched'
);

select ok(
  public.start_match(
    '50000000-0000-0000-0000-000000000001',
    1,
    (select match_id from test_context)
  ) ? 'data',
  'host starts with two players'
);
select is(
  (select revision from public.matches where id = (select match_id from test_context)),
  3::bigint,
  'start increments the revision'
);

select ok(
  public.start_match(
    '50000000-0000-0000-0000-000000000001',
    1,
    (select match_id from test_context)
  ) ? 'data',
  'redundant start still succeeds'
);
select is(
  (select revision from public.matches where id = (select match_id from test_context)),
  3::bigint,
  'redundant start leaves the revision untouched'
);

update public.rounds
set starts_at = transaction_timestamp() - interval '1 second',
    ends_at = transaction_timestamp() + interval '179 seconds'
where id = (select round_id from test_context);
update public.player_rounds
set started_at = transaction_timestamp() - interval '1 second'
where round_id = (select round_id from test_context);
update private.round_secrets
set answer = 'stone'
where round_id = (select round_id from test_context);

update test_context
set first_response = public.submit_guess(
  '50000000-0000-0000-0000-000000000001',
  1,
  match_id,
  1::smallint,
  request_id,
  'CRANE',
  null
);

select is((select first_response #>> '{data,sequence}' from test_context), '1', 'accepted guess has sequence one');
select is(
  (select revision from public.matches where id = (select match_id from test_context)),
  4::bigint,
  'accepted guess increments the revision'
);

select is(
  public.submit_guess(
    '50000000-0000-0000-0000-000000000001',
    1,
    (select match_id from test_context),
    1::smallint,
    (select request_id from test_context),
    'crane',
    null
  ),
  (select first_response from test_context),
  'identical retry returns the original response'
);
select is((select count(*) from public.guesses), 1::bigint, 'identical retry creates no second guess');
select is(
  (select revision from public.matches where id = (select match_id from test_context)),
  4::bigint,
  'identical retry leaves the revision untouched'
);

select is(
  public.submit_guess(
    '50000000-0000-0000-0000-000000000001',
    1,
    (select match_id from test_context),
    1::smallint,
    (select request_id from test_context),
    'stone',
    null
  ) #>> '{error,code}',
  'request_conflict',
  'request reuse with different normalized content conflicts'
);
select is(
  (select revision from public.matches where id = (select match_id from test_context)),
  4::bigint,
  'conflicting reuse leaves the revision untouched'
);

-- Authenticated behavior: rostered members read the signal but not the timing.
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"50000000-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);
select is((select count(*) from public.matches), 1::bigint, 'host reads the rostered match row');
select is((select revision from public.matches), 4::bigint, 'host reads the revision signal');
select throws_ok(
  'select updated_at from public.matches',
  '42501',
  'permission denied for table matches',
  'host cannot select the exact-action timestamp'
);
select throws_ok(
  'select * from public.matches',
  '42501',
  'permission denied for table matches',
  'host cannot select the full match row'
);
reset role;

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"50000000-0000-0000-0000-000000000003","role":"authenticated"}',
  true
);
select is((select count(*) from public.matches), 0::bigint, 'unrelated user reads no match row');
reset role;

set local role anon;
select throws_ok(
  'select count(*) from public.matches',
  '42501',
  'permission denied for table matches',
  'anonymous role has no match-table grant'
);
reset role;

-- Deadline finalization advances the signal exactly once.
update public.rounds
set starts_at = transaction_timestamp() - interval '181 seconds',
    ends_at = transaction_timestamp() - interval '1 second'
where id = (select round_id from test_context);

select ok(private.finalize_round((select round_id from test_context)), 'elapsed round finalizes');
select is(
  (select revision from public.matches where id = (select match_id from test_context)),
  5::bigint,
  'finalization increments the revision'
);
update test_context
set completed_at = (select completed_at from public.rounds where id = test_context.round_id);
select ok(private.finalize_round((select round_id from test_context)), 'repeated finalizer succeeds');
select is(
  (select revision from public.matches where id = (select match_id from test_context)),
  5::bigint,
  'repeated finalizer leaves the revision untouched'
);
select is(
  (select completed_at from public.rounds where id = (select round_id from test_context)),
  (select completed_at from test_context),
  'repeated finalizer preserves completion timestamp'
);

select ok(
  public.match_snapshot(
    '50000000-0000-0000-0000-000000000002',
    1,
    (select match_id from test_context)
  ) ? 'data',
  'canonical snapshot still resolves after reveal'
);

-- Authenticated deletion preparation advances the same signal and preserves
-- the survivor snapshot.
select ok(
  public.delete_account('50000000-0000-0000-0000-000000000001', 1) ? 'data',
  'database deletion preparation succeeds'
);
select is(
  (select revision from public.matches where id = (select match_id from test_context)),
  6::bigint,
  'deletion preparation increments the revision'
);
select is(
  (select display_name_snapshot from public.match_members where id = (select host_member_id from test_context)),
  'Deleted Player',
  'retained result is anonymized'
);
select ok(
  public.match_snapshot(
    '50000000-0000-0000-0000-000000000002',
    1,
    (select match_id from test_context)
  ) ? 'data',
  'survivor snapshot still resolves after deletion preparation'
);

select * from finish();
rollback;
