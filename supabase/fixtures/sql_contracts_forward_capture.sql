begin;
create function private.sql_contracts_forward_snapshot() returns jsonb
language plpgsql security invoker set search_path='' as $$
declare v_relation_name text; rows jsonb; result jsonb:='{}';
begin
  foreach v_relation_name in array array[
    'auth.users','public.profiles','public.matches','public.match_members','public.rounds',
    'public.player_rounds','public.guesses','public.daily_progress','public.daily_imported_results',
    'public.match_rematch_signals',
    'private.round_secrets','private.words','private.create_requests','private.guess_requests',
    'private.user_rate_limits','private.ip_rate_limits','private.live_feature_configuration',
    'private.participation_cursors','private.live_command_receipts','private.rematch_successors',
    'private.account_deletion_receipts'
  ] loop
    execute format('select coalesce(jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text),''[]''::jsonb) from %s t',v_relation_name) into rows;
    result:=result||jsonb_build_object(v_relation_name,rows);
  end loop;
  select coalesce(jsonb_agg(row_data order by row_data::text),'[]'::jsonb) into rows from (
    select (to_jsonb(c)-'actor_epochs'-'participation_epochs_by_member_id')||
      jsonb_build_object('participation_epochs_by_member_id',
        coalesce(to_jsonb(c)->'participation_epochs_by_member_id',to_jsonb(c)->'actor_epochs')) as row_data
    from private.rematch_contexts c
  ) contexts;
  result:=result||jsonb_build_object('private.rematch_contexts',rows);
  select jsonb_agg(to_jsonb(metadata) order by schema_name,function_name,arguments) into rows from (
    select p.oid,n.nspname as schema_name,
      case when p.proname in ('normalize_rematch','rematch_projection','rematch_command_result')
        then p.proname||'_with_locked_participation' else p.proname end as function_name,
      pg_catalog.pg_get_function_identity_arguments(p.oid) as arguments,
      p.proowner,p.proacl,p.prosecdef,p.provolatile,p.proconfig,p.prorettype,p.prolang,
      p.proisstrict,p.proparallel,p.proleakproof,p.prokind,p.procost,p.prorows
    from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid=p.pronamespace
    where (n.nspname='private' and p.proname in (
      'normalize_rematch','rematch_projection','rematch_command_result',
      'normalize_rematch_with_locked_participation','rematch_projection_with_locked_participation',
      'rematch_command_result_with_locked_participation'))
      or (n.nspname='public' and p.proname in ('complete_account_deletion','delete_account','match_snapshot','rematch_command','join_match'))
  ) metadata;
  result:=result||jsonb_build_object('function_metadata',rows);
  select jsonb_agg(to_jsonb(metadata) order by schema_name,relation_name) into rows from (
    select c.oid,n.nspname as schema_name,c.relname as relation_name,c.relowner,c.relacl,c.relrowsecurity,c.relforcerowsecurity
    from pg_catalog.pg_class c join pg_catalog.pg_namespace n on n.oid=c.relnamespace
    where n.nspname in ('public','private','app_rls') and c.relkind in ('r','p')
      and c.relname<>'sql_contracts_forward_evidence'
  ) metadata;
  result:=result||jsonb_build_object('relation_metadata',rows);
  select jsonb_agg(to_jsonb(metadata) order by relation_id,column_number) into rows from (
    select a.attrelid as relation_id,a.attnum as column_number,
      case when c.oid='private.rematch_contexts'::regclass and a.attname='actor_epochs'
        then 'participation_epochs_by_member_id' else a.attname end as column_name,
      a.atttypid,a.atttypmod,a.attnotnull,a.attacl,a.attidentity,a.attgenerated,
      pg_catalog.pg_get_expr(d.adbin,d.adrelid) as default_expression
    from pg_catalog.pg_attribute a join pg_catalog.pg_class c on c.oid=a.attrelid
    join pg_catalog.pg_namespace n on n.oid=c.relnamespace
    left join pg_catalog.pg_attrdef d on d.adrelid=a.attrelid and d.adnum=a.attnum
    where n.nspname in ('public','private','app_rls') and c.relkind in ('r','p')
      and c.relname<>'sql_contracts_forward_evidence' and a.attnum>0 and not a.attisdropped
  ) metadata;
  result:=result||jsonb_build_object('column_metadata',rows);
  select coalesce(jsonb_agg(to_jsonb(p) order by p.oid),'[]'::jsonb) into rows
    from pg_catalog.pg_policy p join pg_catalog.pg_class c on c.oid=p.polrelid
    join pg_catalog.pg_namespace n on n.oid=c.relnamespace where n.nspname in ('public','private','app_rls');
  result:=result||jsonb_build_object('policies',rows);
  select coalesce(jsonb_agg(to_jsonb(p) order by p.oid),'[]'::jsonb) into rows
    from pg_catalog.pg_publication_rel p join pg_catalog.pg_class c on c.oid=p.prrelid
    join pg_catalog.pg_namespace n on n.oid=c.relnamespace where n.nspname in ('public','private','app_rls');
  return result||jsonb_build_object('publication_relations',rows);
end $$;
revoke all on function private.sql_contracts_forward_snapshot() from public,anon,authenticated;
do $$
declare m uuid;
begin
  if (select count(*) from private.sql_contracts_forward_evidence where label in ('offered','accepted','eligible'))<>3
    or (select count(*) from private.sql_contracts_forward_evidence where request_id is not null)<>4 then
    raise exception 'all three fixture states and four replay requests required';
  end if;
  select match_id into strict m from private.sql_contracts_forward_evidence where label='offered';
  if not exists(select 1 from private.rematch_contexts where predecessor_match_id=m and state='offered'
    and cardinality(consenting_member_ids)=1 and actor_epochs<>'{}'::jsonb
    and (select count(*) from jsonb_object_keys(actor_epochs))=2) then
    raise exception 'offered fixture must retain two member epochs and one consent';
  end if;
  if exists(select 1 from private.rematch_contexts c cross join lateral jsonb_each(c.actor_epochs) e
    where c.predecessor_match_id=m and not exists(select 1 from public.match_members member
      join private.participation_cursors cursor on cursor.actor_user_id=member.auth_user_id
      where member.match_id=m and member.id::text=e.key and to_jsonb(cursor.epoch)=e.value)) then
    raise exception 'epoch map must contain roster MEMBER IDs with current actor epochs';
  end if;
  if not exists(select 1 from private.rematch_contexts c join private.rematch_successors s
      on s.match_id=c.successor_match_id and s.predecessor_match_id=c.predecessor_match_id
    where c.predecessor_match_id=(select match_id from private.sql_contracts_forward_evidence where label='accepted')
      and c.state='accepted' and cardinality(c.consenting_member_ids)=2 and cardinality(s.excluded_answers)=1)
    or not exists(select 1 from private.rematch_contexts where state='eligible'
      and predecessor_match_id=(select match_id from private.sql_contracts_forward_evidence where label='eligible')) then
    raise exception 'accepted successor/consent/exclusion and eligible context required';
  end if;
  if (select count(*) from private.sql_contracts_forward_evidence e
      join private.live_command_receipts r on r.actor_user_id=e.actor_id and r.request_id=e.request_id
      where e.request_id is not null and r.response=e.response
        and r.kind=case when e.kind='join' then 'join' else 'rematch' end)<>4 then
    raise exception 'all four original responses must have durable matching receipts';
  end if;
  if (select count(distinct deletion_id) from private.account_deletion_receipts
      where token_hash in (repeat('a',64),repeat('b',64),repeat('c',64),repeat('d',64)))<>2
    or (select count(*) from private.account_deletion_receipts where token_hash in (repeat('a',64),repeat('b',64)) and status='pending' and user_id is not null)<>2
    or (select count(distinct deletion_id) from private.account_deletion_receipts where token_hash in (repeat('a',64),repeat('b',64)))<>1
    or (select count(*) from private.account_deletion_receipts where token_hash in (repeat('c',64),repeat('d',64)) and status='completed' and user_id is null and completed_at is not null)<>2
    or (select count(distinct deletion_id) from private.account_deletion_receipts where token_hash in (repeat('c',64),repeat('d',64)))<>1 then
    raise exception 'pending and completed rotated deletion groups required';
  end if;
  if (select count(*) from private.participation_cursors where actor_user_id::text like 'd4000000-%')<>6
    or (select count(*) from private.guess_requests where actor_user_id::text like 'd4000000-%')<>3
    or (select count(*) from private.create_requests where actor_user_id::text like 'd4000000-%')<>3
    or (select count(*) from private.round_secrets s join public.rounds r on r.id=s.round_id
      where r.match_id in(select match_id from private.sql_contracts_forward_evidence where label in ('offered','accepted','eligible')))<>3 then
    raise exception 'populated cursors, gameplay, secrets and original receipts required';
  end if;
  if jsonb_array_length(private.sql_contracts_forward_snapshot()->'function_metadata')<>8 then
    raise exception 'all three private helpers and five public entrypoint metadata rows required';
  end if;
  insert into private.sql_contracts_forward_evidence(label,response)
    values('captured_rows',private.sql_contracts_forward_snapshot());
end $$;
commit;
