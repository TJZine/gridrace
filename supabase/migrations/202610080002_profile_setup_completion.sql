-- Preserve the selected legacy classification without rewriting any player name.
-- This mapping does not establish whether a generated-looking name was once saved.
alter table public.profiles
  add column setup_completed boolean not null default false;

-- Backfill is classification, not a user edit; retain the original edit timestamps.
alter table public.profiles disable trigger profiles_touch_updated_at;
update public.profiles
set setup_completed = not (display_name ~ '^Player [0-9a-f]{6}$');
alter table public.profiles enable trigger profiles_touch_updated_at;

create function private.complete_profile_setup_on_name_save()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.setup_completed := true;
  return new;
end;
$$;

-- UPDATE OF observes the Save intent, including unchanged names from old clients.
-- Constraint failures roll back this transition with the rest of the update.
create trigger profiles_complete_setup_on_name_save
before update of display_name on public.profiles
for each row execute function private.complete_profile_setup_on_name_save();

revoke execute on function private.complete_profile_setup_on_name_save()
  from public, anon, authenticated;

-- The existing owner-scoped RLS and name/avatar UPDATE grants remain unchanged.
grant select (setup_completed) on public.profiles to authenticated;
