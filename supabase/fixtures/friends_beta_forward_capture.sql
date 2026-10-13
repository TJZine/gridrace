-- Capture only synthetic retained fixtures in the controller-owned disposable database.
select jsonb_build_object('matches',(select jsonb_agg(to_jsonb(t) order by id) from public.matches t),
 'members',(select jsonb_agg(to_jsonb(t) order by id) from public.match_members t),
 'rounds',(select jsonb_agg(to_jsonb(t) order by id) from public.rounds t),
 'players',(select jsonb_agg(to_jsonb(t) order by round_id,member_id) from public.player_rounds t),
 'secrets',(select jsonb_agg(to_jsonb(t) order by round_id) from private.round_secrets t),
 'guesses',(select jsonb_agg(to_jsonb(t) order by id) from public.guesses t),
 'create_receipts',(select jsonb_agg(to_jsonb(t) order by actor_user_id,request_id) from private.create_requests t),
 'guess_receipts',(select jsonb_agg(to_jsonb(t) order by actor_user_id,request_id) from private.guess_requests t),
 'columns',(select jsonb_agg(to_jsonb(t) order by table_name,column_name,grantee,privilege_type) from information_schema.column_privileges t where grantee in ('anon','authenticated') and table_name in ('matches','rounds','match_members','player_rounds','guesses')));
