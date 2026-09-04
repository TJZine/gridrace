begin;

-- GR-06: replace the timing-bearing public.matches.updated_at Realtime signal
-- with a timestamp-free monotonically increasing revision.
--
-- Every canonical mutation (join, start, guess, deadline finalization, and the
-- deletion paths) already UPDATEs the match row inside its own transaction, so
-- a single row trigger advances the signal for each of them without rewriting
-- migration history. Idempotent replays (duplicate join/start, identical guess
-- retry, repeated finalizer, repeat deletion preparation) perform no UPDATE
-- and therefore leave the revision untouched.
--
-- Existing rows backfill to revision 1 via the column default; new rows start
-- at 1 and each canonical change adds exactly one.

alter table public.matches
  add column revision bigint not null default 1;

alter table public.matches
  add constraint matches_revision_check check (revision >= 1);

create or replace function private.touch_match_revision()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.revision := old.revision + 1;
  return new;
end;
$$;

create trigger matches_touch_revision
before update on public.matches
for each row execute function private.touch_match_revision();

-- Authenticated roster members keep least-privilege row access through the
-- unchanged RLS membership policy but lose the exact-action-timing column.
-- service_role keeps full access. Column grants fail closed: any future column
-- stays hidden until it is explicitly granted.
revoke all on public.matches from authenticated;

grant select (
  id,
  join_code,
  creator_member_id,
  mode,
  round_count,
  current_round,
  status,
  created_at,
  started_at,
  completed_at,
  expires_at,
  minimum_client_build,
  revision
) on public.matches to authenticated;

-- The published Realtime projection carries the same timing-free column set,
-- so matches.updated_at can be neither selected nor received by an
-- authenticated client. The table stays published, preserving the existing
-- roster-authorized row subscription.
alter publication supabase_realtime drop table public.matches;

alter publication supabase_realtime add table public.matches (
  id,
  join_code,
  creator_member_id,
  mode,
  round_count,
  current_round,
  status,
  created_at,
  started_at,
  completed_at,
  expires_at,
  minimum_client_build,
  revision
);

commit;
