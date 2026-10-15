begin;
insert into auth.users(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,created_at,updated_at)
select ('d3000000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,
 '00000000-0000-0000-0000-000000000000','authenticated','authenticated',
 'friends-forward-'||n||'@example.test','unused',now(),now(),now() from generate_series(1,14)n;
create table public.friends_beta_forward_evidence(label text primary key,match_id uuid,receipt jsonb);
do $$
declare host uuid:='d3000000-0000-0000-0000-000000000001'; guest uuid:='d3000000-0000-0000-0000-000000000002';
 m uuid; r uuid; answer text; response jsonb; n smallint; total smallint; label text; pair_index integer:=0;
begin
 foreach label in array array['legacy_live','legacy_completed','v2_completed_1','v2_completed_3','v2_completed_5','v2_active_3','v2_incomplete_5'] loop
   pair_index:=pair_index+1;
   host:=('d3000000-0000-0000-0000-'||lpad((2*pair_index-1)::text,12,'0'))::uuid;
   guest:=('d3000000-0000-0000-0000-'||lpad((2*pair_index)::text,12,'0'))::uuid;
   delete from private.user_rate_limits;
   total:=case when label like '%_3' then 3 when label like '%_5' then 5 else 1 end;
   response:=public.create_match(host,case when label like 'legacy%' then 1 else 2 end,null,extensions.gen_random_uuid(),total);
   m:=(response#>>'{data,match_id}')::uuid;
   insert into public.friends_beta_forward_evidence values(label,m,response);
   perform public.join_match(guest,2,(select join_code from public.matches where id=m));
   for n in 1..case when label like '%completed%' then total else 1 end loop
     perform public.start_match(host,2,m,n::smallint);
     select id into r from public.rounds where match_id=m and round_number=n;
     update public.rounds set starts_at=now()-interval '1 second',ends_at=now()+interval '179 seconds' where id=r;
     update public.player_rounds set started_at=now()-interval '1 second' where round_id=r;
     select secret.answer into answer from private.round_secrets secret where round_id=r;
     perform public.submit_guess(host,case when label like 'legacy%' then 1 else 2 end,m,n::smallint,extensions.gen_random_uuid(),answer,null);
     if label like '%completed%' or label like '%incomplete%' then
       update public.rounds set starts_at=now()-interval '4 minutes',ends_at=now()-interval '1 minute' where id=r;
       perform private.finalize_round(r);
     end if;
   end loop;
   if label='legacy_completed' then
     update public.matches set completed_at=now()-interval '10 minutes' where id=m;
     update public.rounds set completed_at=now()-interval '10 minutes' where match_id=m;
   end if;
   if label like '%incomplete%' then perform public.delete_account(guest,2); end if;
 end loop;
end $$;
commit;
