begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

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
    '10000000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    'host@example.test',
    'unused',
    transaction_timestamp(),
    transaction_timestamp(),
    transaction_timestamp()
  ),
  (
    '10000000-0000-0000-0000-000000000002',
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    'member@example.test',
    'unused',
    transaction_timestamp(),
    transaction_timestamp(),
    transaction_timestamp()
  ),
  (
    '10000000-0000-0000-0000-000000000003',
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    'unrelated@example.test',
    'unused',
    transaction_timestamp(),
    transaction_timestamp(),
    transaction_timestamp()
  );

select is((select count(*) from private.words), 100::bigint, 'seed contains exactly 100 words');
select is((select count(*) from public.profiles), 3::bigint, 'auth trigger creates profiles');
select ok(
  (select bool_and(display_name ~ '^[A-Za-z0-9][A-Za-z0-9 ''-]*[A-Za-z0-9]$') from public.profiles),
  'generated profile names satisfy the frozen character contract'
);

select is(private.normalize_guess('STONE'), 'stone', 'ASCII uppercase normalization is deterministic');
select is(private.normalize_guess('st0ne'), null, 'invalid character is rejected');
select is(private.normalize_guess('stöne'), null, 'non-ASCII input is rejected');
select is(private.evaluate_guess('stone', 'stone'), array[2,2,2,2,2]::smallint[], 'all-correct feedback');
select is(private.evaluate_guess('flame', 'civic'), array[0,0,0,0,0]::smallint[], 'all-absent feedback');
select is(private.evaluate_guess('apple', 'ample'), array[2,0,2,2,2]::smallint[], 'answer duplicate handling');
select is(private.evaluate_guess('grape', 'apple'), array[1,1,0,0,2]::smallint[], 'excess guess duplicate handling');
select is(private.evaluate_guess('civic', 'vivid'), array[0,2,2,2,0]::smallint[], 'exact matches consume duplicates');
select is(private.evaluate_guess('bloom', 'cocoa'), array[0,1,0,2,0]::smallint[], 'multiple duplicate interactions');

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
    '10000000-0000-0000-0000-000000000001',
    1,
    repeat('a', 64)
  ) as response
)
insert into test_context (match_id, request_id, first_response)
select
  (response #>> '{data,match_id}')::uuid,
  '20000000-0000-0000-0000-000000000001',
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

select ok(
  (select first_response ? 'data' from test_context),
  'create-match returns a success envelope'
);
select is(
  (select count(*) from private.ip_rate_limits where ip_hash = repeat('a', 64)),
  1::bigint,
  'keyed-IP rate path stores only the supplied digest'
);
select ok(private.consume_rate_limit('10000000-0000-0000-0000-000000000003', null, 'create', transaction_timestamp()), 'create rate attempt one allowed');
select ok(private.consume_rate_limit('10000000-0000-0000-0000-000000000003', null, 'create', transaction_timestamp()), 'create rate attempt two allowed');
select ok(private.consume_rate_limit('10000000-0000-0000-0000-000000000003', null, 'create', transaction_timestamp()), 'create rate attempt three allowed');
select ok(private.consume_rate_limit('10000000-0000-0000-0000-000000000003', null, 'create', transaction_timestamp()), 'create rate attempt four allowed');
select ok(private.consume_rate_limit('10000000-0000-0000-0000-000000000003', null, 'create', transaction_timestamp()), 'create rate attempt five allowed');
select ok(not private.consume_rate_limit('10000000-0000-0000-0000-000000000003', null, 'create', transaction_timestamp()), 'create rate attempt six denied');

select is(
  public.join_match(
    '10000000-0000-0000-0000-000000000002',
    1,
    (select join_code from public.matches where id = (select match_id from test_context)),
    null
  ) #>> '{data,match_id}',
  (select match_id::text from test_context),
  'second player joins the room'
);

update test_context as context
set member_member_id = member.id
from public.match_members as member
where member.match_id = context.match_id and member.seat = 2;

select is(
  public.join_match(
    '10000000-0000-0000-0000-000000000002',
    1,
    (select join_code from public.matches where id = (select match_id from test_context)),
    null
  ) #>> '{data,match_id}',
  (select match_id::text from test_context),
  'duplicate join returns the existing match'
);

select is(
  public.start_match(
    '10000000-0000-0000-0000-000000000002',
    1,
    (select match_id from test_context)
  ) #>> '{error,code}',
  'not_host',
  'non-host cannot start'
);
select ok(
  public.start_match(
    '10000000-0000-0000-0000-000000000001',
    1,
    (select match_id from test_context)
  ) ? 'data',
  'host starts with two players'
);
select is((select count(*) from private.round_secrets), 1::bigint, 'start creates one private secret');

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
  '10000000-0000-0000-0000-000000000001',
  1,
  match_id,
  1::smallint,
  request_id,
  'CRANE',
  null
);

select is((select first_response #>> '{data,sequence}' from test_context), '1', 'accepted guess has sequence one');
select is((select count(*) from public.guesses), 1::bigint, 'accepted guess inserts exactly one row');
create temporary table submit_rate_before_retry as
select attempt_count
from private.user_rate_limits
where actor_user_id = '10000000-0000-0000-0000-000000000001'
  and action = 'submit_guess';
select is(
  public.submit_guess(
    '10000000-0000-0000-0000-000000000001',
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
  (
    select attempt_count
    from private.user_rate_limits
    where actor_user_id = '10000000-0000-0000-0000-000000000001'
      and action = 'submit_guess'
  ),
  (select attempt_count from submit_rate_before_retry),
  'identical retry does not consume another submit rate attempt'
);
select is(
  public.submit_guess(
    '10000000-0000-0000-0000-000000000001',
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
  jsonb_array_length(
    public.match_snapshot(
      '10000000-0000-0000-0000-000000000001',
      1,
      (select match_id from test_context)
    ) #> '{data,round,players,0,board}'
  ),
  1,
  'pre-reveal snapshot includes the requester board'
);
select is(
  public.match_snapshot(
    '10000000-0000-0000-0000-000000000002',
    1,
    (select match_id from test_context)
  ) #>> '{data,round,players,0,board}',
  null,
  'pre-reveal snapshot omits the opponent board'
);
select is(
  public.match_snapshot(
    '10000000-0000-0000-0000-000000000002',
    1,
    (select match_id from test_context)
  ) #>> '{data,round,answer}',
  null,
  'pre-reveal snapshot omits the answer'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);
select is((select count(*) from public.matches), 1::bigint, 'host reads rostered match');
select is((select count(*) from public.match_members), 2::bigint, 'host reads shared roster');
select is((select count(*) from public.rounds), 1::bigint, 'host reads rostered round');
select is((select count(*) from public.player_rounds), 2::bigint, 'host reads both player round summaries');
select is((select count(*) from public.guesses), 1::bigint, 'host reads own board before reveal');
select is((select count(*) from public.profiles), 1::bigint, 'host reads only own profile');
select throws_ok(
  'select auth_user_id from public.match_members',
  '42501',
  'permission denied for table match_members',
  'auth identity column is denied'
);
select throws_ok(
  'select solve_duration_us from public.player_rounds',
  '42501',
  'permission denied for table player_rounds',
  'exact solve timing column is denied'
);
select throws_ok(
  'insert into public.matches (join_code, creator_member_id, expires_at) values (''ABC234'', gen_random_uuid(), now() + interval ''1 hour'')',
  '42501',
  'permission denied for table matches',
  'normal client cannot insert authoritative match state'
);
select throws_ok(
  'select count(*) from private.words',
  '42501',
  'permission denied for schema private',
  'normal client cannot read private words'
);
select throws_ok(
  'select public.create_match(''10000000-0000-0000-0000-000000000001'', 1, null)',
  '42501',
  'permission denied for function create_match',
  'normal client cannot execute service-only RPCs'
);
reset role;

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}',
  true
);
select is((select count(*) from public.matches), 1::bigint, 'second rostered player reads match');
select is((select count(*) from public.rounds), 1::bigint, 'second rostered player reads round');
select is((select count(*) from public.player_rounds), 2::bigint, 'second rostered player reads both player round summaries');
select is((select count(*) from public.guesses), 0::bigint, 'opponent board is hidden before reveal');
reset role;

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000003","role":"authenticated"}',
  true
);
select is((select count(*) from public.matches), 0::bigint, 'unrelated authenticated user reads no match');
select is((select count(*) from public.match_members), 0::bigint, 'unrelated user reads no roster');
select is((select count(*) from public.rounds), 0::bigint, 'unrelated user reads no rounds');
select is((select count(*) from public.player_rounds), 0::bigint, 'unrelated user reads no player round summaries');
select is((select count(*) from public.guesses), 0::bigint, 'unrelated user reads no guesses');
reset role;

select is(
  public.match_snapshot(
    '10000000-0000-0000-0000-000000000003',
    1,
    (select match_id from test_context)
  ) #>> '{error,code}',
  'not_a_match_member',
  'unrelated user cannot obtain a match snapshot'
);

set local role anon;
select throws_ok(
  'select count(*) from public.matches',
  '42501',
  'permission denied for table matches',
  'anonymous role has no match-table grant'
);
reset role;

update public.rounds
set starts_at = transaction_timestamp() - interval '181 seconds',
    ends_at = transaction_timestamp() - interval '1 second'
where id = (select round_id from test_context);

select ok(private.finalize_round((select round_id from test_context)), 'elapsed round finalizes');
update test_context
set completed_at = (select completed_at from public.rounds where id = test_context.round_id);
select ok(private.finalize_round((select round_id from test_context)), 'repeated finalizer succeeds');
select is(
  (select completed_at from public.rounds where id = (select round_id from test_context)),
  (select completed_at from test_context),
  'repeated finalizer preserves completion timestamp'
);
select is((select state from public.rounds where id = (select round_id from test_context)), 'revealed', 'round is revealed');
select is((select revealed_answer from public.rounds where id = (select round_id from test_context)), 'stone', 'answer becomes public only at reveal');
select is((select count(*) from public.player_rounds where placement is not null), 2::bigint, 'both placements finalize atomically');
select is(
  public.match_snapshot(
    '10000000-0000-0000-0000-000000000002',
    1,
    (select match_id from test_context)
  ) #>> '{data,round,answer}',
  'stone',
  'post-reveal snapshot includes the answer'
);
select is(
  jsonb_array_length(
    public.match_snapshot(
      '10000000-0000-0000-0000-000000000002',
      1,
      (select match_id from test_context)
    ) #> '{data,round,players,0,board}'
  ),
  1,
  'post-reveal snapshot includes the opponent board'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}',
  true
);
select is((select count(*) from public.guesses), 1::bigint, 'opponent board becomes visible after reveal');
reset role;

select ok(
  public.delete_account('10000000-0000-0000-0000-000000000001', 1) ? 'data',
  'database deletion preparation succeeds'
);
select is((select count(*) from public.profiles where id = '10000000-0000-0000-0000-000000000001'), 0::bigint, 'deleted profile is removed');
select is((select count(*) from private.guess_requests where actor_user_id = '10000000-0000-0000-0000-000000000001'), 0::bigint, 'deletion removes request identity mapping');
select is((select count(*) from private.user_rate_limits where actor_user_id = '10000000-0000-0000-0000-000000000001'), 0::bigint, 'deletion removes user rate identity mapping');
select is(
  (select display_name_snapshot from public.match_members where id = (select host_member_id from test_context)),
  'Deleted Player',
  'retained result is anonymized'
);
select is(
  (select auth_user_id from public.match_members where id = (select host_member_id from test_context)),
  null,
  'retained result has no auth identity'
);
select is((select count(*) from public.guesses), 1::bigint, 'survivor-required accepted board remains');
select is(
  public.match_snapshot(
    '10000000-0000-0000-0000-000000000002',
    1,
    (select match_id from test_context)
  ) #>> '{data,members,0,display_name}',
  'Deleted Player',
  'survivor snapshot retains only anonymized presentation'
);
select ok(
  public.delete_account('10000000-0000-0000-0000-000000000001', 1) ? 'data',
  'database deletion preparation is idempotent'
);

select is(
  (select count(*) from cron.job where jobname = 'gridrace-finalize-rounds'),
  1::bigint,
  'one deadline safety Cron job is registered'
);
select ok(not has_schema_privilege('anon', 'cron', 'usage'), 'anonymous role cannot use the Cron schema');
select ok(not has_schema_privilege('authenticated', 'cron', 'usage'), 'authenticated role cannot use the Cron schema');
select lives_ok(
  (select command from cron.job where jobname = 'gridrace-finalize-rounds'),
  'registered deadline Cron command remains executable by its owner'
);
select ok(
  exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'matches'
  ),
  'only the safe match revision table is published by this migration'
);

select * from finish();
rollback;
