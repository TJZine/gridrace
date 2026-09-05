begin;

-- GR-08: enforce the canonical Daily Classic v1 identity tuple.
--
-- Schedule source: shared/word-packs/daily-classic-en-US-v1 (schedule
-- version 1, epoch day 20696 = 2026-08-31, 725 published answers, so puzzle
-- days 20696..21420 carry puzzle numbers 1..725). The previous check
-- accepted each field in isolation, so a structurally valid tuple could mix
-- an inconsistent puzzle id/number/day/word-pack/schedule combination or an
-- out-of-range day.
--
-- The ordered CASE fails closed on null or out-of-range days before any date
-- arithmetic or linkage comparison runs, so extreme integer input is rejected
-- instead of raising a date/arithmetic overflow. Existing CHECK constraints
-- and both daily RPC guards call this function, so no other surface changes.
create or replace function private.valid_daily_identity(
  p_puzzle_id text,
  p_puzzle_number integer,
  p_puzzle_day integer,
  p_word_pack_id text,
  p_schedule_version integer
)
returns boolean
language sql
immutable
security invoker
set search_path = ''
as $$
  select case
    when p_puzzle_day is null
      or p_puzzle_day not between 20696 and 21420
    then false
    when p_puzzle_number is null
      or p_puzzle_number not between 1 and 725
    then false
    when p_word_pack_id is distinct from 'daily-classic-en-US-v1'
      or p_schedule_version is distinct from 1
    then false
    when p_puzzle_number <> p_puzzle_day - 20695
    then false
    else p_puzzle_id is not distinct from 'daily-classic-'
      || to_char(date '1970-01-01' + p_puzzle_day, 'YYYY-MM-DD')
  end;
$$;

commit;
