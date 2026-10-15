import json, os, shutil, subprocess, time, uuid

assert os.environ.get('GRIDRACE_DISPOSABLE_BETA') == '1', 'explicit disposable lease required'
port = int(os.environ['GRIDRACE_BETA_LOCAL_DB_PORT'])
assert port > 1024
psql = shutil.which('psql') or '/opt/homebrew/opt/libpq/bin/psql'
env = {**os.environ, 'PGPASSWORD': 'postgres'}
base = [psql, '-X', '-At', '-h', '127.0.0.1', '-p', str(port), '-U', 'postgres', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1']
results = []
actors = []
def sql(query):
    p = subprocess.run(base + ['-c', query], env=env, capture_output=True, text=True, timeout=15)
    if p.returncode: raise RuntimeError(p.stderr)
    return p.stdout.strip()
def value(query): return sql(query).splitlines()[-1]
def command(actor, match, action, epoch, generation=1, request=None):
    return f"public.rematch_command('{actor}',3,'{request or uuid.uuid4()}','{match}',{generation},'{action}',{epoch})"
def epoch(actor): return int(value(f"select epoch from private.participation_cursors where actor_user_id='{actor}'"))
def match_pair(completed=True):
    a,b = str(uuid.uuid4()),str(uuid.uuid4()); actors.extend([a,b])
    sql(f"insert into auth.users(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,created_at,updated_at) select x::uuid,'00000000-0000-0000-0000-000000000000','authenticated','authenticated',x||'@example.test','unused',now(),now(),now() from unnest(array['{a}','{b}'])x;")
    m=value(f"select public.create_match('{a}',3,null,'{uuid.uuid4()}',1::smallint)#>>'{{data,match_id}}'")
    if completed:
        sql(f"select public.join_match('{b}',3,(select join_code from public.matches where id='{m}'),null,'{uuid.uuid4()}',null); select public.start_match('{a}',3,'{m}',1::smallint); update public.rounds set starts_at=now()-interval '4 minutes',ends_at=now()-interval '1 minute' where match_id='{m}'; select private.finalize_round(id) from public.rounds where match_id='{m}';")
    return a,b,m

def begin_first(expression):
    p=subprocess.Popen(base,env=env,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,bufsize=1)
    p.stdin.write(f"set statement_timeout='8s'; begin; select {expression}; select 'BARRIER';\n");p.stdin.flush()
    lines=[]
    while True:
        line=p.stdout.readline().strip()
        if line=='BARRIER': break
        if not line and p.poll() is not None: raise RuntimeError(p.stderr.read())
        lines.append(line)
    return p,lines

def release(p):
    p.stdin.write('commit;\n\\q\n');p.stdin.flush()
    _,err=p.communicate(timeout=10)
    if p.returncode: raise RuntimeError(err)

def waiter(expression,name):
    return subprocess.Popen(base+['-c',f"set application_name='{name}'; set statement_timeout='8s'; select {expression};"],env=env,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)

def blocked(name):
    deadline=time.monotonic()+5
    while time.monotonic()<deadline:
        if value(f"select exists(select 1 from pg_stat_activity where application_name='{name}' and wait_event_type='Lock')")=='t': return
        time.sleep(.02)
    raise AssertionError('second connection did not wait at lock barrier')

def outcome(p,allow_retry=False):
    out,err=p.communicate(timeout=12)
    if p.returncode:
        if allow_retry and 'snapshot_roster_changed' in err: return {'retry':'snapshot_roster_changed'}
        raise RuntimeError(err)
    return json.loads(out.strip().splitlines()[-1])

def ordered(name,first,second):
    p,lines=begin_first(first)
    q=waiter(second,'beta_'+name);blocked('beta_'+name);release(p)
    return json.loads(next(x for x in lines if x.startswith('{'))),outcome(q)

try:
    sql('update private.live_feature_configuration set allow_new_rematches=true;')
    a,b,m=match_pair();ea,eb=epoch(a),epoch(b)
    x,y=ordered('simultaneous_offers',command(a,m,'offer',ea),command(b,m,'offer',eb))
    assert x['data']['state']=='offered' and y['data']['state']=='accepted'
    assert value(f"select count(*) from private.rematch_successors where predecessor_match_id='{m}'")=='1'
    results.append('simultaneous offers: one successor')
    for first_action in ('cancel','accept'):
        a,b,m=match_pair();sql('select '+command(a,m,'offer',epoch(a)));ea,eb=epoch(a),epoch(b)
        cancel=command(a,m,'cancel',ea);accept=command(b,m,'accept',eb)
        x,y=ordered('accept_'+first_action,cancel if first_action=='cancel' else accept,accept if first_action=='cancel' else cancel)
        assert x['data']['state']==('closed' if first_action=='cancel' else 'accepted')
        assert (y.get('error',{}).get('code')=='rematch_unavailable') if first_action=='cancel' else y['data']['state']=='accepted'
        results.append('accept/cancel: '+first_action+' commits first')
    for first_action in ('resume','accept'):
        a,b,m=match_pair();old=value(f"select public.create_match('{b}',3,null,'{uuid.uuid4()}',1::smallint)#>>'{{data,match_id}}'")
        sql('select '+command(a,m,'offer',epoch(a)));ea,eb=epoch(a),epoch(b)
        resume=f"public.join_match('{b}',3,(select join_code from public.matches where id='{old}'),null,'{uuid.uuid4()}','{old}')"
        accept=command(b,m,'accept',eb)
        sql(f"select public.join_match('{b}',3,(select join_code from public.matches where id='{m}'),null,'{uuid.uuid4()}','{m}');")
        sql(f"select public.match_snapshot('{a}',3,'{m}'); select "+command(a,m,'offer',epoch(a),2))
        accept=command(b,m,'accept',epoch(b),2)
        x,y=ordered('accept_'+first_action,resume if first_action=='resume' else accept,accept if first_action=='resume' else resume)
        if first_action=='resume': assert y['error']['code']=='participation_changed'
        else: assert x['data']['state']=='accepted' and 'data' in y
        results.append('accept/pinned Resume: '+first_action+' commits first')
    for first_action in ('delete','accept'):
        a,b,m=match_pair();sql('select '+command(a,m,'offer',epoch(a)));eb=epoch(b)
        delete=f"public.delete_account('{a}',3)"; accept=command(b,m,'accept',eb)
        x,y=ordered('accept_'+first_action,delete if first_action=='delete' else accept,accept if first_action=='delete' else delete)
        if first_action=='delete': assert y['error']['code']=='rematch_unavailable'
        else:
            assert x['data']['state']=='accepted' and 'data' in y
            assert value(f"select state from private.rematch_contexts where predecessor_match_id='{m}'")=='accepted'
            assert value(f"select successor_match_id is not null from private.rematch_contexts where predecessor_match_id='{m}'")=='t'
        results.append('accept/deletion: '+first_action+' commits first')
    a,b,m=match_pair();ea=epoch(a)
    sql(f"select public.match_snapshot('{a}',3,'{m}'); update private.rematch_contexts set deadline=clock_timestamp()+interval '600 milliseconds' where predecessor_match_id='{m}'")
    p,_=begin_first(f"pg_advisory_xact_lock(hashtextextended('{a}',1))")
    q=waiter(command(a,m,'offer',ea),'beta_expiry');blocked('beta_expiry');time.sleep(.7);release(p)
    assert outcome(q)['error']['code']=='rematch_expired';results.append('expiry after actor lock wait')
    a,b,m=match_pair(False)
    p,_=begin_first(f"pg_advisory_xact_lock(hashtextextended('{a}',1))")
    q=waiter(f"public.match_snapshot('{a}',3,'{m}')",'beta_roster');blocked('beta_roster')
    sql(f"select public.join_match('{b}',3,(select join_code from public.matches where id='{m}'),null,'{uuid.uuid4()}',null)")
    release(p);assert outcome(q,True)=={'retry':'snapshot_roster_changed'}
    assert json.loads(value(f"select public.match_snapshot('{a}',3,'{m}')"))['data']['version']==3
    results.append('roster discovery drift aborts whole snapshot; fresh read converges')
    a,b,m=match_pair();ea=epoch(a)
    sql(f"select public.match_snapshot('{a}',3,'{m}'); update private.rematch_contexts set deadline=clock_timestamp()+interval '600 milliseconds' where predecessor_match_id='{m}'")
    p,_=begin_first("(select word from private.words where is_active and is_answer order by word limit 1 for update)")
    q=waiter(command(a,m,'offer',ea),'beta_pool_expiry');blocked('beta_pool_expiry');time.sleep(.7);release(p)
    assert outcome(q)['error']['code']=='rematch_expired';results.append('expiry after answer pool lock wait')
    a,b,m=match_pair()
    gate=value(f"select x from unnest(array['{a}'::uuid,'{b}'::uuid])x order by hashtextextended(x::text,1) limit 1")
    departing=b if gate==a else a
    p,_=begin_first(f"pg_advisory_xact_lock(hashtextextended('{gate}',1))")
    q=waiter(f"public.match_snapshot('{gate}',3,'{m}')",'beta_delete_roster');blocked('beta_delete_roster')
    sql(f"select public.delete_account('{departing}',3)");release(p)
    assert outcome(q,True)=={'retry':'snapshot_roster_changed'}
    assert json.loads(value(f"select public.match_snapshot('{gate}',3,'{m}')"))['data']['rematch']['state']=='unavailable'
    results.append('snapshot deletion drift restarts and canonical read normalizes')
    print(json.dumps({'passed':results,'connections':'independent psql sessions with observed lock barriers','port':port},indent=2))
finally:
    for a in actors:
        sql(f"select public.delete_account('{a}',3); delete from auth.users where id='{a}';")
    sql('update private.live_feature_configuration set allow_new_rematches=false;')
