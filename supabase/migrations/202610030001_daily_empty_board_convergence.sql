-- A started local Daily attempt owns its mode over an empty cloud board.
-- Forward replacement preserves terminal precedence, identity, locks and ACLs.

create or replace function public.sync_daily_progress(
  p_puzzle_id text,
  p_puzzle_number integer,
  p_puzzle_day integer,
  p_word_pack_id text,
  p_schedule_version integer,
  p_hard_mode_enabled boolean,
  p_guesses jsonb,
  p_expected_revision bigint default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_guesses jsonb;
  v_progress public.daily_progress%rowtype;
  v_result public.daily_imported_results%rowtype;
  v_same_identity boolean;
begin
  if v_user_id is null then
    return private.daily_sync_error('not_authenticated');
  end if;

  if private.valid_daily_identity(
      p_puzzle_id, p_puzzle_number, p_puzzle_day, p_word_pack_id, p_schedule_version
    ) is not true
    or p_hard_mode_enabled is null
    or private.valid_daily_guesses(p_guesses, 5, false) is not true
    or (p_expected_revision is not null and p_expected_revision < 1)
  then
    return private.daily_sync_error('invalid_daily_payload');
  end if;

  v_guesses := private.normalize_daily_guesses(p_guesses);
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(v_user_id::text || ':' || p_puzzle_id, 0)
  );

  select * into v_result
  from public.daily_imported_results
  where user_id = v_user_id and puzzle_id = p_puzzle_id;

  if found then
    delete from public.daily_progress
    where user_id = v_user_id and puzzle_id = p_puzzle_id;
    return jsonb_build_object('status', 'completed', 'result', to_jsonb(v_result));
  end if;

  select * into v_progress
  from public.daily_progress
  where user_id = v_user_id and puzzle_id = p_puzzle_id
  for update;

  if not found then
    insert into public.daily_progress (
      user_id, puzzle_id, puzzle_number, puzzle_day, word_pack_id,
      schedule_version, hard_mode_enabled, guesses
    ) values (
      v_user_id, p_puzzle_id, p_puzzle_number, p_puzzle_day, p_word_pack_id,
      p_schedule_version, p_hard_mode_enabled, v_guesses
    )
    returning * into v_progress;
    return jsonb_build_object('status', 'inserted', 'progress', to_jsonb(v_progress));
  end if;

  v_same_identity := v_progress.puzzle_number = p_puzzle_number
    and v_progress.puzzle_day = p_puzzle_day
    and v_progress.word_pack_id = p_word_pack_id
    and v_progress.schedule_version = p_schedule_version;

  if not v_same_identity
    or (v_progress.hard_mode_enabled <> p_hard_mode_enabled
        and jsonb_array_length(v_progress.guesses) > 0)
  then
    return jsonb_build_object('status', 'conflict', 'progress', to_jsonb(v_progress));
  end if;

  -- Hard Mode is attempt configuration. An unstarted stored board yields to
  -- the incoming selection/started attempt, but only at the expected revision.
  if v_progress.hard_mode_enabled <> p_hard_mode_enabled then
    if p_expected_revision is not null and p_expected_revision <> v_progress.revision then
      return jsonb_build_object('status', 'conflict', 'progress', to_jsonb(v_progress));
    end if;
    update public.daily_progress
    set hard_mode_enabled = p_hard_mode_enabled,
        guesses = v_guesses,
        revision = revision + 1,
        server_updated_at = transaction_timestamp()
    where user_id = v_user_id and puzzle_id = p_puzzle_id
    returning * into v_progress;
    return jsonb_build_object('status', 'advanced', 'progress', to_jsonb(v_progress));
  end if;

  if v_guesses = v_progress.guesses then
    return jsonb_build_object('status', 'exact', 'progress', to_jsonb(v_progress));
  end if;

  if jsonb_array_length(v_guesses) < jsonb_array_length(v_progress.guesses)
    and private.daily_guesses_are_prefix(v_guesses, v_progress.guesses)
  then
    return jsonb_build_object('status', 'server_ahead', 'progress', to_jsonb(v_progress));
  end if;

  if jsonb_array_length(v_progress.guesses) < jsonb_array_length(v_guesses)
    and private.daily_guesses_are_prefix(v_progress.guesses, v_guesses)
  then
    if p_expected_revision is not null and p_expected_revision <> v_progress.revision then
      return jsonb_build_object('status', 'conflict', 'progress', to_jsonb(v_progress));
    end if;
    update public.daily_progress
    set guesses = v_guesses,
        revision = revision + 1,
        server_updated_at = transaction_timestamp()
    where user_id = v_user_id and puzzle_id = p_puzzle_id
    returning * into v_progress;
    return jsonb_build_object('status', 'advanced', 'progress', to_jsonb(v_progress));
  end if;

  return jsonb_build_object('status', 'conflict', 'progress', to_jsonb(v_progress));
end;
$$;
