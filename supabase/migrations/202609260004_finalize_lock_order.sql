begin;

create or replace function private.finalize_expired_rounds()
returns integer
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  v_round_id uuid;
  v_count integer := 0;
begin
  for v_round_id in
    select round.id
    from public.rounds as round
    where round.state = 'countdown'
      and round.ends_at <= transaction_timestamp()
    order by round.match_id, round.id
  loop
    if private.finalize_round(v_round_id) then
      v_count := v_count + 1;
    end if;
  end loop;
  return v_count;
end;
$$;

commit;
