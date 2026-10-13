-- Run on the owned forward-upgraded fixture before any clean reset.
begin;
do $$
declare rec record; response jsonb;
begin
  if (select count(*) from private.guess_requests)=0 then raise exception 'populated guess receipts required'; end if;
  for rec in select e.match_id,m.auth_user_id from public.friends_beta_forward_evidence e
    join public.match_members m on m.match_id=e.match_id and m.seat=1 loop
    response:=public.match_snapshot(rec.auth_user_id,3,rec.match_id);
    if response#>>'{data,version}'<>'3' or response#>>'{data,match,id}'<>rec.match_id::text then
      raise exception 'current projection cannot recover preserved match';
    end if;
    if response#>>'{data,selection,is_selected}'<>'false' then raise exception 'passive preserved-room recovery selected'; end if;
  end loop;
  response:=public.match_snapshot((select auth_user_id from public.match_members where match_id=(select match_id from public.friends_beta_forward_evidence where label='legacy_completed') and seat=1),3,(select match_id from public.friends_beta_forward_evidence where label='legacy_completed'));
  if response#>>'{data,rematch,state}'<>'expired' then raise exception 'old deadline reopened'; end if;
  if exists(select 1 from information_schema.role_table_grants where table_schema='private' and grantee in ('anon','authenticated')) then
    raise exception 'private table grant broadened';
  end if;
end $$;
rollback;
