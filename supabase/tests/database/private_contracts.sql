begin;
create extension if not exists pgtap with schema extensions;
set local search_path=public,extensions;
select no_plan();
create function pg_temp.private_contracts() returns setof text language plpgsql as $$
declare signature text; function_id oid;
begin
  foreach signature in array array[
    'private.normalize_rematch_with_locked_participation(uuid,timestamptz)',
    'private.rematch_projection_with_locked_participation(uuid,uuid,timestamptz)',
    'private.rematch_command_result_with_locked_participation(uuid,uuid,integer,text,bigint)'
  ] loop
    function_id:=to_regprocedure(signature);
    return next ok(function_id is not null,signature||': available to locked callers');
    if function_id is null then continue; end if;
    return next ok(not has_function_privilege('anon',function_id,'execute'),signature||': anonymous execution denied');
    return next ok(not has_function_privilege('authenticated',function_id,'execute'),signature||': authenticated execution denied');
    return next ok(has_function_privilege('service_role',function_id,'execute'),signature||': service execution retained');
    return next ok((select not prosecdef and provolatile='v' and proconfig=array['search_path=""']::text[]
      from pg_catalog.pg_proc where oid=function_id),signature||': invoker authority and empty search path');
  end loop;
end $$;
select * from pg_temp.private_contracts();
select ok(to_regprocedure('private.normalize_rematch(uuid,timestamptz)') is null,'unlocked normalizer entry removed');
select ok(to_regprocedure('private.rematch_projection(uuid,uuid,timestamptz)') is null,'unlocked projection entry removed');
select ok(to_regprocedure('private.rematch_command_result(uuid,uuid,integer,text,bigint)') is null,'unlocked command-result entry removed');
select * from finish();
rollback;
