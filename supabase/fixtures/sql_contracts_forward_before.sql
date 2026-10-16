begin;
create table private.sql_contracts_forward_evidence (
  label text primary key,
  actor_id uuid,
  match_id uuid,
  request_id uuid,
  kind text,
  epoch bigint,
  join_code text,
  response jsonb
);
revoke all on private.sql_contracts_forward_evidence from public, anon, authenticated;
insert into auth.users(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,created_at,updated_at)
select ('d4000000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,
 '00000000-0000-0000-0000-000000000000','authenticated','authenticated',
 'sql-contract-forward-'||n||'@example.test','unused',now(),now(),now()
from generate_series(1,8) n;
update private.live_feature_configuration set allow_new_rematches=true;
do $$
declare a uuid; b uuid; m uuid; r uuid; req uuid; answer text; response jsonb; epoch bigint; label text; pair_index integer:=0;
begin
  foreach label in array array['offered','accepted','eligible'] loop
    pair_index:=pair_index+1;
    a:=('d4000000-0000-0000-0000-'||lpad((2*pair_index-1)::text,12,'0'))::uuid;
    b:=('d4000000-0000-0000-0000-'||lpad((2*pair_index)::text,12,'0'))::uuid;
    response:=public.create_match(a,3,null,extensions.gen_random_uuid(),1::smallint);
    m:=(response#>>'{data,match_id}')::uuid;
    if m is null then raise exception 'fixture create failed: %',label; end if;
    response:=public.join_match(b,3,(select join_code from public.matches where id=m),null,extensions.gen_random_uuid(),null);
    if not response?'data' then raise exception 'fixture join failed: %',label; end if;
    response:=public.start_match(a,3,m,1::smallint);
    if not response?'data' then raise exception 'fixture start failed: %',label; end if;
    select id into r from public.rounds where match_id=m;
    update public.rounds set starts_at=now()-interval '1 second',ends_at=now()+interval '179 seconds' where id=r;
    update public.player_rounds set started_at=now()-interval '1 second' where round_id=r;
    select s.answer into answer from private.round_secrets s where round_id=r;
    response:=public.submit_guess(a,3,m,1::smallint,extensions.gen_random_uuid(),answer,null);
    if not response?'data' then raise exception 'fixture guess failed: %',label; end if;
    update public.rounds set starts_at=now()-interval '4 minutes',ends_at=now()-interval '1 minute' where id=r;
    response:=public.match_snapshot(a,3,m);
    if response#>>'{data,rematch,state}' is distinct from 'eligible' then raise exception 'fixture completion failed: %',label; end if;
    insert into private.sql_contracts_forward_evidence(label,actor_id,match_id) values(label,a,m);
    if label='eligible' then continue; end if;
    epoch:=(response#>>'{data,selection,epoch}')::bigint;
    req:=extensions.gen_random_uuid();
    response:=public.rematch_command(a,3,req,m,1,'offer',epoch);
    if response#>>'{data,state}' is distinct from 'offered' then raise exception 'fixture offer failed: %',label; end if;
    insert into private.sql_contracts_forward_evidence values(label||'_offer',a,m,req,'offer',epoch,null,response);
    if label='accepted' then
      epoch:=(public.match_snapshot(b,3,m)#>>'{data,selection,epoch}')::bigint;
      req:=extensions.gen_random_uuid();
      response:=public.rematch_command(b,3,req,m,1,'accept',epoch);
      if response#>>'{data,state}' is distinct from 'accepted' then raise exception 'fixture acceptance failed'; end if;
      insert into private.sql_contracts_forward_evidence values('accepted_accept',b,m,req,'accept',epoch,null,response);
      m:=(response#>>'{data,successor_match_id}')::uuid;
      req:=extensions.gen_random_uuid();
      select join_code into label from public.matches where id=m;
      response:=public.join_match(a,3,label,null,req,m);
      if not response?'data' then raise exception 'fixture pinned join failed'; end if;
      insert into private.sql_contracts_forward_evidence values('accepted_pinned_join',a,m,req,'join',null,label,response);
    end if;
  end loop;
  for pair_index in 7..8 loop
    a:=('d4000000-0000-0000-0000-'||lpad(pair_index::text,12,'0'))::uuid;
    response:=public.begin_account_deletion(a,3,repeat(case when pair_index=7 then 'a' else 'c' end,64));
    if response#>>'{data,status}' is distinct from 'pending' then raise exception 'fixture deletion preparation failed'; end if;
    response:=public.begin_account_deletion(a,3,repeat(case when pair_index=7 then 'b' else 'd' end,64));
    if response#>>'{data,status}' is distinct from 'pending' then raise exception 'fixture deletion rotation failed'; end if;
    if pair_index=8 then
      delete from auth.users where id=a;
      response:=public.complete_account_deletion(repeat('d',64));
      if response#>>'{data,status}' is distinct from 'completed' then raise exception 'fixture deletion completion failed'; end if;
    end if;
  end loop;
end $$;
commit;
