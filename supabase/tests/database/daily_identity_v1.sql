begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at
)
values (
  '50000000-0000-0000-0000-000000000001',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'identity-v1@example.test', 'unused',
  transaction_timestamp(), transaction_timestamp(), transaction_timestamp()
);

-- Canonical v1 schedule: pack daily-classic-en-US-v1, schedule version 1,
-- epoch day 20696 (2026-08-31), 725 published answers, so days 20696..21420
-- carry numbers 1..725.

select is(
  private.valid_daily_identity(
    'daily-classic-2026-08-31', 1, 20696, 'daily-classic-en-US-v1', 1
  ),
  true,
  'canonical first puzzle identity is accepted'
);
select is(
  private.valid_daily_identity(
    'daily-classic-2028-08-24', 725, 21420, 'daily-classic-en-US-v1', 1
  ),
  true,
  'canonical last puzzle identity is accepted'
);
select is(
  private.valid_daily_identity(
    'daily-classic-2026-08-31', 2, 20696, 'daily-classic-en-US-v1', 1
  ),
  false,
  'structurally valid shape with a mismatched puzzle number is rejected'
);
select is(
  private.valid_daily_identity(
    'daily-classic-2026-09-01', 1, 20696, 'daily-classic-en-US-v1', 1
  ),
  false,
  'puzzle id for a different day than the puzzle day is rejected'
);
select is(
  private.valid_daily_identity(
    'daily-classic-2026-08-31', 1, 20696, 'daily-classic-v1', 1
  ),
  false,
  'legacy word-pack id is rejected'
);
select is(
  private.valid_daily_identity(
    'daily-classic-2026-08-31', 1, 20696, 'daily-classic-en-US-v1', 2
  ),
  false,
  'non-v1 schedule version is rejected'
);
select is(
  private.valid_daily_identity(
    'daily-classic-2026-08-30', 0, 20695, 'daily-classic-en-US-v1', 1
  ),
  false,
  'puzzle day before the epoch is rejected'
);
select is(
  private.valid_daily_identity(
    'daily-classic-2028-08-25', 726, 21421, 'daily-classic-en-US-v1', 1
  ),
  false,
  'puzzle day past the published schedule is rejected'
);
select is(
  private.valid_daily_identity(
    'daily-classic-1970-01-01', 1, 0, 'daily-classic-en-US-v1', 1
  ),
  false,
  'day zero is rejected despite a matching derived id'
);
select is(
  private.valid_daily_identity(
    'daily-classic-2243-10-17', 79305, 100000, 'daily-classic-en-US-v1', 1
  ),
  false,
  'far-future day inside the old syntactic range is rejected'
);
select is(
  private.valid_daily_identity(
    'daily-classic-2026-08-31', 1, 2147483647, 'daily-classic-en-US-v1', 1
  ),
  false,
  'extreme puzzle day fails closed instead of raising a date overflow'
);
select is(
  private.valid_daily_identity(
    'daily-classic-2026-08-31', 2147483647, 20696, 'daily-classic-en-US-v1', 1
  ),
  false,
  'extreme puzzle number fails closed instead of raising an overflow'
);
select is(
  private.valid_daily_identity(null, 1, 20696, 'daily-classic-en-US-v1', 1),
  false,
  'null puzzle id is rejected'
);
select is(
  private.valid_daily_identity(
    'daily-classic-2026-08-31', null, 20696, 'daily-classic-en-US-v1', 1
  ),
  false,
  'null puzzle number is rejected'
);

-- Exercise the populated forward-upgrade path: once an old constraint is
-- absent, a row accepted by the former loose identity predicate must prevent
-- the stricter constraint from being recreated as validated.
alter table public.daily_progress
  drop constraint daily_progress_identity_check;
insert into public.daily_progress (
  user_id, puzzle_id, puzzle_number, puzzle_day, word_pack_id,
  schedule_version, hard_mode_enabled, guesses
) values (
  '50000000-0000-0000-0000-000000000001', 'daily-classic-2026-08-31',
  2, 20696, 'daily-classic-en-US-v1', 1, false, '[]'
);
select throws_ok(
  $$alter table public.daily_progress
      add constraint daily_progress_identity_check check (
        private.valid_daily_identity(
          puzzle_id, puzzle_number, puzzle_day, word_pack_id, schedule_version
        )
      )$$,
  '23514',
  'check constraint "daily_progress_identity_check" of relation "daily_progress" is violated by some row',
  'pre-existing invalid progress prevents identity constraint recreation'
);
delete from public.daily_progress
where user_id = '50000000-0000-0000-0000-000000000001';
alter table public.daily_progress
  add constraint daily_progress_identity_check check (
    private.valid_daily_identity(
      puzzle_id, puzzle_number, puzzle_day, word_pack_id, schedule_version
    )
  );

alter table public.daily_imported_results
  drop constraint daily_imported_results_identity_check;
insert into public.daily_imported_results (
  user_id, puzzle_id, puzzle_number, puzzle_day, word_pack_id,
  schedule_version, hard_mode_enabled, guesses, outcome, guess_count,
  client_completed_at
) values (
  '50000000-0000-0000-0000-000000000001', 'daily-classic-2026-08-31',
  2, 20696, 'daily-classic-en-US-v1', 1, false,
  '[{"word":"stone","feedback":[2,2,2,2,2],"accepted_at":"2026-08-31T12:00:00Z"}]',
  'solved', 1, '2026-08-31T12:01:00Z'
);
select throws_ok(
  $$alter table public.daily_imported_results
      add constraint daily_imported_results_identity_check check (
        private.valid_daily_identity(
          puzzle_id, puzzle_number, puzzle_day, word_pack_id, schedule_version
        )
      )$$,
  '23514',
  'check constraint "daily_imported_results_identity_check" of relation "daily_imported_results" is violated by some row',
  'pre-existing invalid result prevents identity constraint recreation'
);
delete from public.daily_imported_results
where user_id = '50000000-0000-0000-0000-000000000001';
alter table public.daily_imported_results
  add constraint daily_imported_results_identity_check check (
    private.valid_daily_identity(
      puzzle_id, puzzle_number, puzzle_day, word_pack_id, schedule_version
    )
  );

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"50000000-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);

select is(
  public.sync_daily_progress(
    'daily-classic-2026-08-31', 2, 20696, 'daily-classic-en-US-v1', 1, false,
    '[]'::jsonb, null
  ) #>> '{error,code}',
  'invalid_daily_payload',
  'progress with an inconsistent number/day tuple is rejected with a typed error'
);
select is(
  public.sync_daily_progress(
    'daily-classic-2028-08-25', 726, 21421, 'daily-classic-en-US-v1', 1, false,
    '[]'::jsonb, null
  ) #>> '{error,code}',
  'invalid_daily_payload',
  'progress past the published schedule is rejected with a typed error'
);
select is(
  public.sync_daily_progress(
    'daily-classic-2026-08-31', 1, 20696, 'daily-classic-en-US-v1', 2, false,
    '[]'::jsonb, null
  ) #>> '{error,code}',
  'invalid_daily_payload',
  'progress with a non-v1 schedule version is rejected with a typed error'
);
select is(
  public.import_daily_result(
    'daily-classic-2026-08-31', 2, 20696, 'daily-classic-en-US-v1', 1, false,
    '[{"word":"crane","feedback":[0,1,0,0,2],"accepted_at":"2026-08-31T12:00:00Z"},{"word":"slate","feedback":[1,0,2,0,2],"accepted_at":"2026-08-31T12:01:00Z"},{"word":"stone","feedback":[2,2,2,2,2],"accepted_at":"2026-08-31T12:02:00Z"}]',
    'solved', 3,
    '2026-08-31T12:03:00Z'
  ) #>> '{error,code}',
  'invalid_daily_payload',
  'result import with an inconsistent number/day tuple is rejected with a typed error'
);
select is(
  public.sync_daily_progress(
    'daily-classic-2028-08-24', 725, 21420, 'daily-classic-en-US-v1', 1, false,
    '[]'::jsonb, null
  ) ->> 'status',
  'inserted',
  'canonical last-schedule-day progress is accepted'
);
select is(
  public.import_daily_result(
    'daily-classic-2026-08-31', 1, 20696, 'daily-classic-en-US-v1', 1, false,
    '[{"word":"crane","feedback":[0,1,0,0,2],"accepted_at":"2026-08-31T12:00:00Z"},{"word":"slate","feedback":[1,0,2,0,2],"accepted_at":"2026-08-31T12:01:00Z"},{"word":"stone","feedback":[2,2,2,2,2],"accepted_at":"2026-08-31T12:02:00Z"}]',
    'solved', 3,
    '2026-08-31T12:03:00Z'
  ) ->> 'status',
  'inserted',
  'canonical first-puzzle result import is accepted'
);
reset role;

-- The table CHECK constraints enforce the same contract for privileged
-- writes that bypass the RPC guards.
set local role service_role;
select throws_ok(
  $$insert into public.daily_progress (
      user_id, puzzle_id, puzzle_number, puzzle_day, word_pack_id,
      schedule_version, hard_mode_enabled, guesses
    ) values (
      '50000000-0000-0000-0000-000000000001', 'daily-classic-2026-08-31',
      2, 20696, 'daily-classic-en-US-v1', 1, false, '[]'
    )$$,
  '23514',
  'new row for relation "daily_progress" violates check constraint "daily_progress_identity_check"',
  'privileged insert of an inconsistent identity tuple violates the table check'
);
select lives_ok(
  $$insert into public.daily_progress (
      user_id, puzzle_id, puzzle_number, puzzle_day, word_pack_id,
      schedule_version, hard_mode_enabled, guesses
    ) values (
      '50000000-0000-0000-0000-000000000001', 'daily-classic-2026-08-31',
      1, 20696, 'daily-classic-en-US-v1', 1, false, '[]'
    )$$,
  'privileged insert of the canonical identity tuple succeeds'
);
reset role;

select * from finish();
rollback;
