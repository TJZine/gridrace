begin;


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
