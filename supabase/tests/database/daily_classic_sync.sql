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
    '30000000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'sync-owner@example.test', 'unused',
    transaction_timestamp(), transaction_timestamp(), transaction_timestamp()
  ),
  (
    '30000000-0000-0000-0000-000000000002',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'sync-other@example.test', 'unused',
    transaction_timestamp(), transaction_timestamp(), transaction_timestamp()
  ),
  (
    '30000000-0000-0000-0000-000000000003',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'sync-delete@example.test', 'unused',
    transaction_timestamp(), transaction_timestamp(), transaction_timestamp()
  );

create temporary table daily_payloads (name text primary key, guesses jsonb not null);
insert into daily_payloads values
  ('empty', '[]'),
  ('first', '[{"word":"crane","feedback":[0,1,0,0,2],"accepted_at":"2026-08-31T12:00:00Z"}]'),
  ('two', '[{"word":"crane","feedback":[0,1,0,0,2],"accepted_at":"2026-08-31T12:00:00Z"},{"word":"slate","feedback":[1,0,2,0,2],"accepted_at":"2026-08-31T12:01:00Z"}]'),
  ('three', '[{"word":"crane","feedback":[0,1,0,0,2],"accepted_at":"2026-08-31T12:00:00Z"},{"word":"slate","feedback":[1,0,2,0,2],"accepted_at":"2026-08-31T12:01:00Z"},{"word":"audio","feedback":[0,0,0,0,0],"accepted_at":"2026-08-31T12:02:00Z"}]'),
  ('reordered', '[{"word":"slate","feedback":[1,0,2,0,2],"accepted_at":"2026-08-31T12:01:00Z"},{"word":"crane","feedback":[0,1,0,0,2],"accepted_at":"2026-08-31T12:02:00Z"}]'),
  ('divergent', '[{"word":"flame","feedback":[0,0,1,0,2],"accepted_at":"2026-08-31T12:00:00Z"}]'),
  ('solved', '[{"word":"crane","feedback":[0,1,0,0,2],"accepted_at":"2026-08-31T12:00:00Z"},{"word":"slate","feedback":[1,0,2,0,2],"accepted_at":"2026-08-31T12:01:00Z"},{"word":"stone","feedback":[2,2,2,2,2],"accepted_at":"2026-08-31T12:02:00Z"}]');

grant select on daily_payloads to authenticated;

select ok(
  not private.daily_guesses_are_prefix(
    (select guesses from daily_payloads where name = 'reordered'),
    (select guesses from daily_payloads where name = 'two')
  ),
  'JSONB containment cannot turn reordered guesses into a prefix'
);
select ok(
  private.daily_guesses_are_prefix(
    (select guesses from daily_payloads where name = 'first'),
    (select guesses from daily_payloads where name = 'two')
  ),
  'ordered exact elements form a prefix'
);
select ok(
  private.daily_guesses_are_prefix(
    (select guesses from daily_payloads where name = 'empty'),
    (select guesses from daily_payloads where name = 'first')
  ),
  'an empty guess sequence is an exact prefix'
);

set local role anon;
select throws_ok(
  $$select public.sync_daily_progress(
    'daily-classic-2026-08-31', 1, 20696, 'daily-classic-en-US-v1', 1, false,
    '[]'::jsonb, null
  )$$,
  '42501',
  'permission denied for function sync_daily_progress',
  'anonymous clients cannot execute the progress RPC'
);
select throws_ok(
  'select count(*) from public.daily_imported_results',
  '42501',
  'permission denied for table daily_imported_results',
  'anonymous clients cannot read imported results'
);
select throws_ok(
  'select count(*) from public.daily_progress',
  '42501',
  'permission denied for table daily_progress',
  'anonymous clients cannot read progress'
);
select throws_ok(
  $$select public.import_daily_result(
    'daily-classic-2026-08-31', 1, 20696, 'daily-classic-en-US-v1', 1, false,
    '[]'::jsonb, 'solved', 0, transaction_timestamp()
  )$$,
  '42501',
  'permission denied for function import_daily_result',
  'anonymous clients cannot execute the result-import RPC'
);
reset role;

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"30000000-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);

select is(
  public.sync_daily_progress(
    'wrong-puzzle', 1, 20696, 'daily-classic-en-US-v1', 1, false,
    (select guesses from daily_payloads where name = 'first'), null
  ) #>> '{error,code}',
  'invalid_daily_payload',
  'invalid daily identity is rejected with a typed error'
);
select is(
  public.sync_daily_progress(
    null, 1, 20696, 'daily-classic-en-US-v1', 1, false,
    (select guesses from daily_payloads where name = 'first'), null
  ) #>> '{error,code}',
  'invalid_daily_payload',
  'null daily identity is rejected with a typed error'
);
select is(
  public.sync_daily_progress(
    'daily-classic-2026-08-31', 1, 20696, 'daily-classic-en-US-v1', 1, false,
    '[{"word":"CRANE","feedback":[0,1,0,0,2],"accepted_at":"2026-08-31T12:00:00Z"}]', null
  ) #>> '{error,code}',
  'invalid_daily_payload',
  'malformed guess payload is rejected'
);
select is(
  public.sync_daily_progress(
    'daily-classic-2026-08-31', 1, 20696, 'daily-classic-en-US-v1', 1, false,
    (select guesses from daily_payloads where name = 'first'), null
  ) ->> 'status',
  'inserted',
  'first progress snapshot inserts'
);
select is(
  public.sync_daily_progress(
    'daily-classic-2026-08-31', 1, 20696, 'daily-classic-en-US-v1', 1, false,
    (select guesses from daily_payloads where name = 'first'), 999
  ) ->> 'status',
  'exact',
  'exact retry succeeds despite stale revision'
);
select is(
  public.sync_daily_progress(
    'daily-classic-2026-08-31', 1, 20696, 'daily-classic-en-US-v1', 1, false,
    (select guesses from daily_payloads where name = 'two'), 1
  ) ->> 'status',
  'advanced',
  'an exact-prefix extension advances progress'
);
select is(
  public.sync_daily_progress(
    'daily-classic-2026-08-31', 1, 20696, 'daily-classic-en-US-v1', 1, false,
    (select guesses from daily_payloads where name = 'first'), 1
  ) ->> 'status',
  'server_ahead',
  'a shorter exact prefix succeeds despite stale revision'
);
select is(
  public.sync_daily_progress(
    'daily-classic-2026-08-31', 1, 20696, 'daily-classic-en-US-v1', 1, false,
    (select guesses from daily_payloads where name = 'reordered'), 2
  ) ->> 'status',
  'conflict',
  'reordered JSONB containment is not accepted as a prefix'
);
select is(
  public.sync_daily_progress(
    'daily-classic-2026-08-31', 1, 20696, 'daily-classic-en-US-v1', 1, false,
    (select guesses from daily_payloads where name = 'divergent'), 2
  ) ->> 'status',
  'conflict',
  'divergent progress returns a typed conflict'
);
select is(
  public.sync_daily_progress(
    'daily-classic-2026-08-31', 1, 20696, 'daily-classic-en-US-v1', 1, false,
    (select guesses from daily_payloads where name = 'three'), 1
  ) ->> 'status',
  'conflict',
  'stale revision cannot advance progress'
);
select is(
  public.sync_daily_progress(
    'daily-classic-2026-08-31', 1, 20696, 'daily-classic-en-US-v1', 1, false,
    (select guesses from daily_payloads where name = 'three'), 2
  ) #>> '{progress,revision}',
  '3',
  'current revision advances monotonic progress'
);

select is(
  public.sync_daily_progress(
    'daily-classic-2026-09-01', 2, 20697, 'daily-classic-en-US-v1', 1, false,
    (select guesses from daily_payloads where name = 'empty'), null
  ) ->> 'status',
  'inserted',
  'empty progress inserts'
);
select is(
  public.sync_daily_progress(
    'daily-classic-2026-09-01', 2, 20697, 'daily-classic-en-US-v1', 1, true,
    (select guesses from daily_payloads where name = 'empty'), 99
  ) ->> 'status',
  'conflict',
  'stale revision blocks an empty-board hard-mode change'
);
select is(
  public.sync_daily_progress(
    'daily-classic-2026-09-01', 2, 20697, 'daily-classic-en-US-v1', 1, true,
    (select guesses from daily_payloads where name = 'empty'), 1
  ) ->> 'status',
  'advanced',
  'hard mode can change while both boards are empty'
);
select is(
  public.sync_daily_progress(
    'daily-classic-2026-09-01', 2, 20697, 'daily-classic-en-US-v1', 1, true,
    (select guesses from daily_payloads where name = 'first'), 2
  ) ->> 'status',
  'advanced',
  'first accepted guess advances after hard-mode selection'
);
select is(
  public.sync_daily_progress(
    'daily-classic-2026-09-01', 2, 20697, 'daily-classic-en-US-v1', 1, false,
    (select guesses from daily_payloads where name = 'first'), 3
  ) ->> 'status',
  'conflict',
  'hard mode cannot change after an accepted guess'
);

select throws_ok(
  $$update public.daily_progress
    set user_id = '30000000-0000-0000-0000-000000000002'
    where puzzle_id = 'daily-classic-2026-08-31'$$,
  '42501',
  'permission denied for table daily_progress',
  'direct ownership reassignment is denied'
);
select throws_ok(
  $$insert into public.daily_imported_results (
      user_id, puzzle_id, puzzle_number, puzzle_day, word_pack_id,
      schedule_version, hard_mode_enabled, guesses, outcome, guess_count,
      client_completed_at
    ) values (
      '30000000-0000-0000-0000-000000000001', 'daily-classic-2026-08-31',
      1, 20696, 'daily-classic-en-US-v1', 1, false, '[]', 'solved', 0,
      transaction_timestamp()
    )$$,
  '42501',
  'permission denied for table daily_imported_results',
  'direct imported-result creation is denied'
);
reset role;

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"30000000-0000-0000-0000-000000000002","role":"authenticated"}',
  true
);
select is((select count(*) from public.daily_progress), 0::bigint, 'unrelated user reads no owner progress');
select is((select count(*) from public.daily_imported_results), 0::bigint, 'unrelated user reads no owner results');
select is(
  public.sync_daily_progress(
    'daily-classic-2026-08-31', 1, 20696, 'daily-classic-en-US-v1', 1, false,
    (select guesses from daily_payloads where name = 'divergent'), null
  ) ->> 'status',
  'inserted',
  'unrelated user can only create their own progress'
);
select is((select count(*) from public.daily_progress), 1::bigint, 'unrelated user sees only their own row');
reset role;

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"30000000-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);
select is(
  public.sync_daily_progress(
    'daily-classic-2026-09-02', 3, 20698, 'daily-classic-en-US-v1', 1, false,
    (select guesses from daily_payloads where name = 'two'), null
  ) ->> 'status',
  'inserted',
  'compatible progress exists before completion import'
);
select is(
  public.import_daily_result(
    'daily-classic-2026-09-02', 3, 20698, 'daily-classic-en-US-v1', 1, false,
    (select guesses from daily_payloads where name = 'solved'), 'solved', 3,
    '2026-08-31T12:03:00Z'
  ) ->> 'status',
  'inserted',
  'valid imported result inserts'
);
select is(
  (select count(*) from public.daily_progress where puzzle_id = 'daily-classic-2026-09-02'),
  0::bigint,
  'completed result removes compatible in-progress state'
);
select is(
  public.import_daily_result(
    'daily-classic-2026-09-02', 3, 20698, 'daily-classic-en-US-v1', 1, false,
    (select guesses from daily_payloads where name = 'solved'), 'solved', 3,
    '2026-08-31T12:03:00Z'
  ) ->> 'status',
  'exact',
  'exact repeated result import is idempotent'
);
select throws_ok(
  $$update public.daily_imported_results
    set user_id = '30000000-0000-0000-0000-000000000002'
    where puzzle_id = 'daily-classic-2026-09-02'$$,
  '42501',
  'permission denied for table daily_imported_results',
  'imported-result ownership cannot be reassigned'
);
select is(
  public.import_daily_result(
    'daily-classic-2026-09-02', 3, 20698, 'daily-classic-en-US-v1', 1, true,
    (select guesses from daily_payloads where name = 'solved'), 'solved', 3,
    '2026-08-31T12:03:00Z'
  ) ->> 'status',
  'conflict',
  'different result payload cannot overwrite the first import'
);
select is(
  public.sync_daily_progress(
    'daily-classic-2026-09-02', 3, 20698, 'daily-classic-en-US-v1', 1, false,
    (select guesses from daily_payloads where name = 'first'), null
  ) ->> 'status',
  'completed',
  'compatible cloud completion dominates in-progress state'
);
select is(
  public.sync_daily_progress(
    'daily-classic-2026-09-02', 3, 20698, 'daily-classic-en-US-v1', 1, true,
    (select guesses from daily_payloads where name = 'divergent'), null
  ) ->> 'status',
  'completed',
  'an immutable cloud completion dominates divergent mismatched-mode progress'
);
select is(
  public.sync_daily_progress(
    'daily-classic-2026-09-05', 6, 20701, 'daily-classic-en-US-v1', 1, true,
    (select guesses from daily_payloads where name = 'divergent'), null
  ) ->> 'status',
  'inserted',
  'a divergent active attempt exists before terminal import'
);
select is(
  public.import_daily_result(
    'daily-classic-2026-09-05', 6, 20701, 'daily-classic-en-US-v1', 1, false,
    (select guesses from daily_payloads where name = 'solved'), 'solved', 3,
    '2026-09-05T12:03:00Z'
  ) ->> 'status',
  'inserted',
  'a valid terminal result replaces divergent active progress'
);
select is(
  (select count(*) from public.daily_progress where puzzle_id = 'daily-classic-2026-09-05'),
  0::bigint,
  'terminal import removes the superseded active attempt'
);
select is(
  (select count(*) from public.daily_imported_results where puzzle_id = 'daily-classic-2026-09-02'),
  1::bigint,
  'conflicting import leaves the immutable result unchanged'
);
select ok(
  not (
    select hard_mode_enabled
    from public.daily_imported_results
    where puzzle_id = 'daily-classic-2026-09-02'
  ),
  'conflicting import does not overwrite the stored payload'
);
reset role;

select hasnt_column(
  'public',
  'daily_imported_results',
  'verified',
  'imported results have no client-writable verification flag'
);
select hasnt_table(
  'public',
  'daily_verified_results',
  'migration creates no verified-result surface'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"30000000-0000-0000-0000-000000000003","role":"authenticated"}',
  true
);
select is(
  public.sync_daily_progress(
    'daily-classic-2026-09-03', 4, 20699, 'daily-classic-en-US-v1', 1, false,
    (select guesses from daily_payloads where name = 'first'), null
  ) ->> 'status',
  'inserted',
  'deletion subject creates progress'
);
select is(
  public.import_daily_result(
    'daily-classic-2026-09-04', 5, 20700, 'daily-classic-en-US-v1', 1, false,
    (select guesses from daily_payloads where name = 'solved'), 'solved', 3,
    '2026-08-31T12:03:00Z'
  ) ->> 'status',
  'inserted',
  'deletion subject creates an imported result'
);
reset role;

delete from public.profiles where id = '30000000-0000-0000-0000-000000000003';
select ok(
  public.delete_account('30000000-0000-0000-0000-000000000003', 1) ? 'data',
  'account deletion succeeds even when the profile is already absent'
);
select is(
  (select count(*) from public.daily_progress where user_id = '30000000-0000-0000-0000-000000000003'),
  0::bigint,
  'account deletion removes all daily progress'
);
select is(
  (select count(*) from public.daily_imported_results where user_id = '30000000-0000-0000-0000-000000000003'),
  0::bigint,
  'account deletion removes all imported results'
);
select ok(
  public.delete_account('30000000-0000-0000-0000-000000000003', 1) ? 'data',
  'daily account cleanup is idempotent'
);

select * from finish();
rollback;
