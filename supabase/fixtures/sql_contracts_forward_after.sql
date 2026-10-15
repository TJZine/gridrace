begin;
do $$
declare baseline jsonb; current_rows jsonb; rec record; response jsonb; m uuid; actor uuid;
begin
  select e.response into strict baseline from private.sql_contracts_forward_evidence e where label='captured_rows';
  current_rows:=private.sql_contracts_forward_snapshot();
  if baseline is distinct from current_rows then
    raise exception 'forward preservation mismatch in: %',
      (select string_agg(key,', ' order by key) from jsonb_each(baseline) where value is distinct from current_rows->key);
  end if;
  if exists(select 1 from pg_catalog.pg_attribute where attrelid='private.rematch_contexts'::regclass and attname='actor_epochs' and not attisdropped)
    or not exists(select 1 from pg_catalog.pg_attribute where attrelid='private.rematch_contexts'::regclass and attname='participation_epochs_by_member_id' and not attisdropped) then
    raise exception 'private epoch column contract did not migrate';
  end if;
  if to_regprocedure('private.normalize_rematch(uuid,timestamptz)') is not null
    or to_regprocedure('private.rematch_projection(uuid,uuid,timestamptz)') is not null
    or to_regprocedure('private.rematch_command_result(uuid,uuid,integer,text,bigint)') is not null then
    raise exception 'obsolete private helper still exists';
  end if;
  for rec in select * from private.sql_contracts_forward_evidence where request_id is not null order by label loop
    if rec.kind='join' then
      response:=public.join_match(rec.actor_id,3,rec.join_code,null,rec.request_id,rec.match_id);
    else
      response:=public.rematch_command(rec.actor_id,3,rec.request_id,rec.match_id,1,rec.kind,rec.epoch);
    end if;
    if response is distinct from rec.response then raise exception 'original request replay changed: %',rec.label; end if;
  end loop;
  if baseline is distinct from private.sql_contracts_forward_snapshot() then
    raise exception 'receipt replay mutated captured state';
  end if;
  select match_id,actor_id into strict m,actor from private.sql_contracts_forward_evidence where label='offered';
  response:=public.match_snapshot(actor,3,m);
  if response#>>'{data,rematch,state}' is distinct from 'offered' then raise exception 'offered projection did not survive'; end if;
  select member.auth_user_id into strict actor from public.match_members member where member.match_id=m and member.seat=2;
  response:=public.create_match(actor,3,null,extensions.gen_random_uuid(),1::smallint);
  if not response?'data' then raise exception 'participation-change fixture create failed'; end if;
  response:=public.match_snapshot(actor,3,m);
  if response#>>'{data,rematch,reason}' is distinct from 'participation_changed' then
    raise exception 'member-keyed epoch change failed to invalidate consent';
  end if;
  select match_id,actor_id into strict m,actor from private.sql_contracts_forward_evidence where label='accepted';
  response:=public.match_snapshot(actor,3,m);
  if response#>>'{data,rematch,state}' is distinct from 'accepted'
    or response#>>'{data,rematch,successor_available}' is distinct from 'true' then
    raise exception 'accepted successor recovery did not survive';
  end if;
end $$;
rollback;
