alter table public.profiles
  add column setup_completed boolean not null default false;

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
create trigger profiles_complete_setup_on_name_save
before update of display_name on public.profiles
for each row execute function private.complete_profile_setup_on_name_save();

revoke execute on function private.complete_profile_setup_on_name_save()
  from public, anon, authenticated;

grant select (setup_completed) on public.profiles to authenticated;
