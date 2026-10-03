begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

-- Synthetic identities; every fixture is rolled back with the test transaction.
insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at)
select ('b4000000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid,
  '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
  'multi-' || n || '@example.test', 'unused', now(), now(), now()
from generate_series(1, 20) n;

select ok(not has_column_privilege('authenticated', 'public.matches', 'terminal_reason', 'select'), 'block reason has no client grant');
select ok(not has_column_privilege('authenticated', 'public.matches', 'updated_at', 'select'), 'exact mutation time remains hidden');
select ok(not exists (
  select 1 from pg_publication_tables where pubname = 'supabase_realtime'
    and tablename = 'matches' and 'terminal_reason' = any(attnames)
), 'block reason is absent from Realtime');
select ok(has_function_privilege('service_role', 'public.create_match(uuid,integer,text,uuid,smallint)', 'execute'), 'service can create configured match');
select ok(has_function_privilege('service_role', 'public.start_match(uuid,integer,uuid,smallint)', 'execute'), 'service can start explicit round');
select ok(not has_function_privilege('authenticated', 'public.create_match(uuid,integer,text,uuid,smallint)', 'execute'), 'client cannot create directly');
select ok(not has_function_privilege('anon', 'public.start_match(uuid,integer,uuid,smallint)', 'execute'), 'anonymous cannot start directly');
select ok(not has_function_privilege('authenticated', 'public.start_match(uuid,integer,uuid,smallint)', 'execute'), 'client cannot start directly');
select ok(not has_table_privilege('authenticated', 'private.round_secrets', 'select'), 'round secrets stay private');
select ok(not has_table_privilege('authenticated', 'private.create_requests', 'select'), 'configuration receipts stay private');

create function pg_temp.exercise(p_count smallint) returns setof text
language plpgsql as $$
declare
  host uuid := 'b4000000-0000-0000-0000-000000000001';
  guest uuid := 'b4000000-0000-0000-0000-000000000002';
  outsider uuid := 'b4000000-0000-0000-0000-000000000003';
  request uuid := extensions.gen_random_uuid();
  guess_request uuid := extensions.gen_random_uuid();
  m uuid; r uuid; answer text; first_answer text;
  response jsonb; receipt jsonb; snapshot jsonb; previous jsonb;
  revision bigint; n smallint;
begin
  delete from private.user_rate_limits;
  response := public.create_match(host, 2, null, request, p_count);
  m := (response #>> '{data,match_id}')::uuid;
  return next ok(m is not null, p_count || ': create succeeds');
  return next is((select count(*) from public.rounds where match_id=m), p_count::bigint, p_count || ': all pending rounds exist');
  return next is((select minimum_client_build from public.matches where id=m), 2, p_count || ': new room floor is 2');
  return next is(public.create_match(host,2,null,request,p_count), response, p_count || ': create retry original identity');
  return next is(public.create_match(host,2,null,request,case when p_count=1 then 3 else 1 end::smallint) #>> '{error,code}', 'request_conflict', p_count || ': changed count conflicts');
  return next is(public.create_match(host,3,null,request,p_count) #>> '{error,code}', 'request_conflict', p_count || ': changed build conflicts');
  return next is(public.match_snapshot(host,1,m) #>> '{error,code}', 'client_update_required', p_count || ': legacy snapshot denied');
  snapshot := public.match_snapshot(host,2,m)->'data';
  return next is(snapshot->>'version', '2', p_count || ': snapshot v2');
  return next is(snapshot->'standings', 'null'::jsonb, p_count || ': lobby has no totals');
  return next is(snapshot->'revealed_rounds', '[]'::jsonb, p_count || ': lobby has no reveals');
  return next is(snapshot #> '{round,players}', '[]'::jsonb, p_count || ': lobby has no boards');
  return next ok(snapshot #> '{match,started_at}' = 'null'::jsonb and snapshot #> '{match,completed_at}' = 'null'::jsonb and snapshot #> '{match,terminal_reason}' = 'null'::jsonb, p_count || ': lobby matrix');
  return next is(public.start_match(host,2,m,1::smallint) #>> '{error,code}', 'not_enough_players', p_count || ': two seats required');
  response := public.join_match(guest,2,(select join_code from public.matches where id=m));
  return next ok(response ? 'data', p_count || ': second player joins');
  return next is(public.start_match(outsider,2,m,1::smallint) #>> '{error,code}', 'not_a_match_member', p_count || ': outsider start denied');
  return next is(public.start_match(guest,2,m,1::smallint) #>> '{error,code}', 'not_host', p_count || ': guest start denied');
  return next is(public.start_match(host,1,m,1::smallint) #>> '{error,code}', 'client_update_required', p_count || ': legacy start denied');
  return next is(public.start_match(host,2,m,0::smallint) #>> '{error,code}', 'round_not_active', p_count || ': invalid target denied');
  for n in 1..p_count loop
    response := public.start_match(host,2,m,n::smallint);
    return next ok(response ? 'data', p_count || ': targeted Start ' || n);
    select id into r from public.rounds where match_id=m and round_number=n;
    select secret.answer into answer from private.round_secrets secret where round_id=r;
    if n=1 then first_answer := answer; end if;
    select matches.revision into revision from public.matches where id=m;
    return next is(public.start_match(host,2,m,n::smallint), response, p_count || ': duplicate target ' || n);
    return next is((select matches.revision from public.matches where id=m), revision, p_count || ': duplicate no revision ' || n);
    return next is((select count(*) from private.round_secrets s join public.rounds rr on rr.id=s.round_id where rr.match_id=m), n::bigint, p_count || ': no future secrets ' || n);
    return next is((select count(distinct s.answer) from private.round_secrets s join public.rounds rr on rr.id=s.round_id where rr.match_id=m), n::bigint, p_count || ': no repeated answers ' || n);
    return next is((select count(*) from public.player_rounds p join public.rounds rr on rr.id=p.round_id where rr.match_id=m), (2*n)::bigint, p_count || ': no future player rows ' || n);
    snapshot := public.match_snapshot(host,2,m)->'data';
    return next is(snapshot #>> '{round,state}', 'countdown', p_count || ': countdown ' || n);
    return next is(jsonb_array_length(snapshot->'revealed_rounds'), (n-1)::integer, p_count || ': prior reveals only ' || n);
    return next is(snapshot #> '{round,answer}', 'null'::jsonb, p_count || ': answer hidden ' || n);
    return next ok(snapshot #> '{round,players,1,board}'='null'::jsonb and snapshot #> '{round,players,1,solve_duration_ms}'='null'::jsonb and snapshot #> '{round,players,1,efficiency_points}'='null'::jsonb, p_count || ': opponent clues/time hidden ' || n);
    if n<p_count then
      return next is(public.start_match(host,2,m,(n+1)::smallint) #>> '{error,code}', 'round_not_active', p_count || ': active round prevents advance ' || n);
      return next is(public.submit_guess(host,2,m,(n+1)::smallint,extensions.gen_random_uuid(),'apple') #>> '{error,code}', 'round_not_active', p_count || ': future guess denied ' || n);
    end if;
    update public.rounds set starts_at=now()-interval '1 second', ends_at=now()+interval '179 seconds' where id=r;
    update public.player_rounds set started_at=now()-interval '1 second' where round_id=r;
    response := public.submit_guess(host,2,m,n::smallint,case when n=1 then guess_request else extensions.gen_random_uuid() end,answer);
    return next is(response #>> '{data,player_state}', 'solved', p_count || ': own solve ' || n);
    if n=1 then receipt := response; end if;
    snapshot := public.match_snapshot(guest,2,m)->'data';
    return next is(jsonb_array_length(snapshot->'revealed_rounds'), (n-1)::integer, p_count || ': current solve excluded from history ' || n);
    return next ok(snapshot #> '{round,players,0,board}'='null'::jsonb and snapshot #> '{round,players,0,solve_duration_ms}'='null'::jsonb, p_count || ': opponent solve hidden ' || n);
    response := public.submit_guess(guest,2,m,n::smallint,extensions.gen_random_uuid(),answer);
    return next is(response #>> '{data,player_state}', 'solved', p_count || ': second solve finalizes ' || n);
    -- Independent exact-time fixtures: equal displayed milliseconds, unequal SQL ranks;
    -- floor(sum) differs from sum(floor) across rounds.
    update public.player_rounds p set solve_duration_us=case when member.seat=1 then 1600 else 1900 end,
      finished_at=p.started_at + case when member.seat=1 then interval '1600 microseconds' else interval '1900 microseconds' end
    from public.match_members member where p.round_id=r and member.id=p.member_id;
    snapshot := public.match_snapshot(host,2,m)->'data';
    return next is(snapshot #>> '{match,status}', case when n=p_count then 'completed' else 'in_progress' end, p_count || ': reveal status ' || n);
    return next is(jsonb_array_length(snapshot->'revealed_rounds'), n::integer, p_count || ': contiguous history ' || n);
    return next is(snapshot->'round', snapshot->'revealed_rounds'->(n-1), p_count || ': current/history identical ' || n);
    return next is(snapshot #>> '{standings,through_round}', n::text, p_count || ': through revealed round ' || n);
    return next is(snapshot #>> '{standings,is_final}', (n=p_count)::text, p_count || ': final only after configured count ' || n);
    return next is(snapshot #>> '{standings,players,0,placement}', '1', p_count || ': exact total winner ' || n);
    return next is(snapshot #>> '{standings,players,1,placement}', '2', p_count || ': exact total loser ' || n);
    return next is(snapshot #>> '{standings,players,0,total_solve_duration_ms}', ((1600*n)/1000)::text, p_count || ': floor SUM once ' || n);
    return next is(snapshot #>> '{standings,players,0,rounds_solved}', n::text, p_count || ': rounds solved ' || n);
    return next is(snapshot #>> '{standings,players,0,efficiency_points}', (6*n)::text, p_count || ': total efficiency ' || n);
    return next is(public.submit_guess(host,2,m,1::smallint,guess_request,upper(first_answer)), receipt, p_count || ': receipt replay across round/final ' || n);
    return next is(public.submit_guess(host,2,m,n::smallint,guess_request,first_answer) #>> '{error,code}', case when n=1 then null else 'request_conflict' end, p_count || ': changed round conflict ' || n);
    return next is(public.submit_guess(host,2,m,n::smallint,extensions.gen_random_uuid(),answer) #>> '{error,code}', 'round_already_finished', p_count || ': old unreceipted guess denied ' || n);
    previous := public.match_snapshot(host,2,m);
    perform private.finalize_round(r);
    return next is(public.match_snapshot(host,2,m), previous, p_count || ': repeated finalization no mutation ' || n);
    select matches.revision into revision from public.matches where id=m;
    return next ok(public.start_match(host,2,m,1::smallint) ? 'data', p_count || ': stale target succeeds ' || n);
    return next is((select current_round from public.matches where id=m), n::smallint, p_count || ': stale never advances ' || n);
    return next is((select matches.revision from public.matches where id=m), revision, p_count || ': stale no revision ' || n);
  end loop;
  return next ok(snapshot #> '{match,completed_at}'=snapshot #> '{round,completed_at}' and snapshot #> '{match,terminal_reason}'='null'::jsonb, p_count || ': completion matrix');
  return next is(public.create_match(host,2,null,request,p_count) #>> '{data,match_id}', m::text, p_count || ': create replay after final');
  update public.player_rounds p set solve_duration_us=1600, finished_at=started_at+interval '1600 microseconds'
    from public.rounds rr where rr.id=p.round_id and rr.match_id=m;
  snapshot := public.match_snapshot(host,2,m)->'data';
  return next is(snapshot #>> '{standings,players,1,placement}', '1', p_count || ': exact totals tie shares rank');
  return next is(public.start_match(host,2,m,(p_count+1)::smallint) #>> '{error,code}', 'round_not_active', p_count || ': no extra rounds');
  update private.user_rate_limits set attempt_count=30 where actor_user_id=host and action='submit_guess';
  return next is(public.submit_guess(host,2,m,1::smallint,guess_request,first_answer), receipt, p_count || ': receipt precedes rate/final checks');
  return next is((select attempt_count from private.user_rate_limits where actor_user_id=host and action='submit_guess'), 30, p_count || ': replay spends no exhausted quota');
  return next is(public.submit_guess(host,2,m,1::smallint,extensions.gen_random_uuid(),first_answer) #>> '{error,code}', 'rate_limited', p_count || ': exhausted new request remains denied');

end $$;
select * from pg_temp.exercise(1::smallint);
select * from pg_temp.exercise(3::smallint);
select * from pg_temp.exercise(5::smallint);

-- Each deletion boundary gets its own identities, so profile removal is real.
create function pg_temp.deletion_case(p_case integer) returns setof text language plpgsql as $$
declare
  host uuid := ('b4000000-0000-0000-0000-'||lpad((4+2*p_case)::text,12,'0'))::uuid;
  guest uuid := ('b4000000-0000-0000-0000-'||lpad((5+2*p_case)::text,12,'0'))::uuid;
  m uuid; r uuid; snapshot jsonb; before_snapshot jsonb; n smallint; target smallint;
begin
  m := (public.create_match(host,2,null,extensions.gen_random_uuid(),3::smallint) #>> '{data,match_id}')::uuid;
  perform public.join_match(guest,2,(select join_code from public.matches where id=m));
  target := case when p_case in (3,4) then 3 else 1 end;
  for n in 1..target loop
    perform public.start_match(host,2,m,n::smallint);
    select id into r from public.rounds where match_id=m and round_number=n;
    if n<target or p_case in (2,4) then
      update public.player_rounds set state='forfeited',finished_at=now(),efficiency_points=0 where round_id=r;
      perform private.finalize_round(r);
    end if;
  end loop;
  before_snapshot := public.match_snapshot(host,2,m)->'data';
  perform public.delete_account(guest,2);
  snapshot := public.match_snapshot(host,2,m)->'data';
  return next is(snapshot #>> '{match,status}', case p_case when 1 then 'in_progress' when 2 then 'incomplete' when 3 then 'in_progress' else 'completed' end, 'deletion '||p_case||': status');
  return next is(snapshot #>> '{match,terminal_reason}', case when p_case<3 then 'account_deleted' else null end, 'deletion '||p_case||': reason');
  return next ok(snapshot #> '{match,started_at}' <> 'null'::jsonb, 'deletion '||p_case||': started preserved');
  return next is(snapshot #> '{match,completed_at}', case when p_case=4 then before_snapshot #> '{match,completed_at}' else 'null'::jsonb end, 'deletion '||p_case||': completion preserved');
  return next ok(snapshot #>> '{members,1,is_self}'='false' and snapshot #>> '{members,1,is_deleted}'='true' and snapshot #>> '{members,1,display_name}'='Deleted Player', 'deletion '||p_case||': identity anonymized');
  if p_case in (1,3) then
    return next is(snapshot #>> '{round,players,1,state}', 'forfeited', 'deletion '||p_case||': countdown forfeit');
    update public.player_rounds set state='forfeited',finished_at=now(),efficiency_points=0 where round_id=r and state='playing';
    perform private.finalize_round(r);
    snapshot := public.match_snapshot(host,2,m)->'data';
    return next is(snapshot #>> '{match,status}', case when p_case=1 then 'incomplete' else 'completed' end, 'deletion '||p_case||': current completes normally');
  end if;
  if p_case<3 then
    return next is(public.start_match(host,2,m,2::smallint) #>> '{error,code}', 'match_incomplete', 'deletion: future start blocked');
    return next is(snapshot #>> '{standings,is_final}', 'false', 'deletion: partial standings');
    return next is((select count(*) from private.round_secrets s join public.rounds rr on rr.id=s.round_id where rr.match_id=m), 1::bigint, 'deletion: future secrets absent');
  else
    return next is(snapshot #>> '{standings,is_final}', 'true', 'final deletion: final standings');
    return next is(snapshot #> '{match,completed_at}', snapshot #> '{round,completed_at}', 'final deletion: exact completion');
    return next is(snapshot #> '{match,terminal_reason}', 'null'::jsonb, 'final deletion: no block reason');
  end if;
  before_snapshot := snapshot;
  perform public.delete_account(guest,2);
  return next is(public.match_snapshot(host,2,m)->'data', before_snapshot, 'deletion '||p_case||': repeated prep no revision');
  perform public.delete_account(host,2);
  return next is((select status from public.matches where id=m), case when p_case<3 then 'incomplete' else 'completed' end, 'deletion '||p_case||': later deletion stable');
  return next is((select count(*) from public.match_members where match_id=m and auth_user_id is not null), 0::bigint, 'deletion '||p_case||': all retained rounds anonymous');
end $$;
select * from pg_temp.deletion_case(1);
select * from pg_temp.deletion_case(2);
select * from pg_temp.deletion_case(3);
select * from pg_temp.deletion_case(4);

select is(public.create_match('b4000000-0000-0000-0000-000000000001',2,null,extensions.gen_random_uuid(),2::smallint) #>> '{error,code}', 'invalid_match_configuration', 'invalid count denied');
select is(public.create_match('b4000000-0000-0000-0000-000000000001',1,null,extensions.gen_random_uuid(),3::smallint) #>> '{error,code}', 'invalid_match_configuration', 'legacy cannot allocate multiple rounds');
select throws_ok($$update public.matches set status='incomplete', terminal_reason=null, completed_at=null where status='completed'$$, '23514', null, 'incomplete requires deletion reason and nonfinal round');
select throws_ok($$update public.matches set terminal_reason='account_deleted' where status='completed'$$, '23514', null, 'completed cannot have deletion reason');
select throws_ok($$update public.matches set status='in_progress', completed_at=null, terminal_reason='account_deleted' where current_round=round_count$$, '23514', null, 'final active cannot have block reason');
select throws_ok($$update public.matches set current_round=round_count+1$$, '23514', null, 'current cannot exceed configured count');

create function pg_temp.scoring() returns setof text language plpgsql as $$
declare
  host uuid := 'b4000000-0000-0000-0000-000000000004';
  guest uuid := 'b4000000-0000-0000-0000-000000000005';
  m uuid; r uuid; answer text; wrong text; response jsonb; snap jsonb;
  sequence integer; guessed integer; rev bigint; before jsonb;
begin
  for sequence in 1..6 loop
    delete from private.user_rate_limits;
    m := (public.create_match(host,2,null,extensions.gen_random_uuid(),1::smallint) #>> '{data,match_id}')::uuid;
    perform public.join_match(guest,2,(select join_code from public.matches where id=m));
    perform public.start_match(host,2,m,1::smallint);
    select id into r from public.rounds where match_id=m;
    select s.answer into answer from private.round_secrets s where round_id=r;
    select word into wrong from private.words where is_active and is_accepted and word<>answer order by word limit 1;
    update public.rounds set starts_at=now()-interval '1 second',ends_at=now()+interval '179 seconds' where id=r;
    for guessed in 1..sequence loop
      response := public.submit_guess(host,2,m,1::smallint,extensions.gen_random_uuid(),case when guessed=sequence then answer else wrong end);
    end loop;
    return next is(response #>> '{data,efficiency_points}', (7-sequence)::text, 'solve efficiency at guess '||sequence);
    response := public.submit_guess(guest,2,m,1::smallint,extensions.gen_random_uuid(),answer);
    snap := public.match_snapshot(host,2,m)->'data';
    return next is(snap #>> '{standings,players,0,efficiency_points}', (7-sequence)::text, 'canonical efficiency at guess '||sequence);
  end loop;
  -- Ranking prioritizes solved-round count before total efficiency, and efficiency
  -- before exact time. Reuse finalized real player rows for independent fixtures.
  select id into m from public.matches where round_count=5;
  update public.player_rounds p set state='timed_out',accepted_guess_count=0,solve_duration_us=null,
    efficiency_points=0,finished_at=now() from public.rounds rr where p.round_id=rr.id and rr.match_id=m;
  update public.player_rounds p set state='solved',accepted_guess_count=6,solve_duration_us=1900,efficiency_points=1
    from public.rounds rr,public.match_members member where p.round_id=rr.id and p.member_id=member.id and rr.match_id=m and member.seat=1 and rr.round_number<=2;
  update public.player_rounds p set state='solved',accepted_guess_count=1,solve_duration_us=1600,efficiency_points=6
    from public.rounds rr,public.match_members member where p.round_id=rr.id and p.member_id=member.id and rr.match_id=m and member.seat=2 and rr.round_number=1;
  snap := public.match_snapshot('b4000000-0000-0000-0000-000000000001',2,m)->'data';
  return next is(snap #>> '{standings,players,0,placement}', '1', 'solved rounds outrank greater efficiency');
  update public.player_rounds p set state='solved',accepted_guess_count=5,solve_duration_us=99999,efficiency_points=2
    from public.rounds rr,public.match_members member where p.round_id=rr.id and p.member_id=member.id and rr.match_id=m and member.seat=2 and rr.round_number=2;
  snap := public.match_snapshot('b4000000-0000-0000-0000-000000000001',2,m)->'data';
  return next is(snap #>> '{standings,players,1,placement}', '1', 'efficiency outranks shorter exact time with equal solves');

  -- Exhaustion must be an atomic failed Start, not a reset/reuse of an answer.
  delete from private.user_rate_limits;
  m := (public.create_match(host,2,null,extensions.gen_random_uuid(),3::smallint) #>> '{data,match_id}')::uuid;
  perform public.join_match(guest,2,(select join_code from public.matches where id=m));
  perform public.start_match(host,2,m,1::smallint);
  select id into r from public.rounds where match_id=m and round_number=1;
  select s.answer into answer from private.round_secrets s where round_id=r;
  update public.player_rounds set state='forfeited',finished_at=now(),efficiency_points=0 where round_id=r;
  perform private.finalize_round(r);
  create temporary table saved_words as select * from private.words;
  update private.words set is_answer=false where word<>answer;
  before := public.match_snapshot(host,2,m);
  response := public.start_match(host,2,m,2::smallint);
  return next is(response #>> '{error,code}', 'internal_error', 'answer exhaustion fails closed');
  return next is(public.match_snapshot(host,2,m), before, 'exhaustion leaves canonical snapshot/revision unchanged');
  return next is((select count(*) from private.round_secrets s join public.rounds rr on rr.id=s.round_id where rr.match_id=m), 1::bigint, 'exhaustion creates no secret');
  update private.words w set is_answer=s.is_answer from saved_words s where s.word=w.word;
  return next ok(public.start_match(host,2,m,2::smallint) ? 'data', 'restored pool supports retry of same target');
  return next is(public.start_match(host,2,m,3::smallint) #>> '{error,code}', 'round_not_active', 'skipping active target denied');
end $$;
select * from pg_temp.scoring();

select * from finish();
rollback;
