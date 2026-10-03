import {
  createClient,
  type RealtimeChannel,
  type Session,
  type SupabaseClient,
} from "@supabase/supabase-js";

type Json = Record<string, unknown>;

assert(
  required("GRIDRACE_LOCAL_INTEGRATION") === "1",
  "local integration opt-in required",
);
const apiUrl = localApiUrl(required("API_URL"));
const database = localDatabase(required("DB_URL"));
const anonKey = required("ANON_KEY");
const serviceKey = required("SERVICE_ROLE_KEY");
const clientOptions = {
  auth: {
    autoRefreshToken: false,
    detectSessionInUrl: false,
    persistSession: false,
  },
};
const admin = createClient(apiUrl, serviceKey, clientOptions);
const createdUsers = new Set<string>();
const createdMatches = new Set<string>();
const deletionHashes = new Set<string>();
const edgeMetrics: Array<
  Pick<EdgeResult, "bytes" | "elapsedMs"> & { name: string }
> = [];
const safeMatchColumns =
  "id,join_code,creator_member_id,mode,round_count,current_round,status,created_at,started_at,completed_at,expires_at,minimum_client_build,revision";

interface TestUser {
  id: string;
  session: Session;
  client: SupabaseClient;
}

interface EdgeResult {
  status: number;
  body: Json;
  bytes: number;
  elapsedMs: number;
}

interface LocalDatabase {
  args: string[];
  password: string;
}

try {
  await scenario("gateway authentication and create retry", async () => {
    const host = await createUser("create-host");
    const requestId = crypto.randomUUID();
    const first = await edge(host.session, "create-match", {
      client_build: 1,
      request_id: requestId,
    });
    const retry = await edge(host.session, "create-match", {
      client_build: 1,
      request_id: requestId,
    });
    assert(first.status === 200 && retry.status === 200, "create retry status");
    assert(matchId(first) === matchId(retry), "create retry identity");
    assert(first.bytes < 512 && retry.bytes < 512, "create response size");

    const conflict = await edge(host.session, "create-match", {
      client_build: 2,
      request_id: requestId,
      round_count: 1,
    });
    assertError(conflict, 409, "request_conflict");

    const anonymous = await edge(null, "create-match", {
      client_build: 1,
      request_id: crypto.randomUUID(),
    });
    assert(anonymous.status === 401, "anonymous create denied");
    assertError(
      await edge(host.session, "create-match", {
        client_build: 0,
        request_id: crypto.randomUUID(),
      }),
      426,
      "client_update_required",
    );
    assertError(
      await edge(host.session, "create-match", {
        client_build: 1,
        request_id: crypto.randomUUID(),
        unexpected: true,
      }),
      400,
      "internal_error",
    );
    assertError(
      await rawEdge(host.session, "create-match", "{"),
      400,
      "internal_error",
    );
    assertError(
      await edge(host.session, "match-snapshot", {
        client_build: 1,
        match_id: "not-a-uuid",
      }),
      400,
      "internal_error",
    );
    assertError(
      await edge(host.session, "match-snapshot", {
        client_build: 1,
        match_id: crypto.randomUUID(),
      }),
      403,
      "not_a_match_member",
    );
  });

  await scenario("RLS secrecy and realtime refresh signal", async () => {
    const host = await createUser("race-host");
    const guest = await createUser("race-guest");
    const outsider = await createUser("race-outsider");
    const created = await edge(host.session, "create-match", {
      client_build: 1,
      request_id: crypto.randomUUID(),
    });
    const matchIdValue = matchId(created);
    const lobby = data(
      await edge(host.session, "match-snapshot", {
        client_build: 1,
        match_id: matchIdValue,
      }),
    );
    const joinCode = nestedString(lobby, "match", "join_code");

    const signal = await subscribeToMatchSignal(host, matchIdValue);
    const joined = await edge(guest.session, "join-match", {
      client_build: 1,
      join_code: joinCode,
    });
    assert(joined.status === 200, "guest join");

    const hostRows = await host.client.from("matches").select(safeMatchColumns)
      .eq(
        "id",
        matchIdValue,
      );
    assert(
      hostRows.error === null && hostRows.data?.length === 1,
      "member match read",
    );
    const timingRead = await host.client.from("matches").select("updated_at")
      .eq(
        "id",
        matchIdValue,
      );
    assert(timingRead.error !== null, "direct timing secrecy");
    const outsiderRows = await outsider.client.from("matches").select(
      safeMatchColumns,
    ).eq("id", matchIdValue);
    assert(
      outsiderRows.error === null && outsiderRows.data?.length === 0,
      "unrelated match denial",
    );
    const unauthenticated = createClient(apiUrl, anonKey, clientOptions);
    const anonRows = await unauthenticated.from("matches").select(
      safeMatchColumns,
    ).eq("id", matchIdValue);
    assert(
      anonRows.error !== null || anonRows.data?.length === 0,
      "anonymous match denial",
    );
    const directWrite = await host.client.from("matches").update({
      status: "completed",
    }).eq("id", matchIdValue);
    assert(directWrite.error !== null, "direct match mutation denied");
    const privateRead = await host.client.schema("private").from("words")
      .select("word").limit(1);
    assert(privateRead.error !== null, "private schema denied");
    const directRpc = await host.client.rpc("create_match", {
      p_user_id: host.id,
      p_client_build: 1,
      p_ip_hash: null,
      p_request_id: crypto.randomUUID(),
    });
    assert(directRpc.error !== null, "service RPC denied");

    const before = data(
      await edge(host.session, "match-snapshot", {
        client_build: 1,
        match_id: matchIdValue,
      }),
    );
    assert(
      nested(before, "round", "answer") === null,
      "pre-reveal answer hidden",
    );
    assertOpponentBoardHidden(before);

    const started = await edge(host.session, "start-match", {
      client_build: 1,
      match_id: matchIdValue,
    });
    assert(started.status === 200, "creator start");
    const payload = await signal.next;
    await signal.close();
    const allowed = new Set([
      "id",
      "join_code",
      "creator_member_id",
      "mode",
      "round_count",
      "current_round",
      "status",
      "created_at",
      "started_at",
      "completed_at",
      "expires_at",
      "minimum_client_build",
      "revision",
    ]);
    assert(
      Object.keys(payload).every((key) => allowed.has(key)),
      "realtime column projection",
    );
    assert(
      !("updated_at" in payload) && !("answer" in payload),
      "realtime secrecy",
    );
    await delay(3200);
    const playing = data(
      await edge(host.session, "match-snapshot", {
        client_build: 1,
        match_id: matchIdValue,
      }),
    );
    assertOpponentBoardHidden(playing);
    const answer = await sqlScalar(
      `select secret.answer from private.round_secrets secret join public.rounds round on round.id = secret.round_id where round.match_id = '${
        uuid(matchIdValue)
      }'`,
    );
    const otherWord = await sqlScalar(
      `select word from private.words where word <> '${
        sqlLiteral(answer)
      }' order by word limit 1`,
    );
    const requestId = crypto.randomUUID();
    const [sameA, sameB] = await Promise.all([
      edge(
        host.session,
        "submit-guess",
        guessBody(matchIdValue, requestId, otherWord),
      ),
      edge(
        host.session,
        "submit-guess",
        guessBody(matchIdValue, requestId, otherWord),
      ),
    ]);
    assert(
      sameA.status === 200 && sameB.status === 200,
      "concurrent identical submit",
    );
    assert(
      JSON.stringify(sameA.body) === JSON.stringify(sameB.body),
      "identical receipt response",
    );
    const oneGuess = await sqlScalar(
      `select count(*) from public.guesses guess join public.rounds round on round.id = guess.round_id where round.match_id = '${
        uuid(matchIdValue)
      }' and guess.request_id = '${uuid(requestId)}'`,
    );
    assert(oneGuess === "1", "one canonical guess");

    const guestSolve = await edge(
      guest.session,
      "submit-guess",
      guessBody(matchIdValue, crypto.randomUUID(), answer),
    );
    const hostSolve = await edge(
      host.session,
      "submit-guess",
      guessBody(matchIdValue, crypto.randomUUID(), answer),
    );
    assert(
      guestSolve.status === 200 && hostSolve.status === 200,
      "authoritative solves",
    );
    const revealed = data(
      await edge(guest.session, "match-snapshot", {
        client_build: 1,
        match_id: matchIdValue,
      }),
    );
    assert(
      nestedString(revealed, "round", "answer").length === 5,
      "answer revealed",
    );
    assertAllBoardsVisible(revealed);

    const deleted = await edge(host.session, "delete-account", {
      client_build: 1,
    });
    assert(deleted.status === 200, "completed player deletion");
    createdUsers.delete(host.id);
    const replay = await edge(host.session, "delete-account", {
      client_build: 1,
    });
    assert(replay.status === 200, "lost deletion response replay");
    const survivor = data(
      await edge(guest.session, "match-snapshot", {
        client_build: 1,
        match_id: matchIdValue,
      }),
    );
    assertDeletedMemberIdentity(survivor);
    const stale = await edge(host.session, "match-snapshot", {
      client_build: 1,
      match_id: matchIdValue,
    });
    assert(stale.status === 401, "deleted credential denied");
    assert(
      (await edge(guest.session, "delete-account", { client_build: 1 }))
        .status === 200,
      "survivor deletion",
    );
    createdUsers.delete(guest.id);
  });

  await scenario("competing joins converge", async () => {
    const host = await createUser("join-host");
    const first = await createUser("join-first");
    const second = await createUser("join-second");
    const created = await edge(host.session, "create-match", {
      client_build: 1,
      request_id: crypto.randomUUID(),
    });
    const matchIdValue = matchId(created);
    const snapshot = data(
      await edge(host.session, "match-snapshot", {
        client_build: 1,
        match_id: matchIdValue,
      }),
    );
    const code = nestedString(snapshot, "match", "join_code");
    const results = await Promise.all([
      edge(first.session, "join-match", { client_build: 1, join_code: code }),
      edge(second.session, "join-match", { client_build: 1, join_code: code }),
    ]);
    assert(
      results.filter((result) => result.status === 200).length === 1,
      "one join winner",
    );
    assert(
      results.filter((result) => result.status === 409).length === 1,
      "one join loser",
    );
    const members = await sqlScalar(
      `select count(*) from public.match_members where match_id = '${
        uuid(matchIdValue)
      }'`,
    );
    assert(members === "2", "two canonical seats");
  });

  await scenario("submission receipt concurrency domains", async () => {
    const host = await createUser("receipt-host");
    const firstGuest = await createUser("receipt-first-guest");
    const secondGuest = await createUser("receipt-second-guest");
    const firstMatch = await createPlayingMatch(host, firstGuest);
    const secondMatch = await createPlayingMatch(host, secondGuest);
    const answer = await matchAnswer(firstMatch);
    const wrong = await anotherWord(answer);
    const otherWrong = await anotherWord(answer, 1);

    const conflictingId = crypto.randomUUID();
    const [conflictA, conflictB] = await Promise.all([
      edge(
        host.session,
        "submit-guess",
        guessBody(firstMatch, conflictingId, wrong),
      ),
      edge(
        host.session,
        "submit-guess",
        guessBody(firstMatch, conflictingId, otherWrong),
      ),
    ]);
    assert(
      [conflictA, conflictB].filter((result) => result.status === 200)
        .length === 1,
      "one conflicting receipt winner",
    );
    assert(
      [conflictA, conflictB].filter((result) => result.status === 409)
        .length === 1,
      "one conflicting receipt rejection",
    );

    const [differentA, differentB] = await Promise.all([
      edge(
        host.session,
        "submit-guess",
        guessBody(firstMatch, crypto.randomUUID(), wrong),
      ),
      edge(
        host.session,
        "submit-guess",
        guessBody(firstMatch, crypto.randomUUID(), wrong),
      ),
    ]);
    assert(
      differentA.status === 200 && differentB.status === 200,
      "different receipt submissions complete",
    );

    const crossMatchId = crypto.randomUUID();
    const crossMatch = await Promise.all([
      edge(
        host.session,
        "submit-guess",
        guessBody(firstMatch, crossMatchId, wrong),
      ),
      edge(
        host.session,
        "submit-guess",
        guessBody(secondMatch, crossMatchId, wrong),
      ),
    ]);
    assert(
      crossMatch.filter((result) => result.status === 200).length === 1,
      "one cross-match receipt winner",
    );
    const crossMatchLoser = crossMatch.find((result) => result.status !== 200);
    assert(crossMatchLoser !== undefined, "cross-match receipt loser");
    assertError(crossMatchLoser, 409, "request_conflict");
    assert(
      await sqlScalar(
        `select count(*) from public.guesses where request_id = '${
          uuid(crossMatchId)
        }'`,
      ) === "1",
      "one cross-match canonical guess",
    );
  });

  await scenario("finalizer and sixth guess converge", async () => {
    const host = await createUser("finalize-host");
    const guest = await createUser("finalize-guest");
    const matchIdValue = await createPlayingMatch(host, guest);
    const answer = await matchAnswer(matchIdValue);
    const wrong = await anotherWord(answer);
    assert(
      (await edge(
        guest.session,
        "submit-guess",
        guessBody(matchIdValue, crypto.randomUUID(), answer),
      )).status === 200,
      "finalizer peer solved",
    );
    for (let attempt = 0; attempt < 5; attempt += 1) {
      assert(
        (await edge(
          host.session,
          "submit-guess",
          guessBody(matchIdValue, crypto.randomUUID(), wrong),
        )).status === 200,
        "pre-sixth guess accepted",
      );
    }
    const roundId = await matchRoundId(matchIdValue);
    const sixthRequestId = crypto.randomUUID();
    const [sixth, finalized] = await Promise.all([
      edge(
        host.session,
        "submit-guess",
        guessBody(matchIdValue, sixthRequestId, wrong),
      ),
      sql(`select private.finalize_round('${uuid(roundId)}')`),
    ]);
    assert(sixth.status === 200, "sixth guess accepted");
    const failedReceipt = data(sixth);
    assert(
      failedReceipt.player_state === "failed",
      "sixth receipt failed state",
    );
    assert(failedReceipt.accepted_guess_count === 6, "sixth receipt count");
    assert(
      failedReceipt.solve_duration_ms === null,
      "failed receipt duration null",
    );
    assert(
      failedReceipt.efficiency_points === null,
      "failed receipt efficiency null",
    );
    assert(["t", "f"].includes(finalized), "concurrent finalizer bounded");
    assert(
      await sqlScalar(
        `select count(*) from public.rounds where id = '${
          uuid(roundId)
        }' and state = 'revealed'`,
      ) === "1",
      "one revealed round",
    );
    assert(
      await sqlScalar(
        `select count(*) from public.guesses where round_id = '${
          uuid(roundId)
        }'`,
      ) === "7",
      "canonical guess total",
    );
    assert(
      await sqlScalar(
        `select efficiency_points from public.player_rounds player join public.match_members member on member.id = player.member_id where player.round_id = '${
          uuid(roundId)
        }' and member.auth_user_id = '${uuid(host.id)}'`,
      ) === "0",
      "failed player storage efficiency zero",
    );
    assert(
      await sqlScalar(
        `select response_data ->> 'efficiency_points' from private.guess_requests where actor_user_id = '${
          uuid(host.id)
        }' and request_id = '${uuid(sixthRequestId)}'`,
      ) === "",
      "stored failed receipt efficiency null",
    );
    const rateBeforeReplay = await sqlScalar(
      `select attempt_count from private.user_rate_limits where actor_user_id = '${
        uuid(host.id)
      }' and action = 'submit_guess'`,
    );
    const replay = await edge(
      host.session,
      "submit-guess",
      guessBody(matchIdValue, sixthRequestId, wrong),
    );
    assert(replay.status === 200, "failed receipt replay accepted");
    assert(
      JSON.stringify(replay.body) === JSON.stringify(sixth.body),
      "failed receipt replay identical",
    );
    assert(
      await sqlScalar(
        `select count(*) from public.guesses where round_id = '${
          uuid(roundId)
        }' and request_id = '${uuid(sixthRequestId)}'`,
      ) === "1",
      "failed receipt replay has one guess",
    );
    assert(
      await sqlScalar(
        `select attempt_count from private.user_rate_limits where actor_user_id = '${
          uuid(host.id)
        }' and action = 'submit_guess'`,
      ) === rateBeforeReplay,
      "failed receipt replay leaves rate counter unchanged",
    );
    const failedSnapshot = data(
      await edge(host.session, "match-snapshot", {
        client_build: 1,
        match_id: matchIdValue,
      }),
    );
    const selfMember = array(failedSnapshot.members).filter(isJson).find((
      member,
    ) => member.is_self === true);
    assert(
      isJson(selfMember) && typeof selfMember.id === "string",
      "failed snapshot self member",
    );
    const selfPlayer = array(nested(failedSnapshot, "round", "players"))
      .filter(isJson)
      .find((player) => player.member_id === selfMember.id);
    assert(
      isJson(selfPlayer) && selfPlayer.state === "failed" &&
        selfPlayer.efficiency_points === 0,
      "failed snapshot efficiency zero",
    );
  });

  await scenario("deadline lock wait uses transaction ordering", async () => {
    const host = await createUser("deadline-host");
    const guest = await createUser("deadline-guest");
    const matchIdValue = await createPlayingMatch(host, guest);
    const wrong = await anotherWord(await matchAnswer(matchIdValue));
    await sql(
      `update public.rounds set ends_at = transaction_timestamp() + interval '700 milliseconds', starts_at = transaction_timestamp() + interval '700 milliseconds' - interval '180 seconds' where match_id = '${
        uuid(matchIdValue)
      }'`,
    );
    const held = holdMatchLock(matchIdValue, 1);
    await delay(150);
    const waited = await edge(
      host.session,
      "submit-guess",
      guessBody(matchIdValue, crypto.randomUUID(), wrong),
    );
    await held;
    assert(
      waited.status === 200,
      "pre-deadline transaction survives lock wait",
    );
    assert(waited.elapsedMs >= 700, "submit actually waited on match lock");

    const equalityHost = await createUser("equality-host");
    const equalityGuest = await createUser("equality-guest");
    const equalityMatch = await createPlayingMatch(equalityHost, equalityGuest);
    await sql(
      `update public.rounds set ends_at = transaction_timestamp(), starts_at = transaction_timestamp() - interval '180 seconds' where match_id = '${
        uuid(equalityMatch)
      }'`,
    );
    const atDeadline = await edge(
      equalityHost.session,
      "submit-guess",
      guessBody(equalityMatch, crypto.randomUUID(), wrong),
    );
    assertError(atDeadline, 409, "round_already_finished");
  });

  await scenario(
    "scheduled finalization and multi-match deletion share lock order",
    async () => {
      const deleting = await createUser("finalize-delete-member");
      const firstGuest = await createUser("finalize-delete-first-guest");
      const secondGuest = await createUser("finalize-delete-second-guest");
      await sql(
        "select cron.alter_job(job_id := (select jobid from cron.job where jobname = 'gridrace-finalize-rounds'), active := false)",
      );
      try {
        await sql("select private.finalize_expired_rounds()");
        const firstMatchId = await createPlayingMatch(deleting, firstGuest);
        const secondMatchId = await createPlayingMatch(deleting, secondGuest);
        const matchIds = [firstMatchId, secondMatchId].sort();
        const [lowerMatchId, higherMatchId] = matchIds;
        await sql(
          `update public.rounds set starts_at = transaction_timestamp() - interval '181 seconds', ends_at = transaction_timestamp() - interval '1 second' where match_id = '${
            uuid(lowerMatchId)
          }'; update public.rounds set starts_at = transaction_timestamp() - interval '182 seconds', ends_at = transaction_timestamp() - interval '2 seconds' where match_id = '${
            uuid(higherMatchId)
          }'`,
        );
        assert(
          await sqlScalar(
            `select (select ends_at from public.rounds where match_id = '${
              uuid(higherMatchId)
            }') < (select ends_at from public.rounds where match_id = '${
              uuid(lowerMatchId)
            }')`,
          ) === "t",
          "deadline order opposes match ID order",
        );

        const barrierName = `gridrace-fd-barrier-${crypto.randomUUID()}`;
        const finalizerName = `gridrace-fd-finalizer-${crypto.randomUUID()}`;
        const barrier = await holdMatchLockBarrier(lowerMatchId, barrierName);
        let finalizerPromise: Promise<string> | undefined;
        let deletionPromise: Promise<EdgeResult> | undefined;
        try {
          finalizerPromise = sql(
            "select private.finalize_expired_rounds()",
            finalizerName,
          );
          await waitForSqlValue(
            `select count(*) from pg_stat_activity where application_name = '${finalizerName}' and wait_event_type = 'Lock'`,
            "1",
            "scheduled finalizer waits on lower match ID",
          );
          await assertMatchLockAvailable(
            higherMatchId,
            "scheduled finalizer has not locked higher match ID",
          );

          deletionPromise = edge(deleting.session, "delete-account", {
            client_build: 1,
          });
          await waitForSqlValue(
            "select count(*) from pg_stat_activity where pid <> pg_backend_pid() and wait_event_type = 'Lock' and query ilike '%begin_account_deletion%'",
            "1",
            "deletion waits on lower match ID",
          );
          await assertMatchLockAvailable(
            higherMatchId,
            "deletion has not locked higher match ID",
          );
        } finally {
          await barrier.release();
        }

        assert(finalizerPromise !== undefined, "finalizer started");
        assert(deletionPromise !== undefined, "deletion started");
        const [finalized, deleted] = await Promise.all([
          finalizerPromise,
          deletionPromise,
        ]);
        assert(finalized === "2", "scheduled finalizer completes both rounds");
        assert(deleted.status === 200, "multi-match deletion completes");
        createdUsers.delete(deleting.id);

        assert(
          await sqlScalar(
            `select count(*) from public.matches where id in ('${
              uuid(lowerMatchId)
            }', '${uuid(higherMatchId)}') and status = 'completed'`,
          ) === "2",
          "both matches complete canonically",
        );
        assert(
          await sqlScalar(
            `select count(*) from public.rounds where match_id in ('${
              uuid(lowerMatchId)
            }', '${
              uuid(higherMatchId)
            }') and state = 'revealed' and revealed_answer is not null`,
          ) === "2",
          "both rounds reveal canonically",
        );
        for (
          const [guest, matchIdValue] of [
            [firstGuest, firstMatchId],
            [secondGuest, secondMatchId],
          ] as const
        ) {
          const snapshot = data(
            await edge(guest.session, "match-snapshot", {
              client_build: 1,
              match_id: matchIdValue,
            }),
          );
          assert(
            nested(snapshot, "round", "answer") !== null,
            "survivor sees reveal",
          );
          assertDeletedMemberIdentity(snapshot);
        }

        const tokenHash = await sha256(deleting.session.access_token);
        assert(
          (await edge(deleting.session, "delete-account", { client_build: 1 }))
            .status === 200,
          "multi-match deletion receipt replay completes",
        );
        assert(
          (await edge(deleting.session, "match-snapshot", {
            client_build: 1,
            match_id: lowerMatchId,
          })).status === 401,
          "multi-match stale bearer cannot read",
        );
        assert(
          (await edge(deleting.session, "create-match", {
            client_build: 1,
            request_id: crypto.randomUUID(),
          })).status === 401,
          "multi-match stale bearer cannot write",
        );
        assert(
          await sqlScalar(
            `select (select count(*) from auth.users where id = '${
              uuid(deleting.id)
            }') + (select count(*) from public.profiles where id = '${
              uuid(deleting.id)
            }') + (select count(*) from public.match_members where auth_user_id = '${
              uuid(deleting.id)
            }') + (select count(*) from private.user_rate_limits where actor_user_id = '${
              uuid(deleting.id)
            }') + (select count(*) from private.create_requests where actor_user_id = '${
              uuid(deleting.id)
            }') + (select count(*) from private.guess_requests where actor_user_id = '${
              uuid(deleting.id)
            }')`,
          ) === "0",
          "multi-match deletion leaves no live auth-linked state",
        );
        assert(
          await sqlScalar(
            `select count(*) from private.account_deletion_receipts where token_hash = '${tokenHash}' and status = 'completed' and user_id is null and completed_at is not null`,
          ) === "1",
          "multi-match deletion receipt is terminal",
        );
      } finally {
        await sql(
          "select cron.alter_job(job_id := (select jobid from cron.job where jobname = 'gridrace-finalize-rounds'), active := true)",
        );
      }
    },
  );

  await scenario("deletion races preserve canonical state", async () => {
    const startHost = await createUser("delete-start-host");
    const startGuest = await createUser("delete-start-guest");
    const startMatch = await createLobbyWithGuest(startHost, startGuest);
    const [start, startDelete] = await Promise.all([
      edge(startHost.session, "start-match", {
        client_build: 1,
        match_id: startMatch,
      }),
      edge(startGuest.session, "delete-account", { client_build: 1 }),
    ]);
    assert(startDelete.status === 200, "start-race deletion completes");
    createdUsers.delete(startGuest.id);
    assert([200, 409].includes(start.status), "start-race command bounded");

    const joinHost = await createUser("delete-join-host");
    const joinGuest = await createUser("delete-join-guest");
    const replacement = await createUser("delete-join-replacement");
    const joinMatch = await createLobbyWithGuest(joinHost, joinGuest);
    const joinCode = await matchJoinCode(joinHost, joinMatch);
    const [join, joinDelete] = await Promise.all([
      edge(replacement.session, "join-match", {
        client_build: 1,
        join_code: joinCode,
      }),
      edge(joinGuest.session, "delete-account", { client_build: 1 }),
    ]);
    assert(joinDelete.status === 200, "join-race deletion completes");
    createdUsers.delete(joinGuest.id);
    assert([200, 409].includes(join.status), "join-race command bounded");
    assert(
      Number(
        await sqlScalar(
          `select count(*) from public.match_members where match_id = '${
            uuid(joinMatch)
          }'`,
        ),
      ) <= 2,
      "join-race capacity preserved",
    );

    const submitHost = await createUser("delete-submit-host");
    const submitGuest = await createUser("delete-submit-guest");
    const submitMatch = await createPlayingMatch(submitHost, submitGuest);
    const wrong = await anotherWord(await matchAnswer(submitMatch));
    assert(
      (await edge(
        submitGuest.session,
        "submit-guess",
        guessBody(submitMatch, crypto.randomUUID(), wrong),
      )).status === 200,
      "submit-race rate row seeded",
    );
    const held = holdMatchLock(submitMatch, 1);
    await delay(150);
    const submitPromise = edge(
      submitGuest.session,
      "submit-guess",
      guessBody(submitMatch, crypto.randomUUID(), wrong),
    );
    await delay(150);
    const deletePromise = edge(submitGuest.session, "delete-account", {
      client_build: 1,
    });
    const [submit, submitDelete] = await Promise.all([
      submitPromise,
      deletePromise,
    ]);
    await held;
    assert(submitDelete.status === 200, "submit-race deletion completes");
    createdUsers.delete(submitGuest.id);
    assert(
      [200, 401, 409].includes(submit.status),
      "submit-race command bounded",
    );
    assert(
      await sqlScalar(
        `select count(*) from public.match_members where match_id = '${
          uuid(submitMatch)
        }' and auth_user_id is null`,
      ) === "1",
      "submit-race identity removed",
    );
  });

  await scenario("same-account join and deletion serialize", async () => {
    const joinFirstHost = await createUser("join-delete-host");
    const joinFirst = await createUser("join-delete-member");
    const created = await edge(joinFirstHost.session, "create-match", {
      client_build: 1,
      request_id: crypto.randomUUID(),
    });
    const matchIdValue = matchId(created);
    const joinCode = await matchJoinCode(joinFirstHost, matchIdValue);
    const lockName = `gridrace-join-delete-${crypto.randomUUID()}`;
    const held = holdMatchLock(matchIdValue, 5, lockName);
    await waitForSqlValue(
      `select count(*) from pg_stat_activity where application_name = '${lockName}' and state = 'active'`,
      "1",
      "match barrier acquired",
    );

    const joinPromise = edge(joinFirst.session, "join-match", {
      client_build: 1,
      join_code: joinCode,
    });
    await waitForSqlValue(
      `select not pg_try_advisory_lock(pg_catalog.hashtextextended('${
        uuid(joinFirst.id)
      }', 1))`,
      "t",
      "join holds account lock",
    );
    await waitForSqlValue(
      `select count(*) from pg_stat_activity where pid <> pg_backend_pid() and wait_event_type = 'Lock' and query ilike '%join_match%'`,
      "1",
      "join waits on match lock",
    );

    const deletePromise = edge(joinFirst.session, "delete-account", {
      client_build: 1,
    });
    await waitForSqlValue(
      `select count(*) from pg_stat_activity where pid <> pg_backend_pid() and wait_event_type = 'Lock' and query ilike '%begin_account_deletion%'`,
      "1",
      "deletion waits on join account lock",
    );
    await held;
    const [joined, deleted] = await Promise.all([joinPromise, deletePromise]);
    assert(joined.status === 200, "join-before-delete join completes");
    assert(deleted.status === 200, "join-before-delete deletion completes");
    createdUsers.delete(joinFirst.id);

    const tokenHash = await sha256(joinFirst.session.access_token);
    assert(
      (await edge(joinFirst.session, "delete-account", { client_build: 1 }))
        .status === 200,
      "join-before-delete receipt replay remains completed",
    );
    assert(
      (await edge(joinFirst.session, "match-snapshot", {
        client_build: 1,
        match_id: matchIdValue,
      })).status === 401,
      "join-before-delete stale bearer cannot read",
    );
    assert(
      (await edge(joinFirst.session, "join-match", {
        client_build: 1,
        join_code: joinCode,
      })).status === 401,
      "join-before-delete stale bearer cannot write",
    );
    assert(
      await sqlScalar(
        `select count(*) from auth.users where id = '${uuid(joinFirst.id)}'`,
      ) === "0",
      "join-before-delete Auth identity removed",
    );
    assert(
      await sqlScalar(
        `select count(*) from public.profiles where id = '${
          uuid(joinFirst.id)
        }'`,
      ) === "0",
      "join-before-delete profile removed",
    );
    assert(
      await sqlScalar(
        `select count(*) from public.match_members where auth_user_id = '${
          uuid(joinFirst.id)
        }'`,
      ) === "0",
      "join-before-delete membership identity removed",
    );
    assert(
      await sqlScalar(
        `select count(*) from private.user_rate_limits where actor_user_id = '${
          uuid(joinFirst.id)
        }'`,
      ) === "0",
      "join-before-delete rate identity removed",
    );
    assert(
      await sqlScalar(
        `select count(*) from private.account_deletion_receipts where token_hash = '${tokenHash}' and status = 'completed' and user_id is null and completed_at is not null`,
      ) === "1",
      "join-before-delete receipt is terminal",
    );

    const deleteFirstHost = await createUser("delete-join-host");
    const deleteFirst = await createUser("delete-join-member");
    const deleteFirstCreated = await edge(
      deleteFirstHost.session,
      "create-match",
      { client_build: 1, request_id: crypto.randomUUID() },
    );
    const deleteFirstMatch = matchId(deleteFirstCreated);
    const deleteFirstCode = await matchJoinCode(
      deleteFirstHost,
      deleteFirstMatch,
    );
    assert(
      (await edge(deleteFirst.session, "delete-account", { client_build: 1 }))
        .status === 200,
      "delete-before-join deletion completes",
    );
    createdUsers.delete(deleteFirst.id);
    assert(
      (await edge(deleteFirst.session, "join-match", {
        client_build: 1,
        join_code: deleteFirstCode,
      })).status === 401,
      "delete-before-join stale join rejected",
    );
    assert(
      await sqlScalar(
        `select count(*) from public.match_members where auth_user_id = '${
          uuid(deleteFirst.id)
        }'`,
      ) === "0",
      "delete-before-join creates no membership",
    );
    assert(
      await sqlScalar(
        `select count(*) from public.profiles where id = '${
          uuid(deleteFirst.id)
        }'`,
      ) === "0",
      "delete-before-join profile remains absent",
    );
    assert(
      await sqlScalar(
        `select count(*) from private.user_rate_limits where actor_user_id = '${
          uuid(deleteFirst.id)
        }'`,
      ) === "0",
      "delete-before-join creates no rate row",
    );
  });

  await scenario(
    "rate-counter concurrency completes without deadlock",
    async () => {
      const host = await createUser("rate-host");
      const results = await Promise.all([
        edge(host.session, "create-match", {
          client_build: 1,
          request_id: crypto.randomUUID(),
        }),
        edge(host.session, "create-match", {
          client_build: 1,
          request_id: crypto.randomUUID(),
        }),
      ]);
      assert(
        results.every((result) => result.status === 200),
        "concurrent rate-counter operations complete",
      );
      assert(
        matchId(results[0]) !== matchId(results[1]),
        "distinct canonical rooms",
      );
    },
  );

  await scenario("lobby deletion isolation", async () => {
    const host = await createUser("lobby-host");
    const guest = await createUser("lobby-guest");
    const replacement = await createUser("lobby-replacement");
    const created = await edge(host.session, "create-match", {
      client_build: 1,
      request_id: crypto.randomUUID(),
    });
    const matchIdValue = matchId(created);
    const lobby = data(
      await edge(host.session, "match-snapshot", {
        client_build: 1,
        match_id: matchIdValue,
      }),
    );
    const code = nestedString(lobby, "match", "join_code");
    assert(
      (await edge(guest.session, "join-match", {
        client_build: 1,
        join_code: code,
      })).status === 200,
      "lobby join",
    );
    assert(
      (await edge(guest.session, "delete-account", { client_build: 1 }))
        .status === 200,
      "guest lobby deletion",
    );
    createdUsers.delete(guest.id);
    const afterGuest = data(
      await edge(host.session, "match-snapshot", {
        client_build: 1,
        match_id: matchIdValue,
      }),
    );
    assert(array(afterGuest.members).length === 1, "guest seat removed");
    assert(
      (await edge(replacement.session, "join-match", {
        client_build: 1,
        join_code: code,
      })).status === 200,
      "replacement join",
    );
    assert(
      (await edge(host.session, "delete-account", { client_build: 1 }))
        .status === 200,
      "host lobby deletion",
    );
    createdUsers.delete(host.id);
    const unavailable = await edge(replacement.session, "match-snapshot", {
      client_build: 1,
      match_id: matchIdValue,
    });
    assert(unavailable.status === 403, "deleted host lobby unavailable");
  });

  await scenario("deletion partial-stage recovery", async () => {
    const beforeAuthDelete = await createUser("delete-pending");
    const beforeHash = await sha256(beforeAuthDelete.session.access_token);
    await sql(
      `select public.begin_account_deletion('${
        uuid(beforeAuthDelete.id)
      }', 1, '${beforeHash}')`,
    );
    const resumed = await edge(beforeAuthDelete.session, "delete-account", {
      client_build: 1,
    });
    assert(resumed.status === 200, "resume pending deletion");
    createdUsers.delete(beforeAuthDelete.id);

    const afterAuthDelete = await createUser("delete-auth-gone");
    const afterHash = await sha256(afterAuthDelete.session.access_token);
    await sql(
      `select public.begin_account_deletion('${
        uuid(afterAuthDelete.id)
      }', 1, '${afterHash}')`,
    );
    const removed = await admin.auth.admin.deleteUser(
      afterAuthDelete.id,
      false,
    );
    assert(removed.error === null, "fixture auth deletion");
    createdUsers.delete(afterAuthDelete.id);
    const completed = await edge(afterAuthDelete.session, "delete-account", {
      client_build: 1,
    });
    assert(completed.status === 200, "complete after auth deletion");
    const replay = await edge(afterAuthDelete.session, "delete-account", {
      client_build: 1,
    });
    assert(replay.status === 200, "completed deletion replay");
  });

  await scenario(
    "v2 configured rounds, target concurrency, receipts and exact standings",
    async () => {
      for (const count of [1, 3, 5]) {
        const host = await createUser(`v2-${count}-host`);
        const guest = await createUser(`v2-${count}-guest`);
        const requestId = crypto.randomUUID();
        const created = await edge(host.session, "create-match", {
          client_build: 2,
          request_id: requestId,
          round_count: count,
        });
        const match = matchId(created);
        const snap = async (viewer = host) =>
          data(
            await edge(viewer.session, "match-snapshot", {
              client_build: 2,
              match_id: match,
            }),
          );
        const start = (target: number, viewer = host) =>
          edge(viewer.session, "start-match", {
            client_build: 2,
            match_id: match,
            round_number: target,
          });
        const submit = (
          viewer: TestUser,
          target: number,
          id: string,
          word: string,
        ) =>
          edge(viewer.session, "submit-guess", {
            ...guessBody(match, id, word),
            client_build: 2,
            round_number: target,
          });
        const capture = (label: string, snapshot: Json) => {
          captureSummary(`${count}-${label}`, snapshot);
        };
        let snapshot = await snap();
        capture("lobby", snapshot);
        assert(snapshot.version === 2, "snapshot2 version");
        assert(
          snapshot.standings === null &&
            array(snapshot.revealed_rounds).length === 0,
          "no premature standings",
        );
        assertError(
          await edge(host.session, "match-snapshot", {
            client_build: 1,
            match_id: match,
          }),
          426,
          "client_update_required",
        );
        assertError(
          await edge(host.session, "create-match", {
            client_build: 2,
            request_id: requestId,
            round_count: count === 1 ? 3 : 1,
          }),
          409,
          "request_conflict",
        );
        assertError(
          await edge(host.session, "create-match", {
            client_build: 2,
            request_id: crypto.randomUUID(),
            round_count: 2,
          }),
          400,
          "invalid_match_configuration",
        );
        const deniedCreate = await host.client.rpc("create_match", {
          p_user_id: host.id,
          p_client_build: 2,
          p_ip_hash: null,
          p_request_id: crypto.randomUUID(),
          p_round_count: count,
        });
        const deniedStart = await host.client.rpc("start_match", {
          p_user_id: host.id,
          p_client_build: 2,
          p_match_id: match,
          p_round_number: 1,
        });
        assert(
          deniedCreate.error !== null && deniedStart.error !== null,
          "v2 direct RPC denial",
        );
        const reason = await host.client.from("matches").select(
          "terminal_reason",
        ).eq("id", match);
        assert(reason.error !== null, "terminal reason direct denial");
        assert(
          (await edge(guest.session, "join-match", {
            client_build: 2,
            join_code: nestedString(snapshot, "match", "join_code"),
          })).status === 200,
          "v2 guest join",
        );
        assertError(await start(1, guest), 403, "not_host");
        let originalReceipt: EdgeResult | undefined;
        let originalWord = "";
        const receiptId = crypto.randomUUID();
        for (let target = 1; target <= count; target++) {
          const beforeRevision = nested(await snap(), "match", "revision");
          const signal = count === 3 && target === 2
            ? await subscribeToMatchSignal(guest, match)
            : undefined;
          const barrier = await holdMatchLockBarrier(
            match,
            `gridrace-v2-start-${crypto.randomUUID()}`,
          );
          let starts: Promise<EdgeResult[]>;
          const startsRequests: Promise<EdgeResult>[] = [];
          try {
            const first = start(target);
            startsRequests.push(first);
            await waitForSqlValue(
              `select count(*) from pg_stat_activity where pid <> pg_backend_pid() and wait_event_type='Lock' and query ilike '%start_match%'`,
              "1",
              "first Start waits behind barrier",
            );
            const second = start(target);
            startsRequests.push(second);
            await waitForSqlValue(
              `select count(*) from pg_stat_activity where pid <> pg_backend_pid() and wait_event_type='Lock' and query ilike '%start_match%'`,
              "2",
              "second Start waits behind actor lock",
            );
            starts = Promise.all([first, second]);
          } finally {
            await barrier.release();
            await Promise.allSettled(startsRequests);
            if (signal) {
              try {
                const payload = await signal.next;
                assert(
                  Object.keys(payload).every((key) =>
                    safeMatchColumns.split(",").includes(key)
                  ),
                  "v2 Realtime safe column projection",
                );
                assert(
                  payload.current_round === target,
                  "v2 Realtime next-round signal",
                );
                assert(
                  !("terminal_reason" in payload) && !("standings" in payload),
                  "v2 Realtime no reason or totals",
                );
              } finally {
                await signal.close();
              }
            }
          }
          assert(
            (await starts!).every((result) => result.status === 200),
            "concurrent targeted starts succeed",
          );
          snapshot = await snap();
          capture(`round-${target}-countdown`, snapshot);
          assert(
            Number(nested(snapshot, "match", "revision")) ===
              Number(beforeRevision) + 1,
            "Start mutates once",
          );
          assert(
            nested(snapshot, "round", "number") === target,
            "immutable target is current",
          );
          assert(
            nested(snapshot, "round", "state") === "countdown",
            "countdown starts",
          );
          assert(
            nested(snapshot, "round", "answer") === null,
            "active answer hidden",
          );
          assert(
            array(snapshot.revealed_rounds).length === target - 1,
            "history stops before current",
          );
          assertOpponentBoardHidden(snapshot);
          assert(
            await sqlScalar(
              `select count(*) from private.round_secrets s join public.rounds r on r.id=s.round_id where r.match_id='${
                uuid(match)
              }'`,
            ) === String(target),
            "future secrets absent",
          );
          assert(
            await sqlScalar(
              `select count(distinct s.answer) from private.round_secrets s join public.rounds r on r.id=s.round_id where r.match_id='${
                uuid(match)
              }'`,
            ) === String(target),
            "answers nonrepeating",
          );
          assert(
            await sqlScalar(
              `select count(*) from public.player_rounds p join public.rounds r on r.id=p.round_id where r.match_id='${
                uuid(match)
              }'`,
            ) === String(2 * target),
            "future player rows absent",
          );
          const direct = await host.client.from("rounds").select(
            "round_number,revealed_answer",
          ).eq("match_id", match);
          assert(
            !direct.error &&
              direct.data.every((row) =>
                row.round_number < target || row.revealed_answer === null
              ),
            "RLS no future or active answer",
          );
          if (target < count) {
            assertError(await start(target + 1), 409, "round_not_active");
            assertError(
              await submit(host, target + 1, crypto.randomUUID(), "apple"),
              409,
              "round_not_active",
            );
          }
          if (target > 1) {
            const stale = await start(target - 1);
            assert(stale.status === 200, "stale started target succeeds");
            assert(
              nested(await snap(), "match", "revision") ===
                nested(snapshot, "match", "revision"),
              "stale target no mutation",
            );
            assert(
              JSON.stringify(
                (await submit(host, 1, receiptId, originalWord)).body,
              ) === JSON.stringify(originalReceipt!.body),
              "cross-round receipt exact response/time",
            );
            assertError(
              await submit(host, target, receiptId, originalWord),
              409,
              "request_conflict",
            );
          }
          await delay(3100);
          snapshot = await snap();
          capture(`round-${target}-playing`, snapshot);
          const answer = await sqlScalar(
            `select s.answer from private.round_secrets s join public.rounds r on r.id=s.round_id where r.match_id='${
              uuid(match)
            }' and r.round_number=${target}`,
          );
          const wrong = await anotherWord(answer);
          const id = target === 1 ? receiptId : crypto.randomUUID();
          const guessBarrier = await holdMatchLockBarrier(
            match,
            `gridrace-v2-guess-${crypto.randomUUID()}`,
          );
          let guesses: Promise<EdgeResult[]>;
          const guessesRequests: Promise<EdgeResult>[] = [];
          try {
            const first = submit(host, target, id, wrong);
            guessesRequests.push(first);
            await waitForSqlValue(
              `select count(*) from pg_stat_activity where pid <> pg_backend_pid() and wait_event_type='Lock' and query ilike '%submit_guess%'`,
              "1",
              "guess waits on match barrier",
            );
            const second = submit(host, target, id, wrong);
            guessesRequests.push(second);
            await waitForSqlValue(
              `select count(*) from pg_stat_activity where pid <> pg_backend_pid() and wait_event_type='Lock' and query ilike '%submit_guess%'`,
              "2",
              "duplicate waits on actor",
            );
            guesses = Promise.all([first, second]);
          } finally {
            await guessBarrier.release();
            await Promise.allSettled(guessesRequests);
          }
          const accepted = await guesses!;
          assert(
            accepted.every((result) => result.status === 200),
            "duplicate guesses succeed",
          );
          assert(
            JSON.stringify(accepted[0].body) ===
              JSON.stringify(accepted[1].body),
            "duplicate receipts identical",
          );
          assert(
            await sqlScalar(
              `select count(*) from public.guesses where request_id='${
                uuid(id)
              }'`,
            ) === "1",
            "one canonical guess",
          );
          if (target === 1) {
            originalReceipt = accepted[0];
            originalWord = wrong;
          }
          assert(
            (await submit(host, target, crypto.randomUUID(), answer)).status ===
              200,
            "host solves",
          );
          snapshot = await snap(guest);
          capture(`round-${target}-unrevealed-solved-opponent`, snapshot);
          assertOpponentBoardHidden(snapshot);
          assert(
            array(snapshot.revealed_rounds).length === target - 1,
            "unrevealed solve excluded",
          );
          assert(
            (await submit(guest, target, crypto.randomUUID(), wrong)).status ===
              200,
            "guest accepts wrong row",
          );
          assert(
            (await submit(guest, target, crypto.randomUUID(), answer))
              .status === 200,
            "guest solves and finalizes",
          );
          // Exact synthetic timing fixtures retain actual gateway boards. Both display 1ms.
          await sql(
            `update public.player_rounds p set solve_duration_us=case when m.seat=1 then 1600 else 1900 end, finished_at=p.started_at+case when m.seat=1 then interval '1600 microseconds' else interval '1900 microseconds' end from public.match_members m, public.rounds r where p.member_id=m.id and p.round_id=r.id and r.match_id='${
              uuid(match)
            }' and r.round_number=${target}`,
          );
          await sql(
            `update public.guesses g set submitted_at=case when g.sequence=2 then p.finished_at else p.started_at+interval '500 microseconds' end from public.player_rounds p,public.rounds r where g.round_id=p.round_id and g.member_id=p.member_id and p.round_id=r.id and r.match_id='${
              uuid(match)
            }' and r.round_number=${target}`,
          );
          snapshot = await snap();
          capture(`round-${target}-reveal`, snapshot);
          assert(
            nested(snapshot, "match", "status") ===
              (target === count ? "completed" : "in_progress"),
            "configured final status",
          );
          assert(
            array(snapshot.revealed_rounds).length === target,
            "revealed history contiguous",
          );
          assert(
            JSON.stringify(snapshot.round) ===
              JSON.stringify(array(snapshot.revealed_rounds)[target - 1]),
            "current/history exact agreement",
          );
          assertAllBoardsVisible(snapshot);
          const standings = snapshot.standings as Json;
          const totals = array(standings.players) as Json[];
          assert(
            standings.through_round === target &&
              standings.is_final === (target === count),
            "canonical through/final",
          );
          assert(
            totals[0].rounds_solved === target &&
              totals[0].efficiency_points === target * 5,
            "solved/efficiency totals",
          );
          assert(
            totals[0].total_solve_duration_ms ===
              Math.floor(1600 * target / 1000),
            "floor SUM once",
          );
          assert(
            totals[0].placement === 1 && totals[1].placement === 2,
            "exact rank at equal displayed times",
          );
          const replay = await submit(host, 1, receiptId, originalWord);
          assert(
            JSON.stringify(replay.body) ===
              JSON.stringify(originalReceipt!.body),
            "receipt replay after reveal/final",
          );
          assertError(
            await submit(host, target, crypto.randomUUID(), wrong),
            409,
            "round_already_finished",
          );
          const before = await snap();
          const staleBarrier = await holdMatchLockBarrier(
            match,
            `gridrace-v2-stale-${crypto.randomUUID()}`,
          );
          let stale: Promise<EdgeResult[]>;
          const staleRequests: Promise<EdgeResult>[] = [];
          try {
            const first = start(1);
            staleRequests.push(first);
            await waitForSqlValue(
              `select count(*) from pg_stat_activity where pid <> pg_backend_pid() and wait_event_type='Lock' and query ilike '%start_match%'`,
              "1",
              "stale Start barrier",
            );
            const second = start(1);
            staleRequests.push(second);
            await waitForSqlValue(
              `select count(*) from pg_stat_activity where pid <> pg_backend_pid() and wait_event_type='Lock' and query ilike '%start_match%'`,
              "2",
              "duplicate stale Start barrier",
            );
            stale = Promise.all([first, second]);
          } finally {
            await staleBarrier.release();
            await Promise.allSettled(staleRequests);
          }
          assert(
            (await stale!).every((result) => result.status === 200),
            "stale starts succeed after reveal/final",
          );
          assert(
            nested(await snap(), "match", "revision") ===
              nested(before, "match", "revision"),
            "stale starts never advance",
          );
          await sql(
            `select private.finalize_round(id) from public.rounds where match_id='${
              uuid(match)
            }' and round_number=${target}`,
          );
          assert(
            nested(await snap(), "match", "revision") ===
              nested(before, "match", "revision"),
            "repeat finalization leaves revision",
          );
        }
        // Exact ties share placement without seat tie-breaking.
        await sql(
          `update public.player_rounds p set solve_duration_us=1600, placement=1, finished_at=p.started_at+interval '1600 microseconds' from public.rounds r where p.round_id=r.id and r.match_id='${
            uuid(match)
          }'`,
        );
        await sql(
          `update public.guesses g set submitted_at=case when g.sequence=2 then p.finished_at else p.started_at+interval '500 microseconds' end from public.player_rounds p,public.rounds r where g.round_id=p.round_id and g.member_id=p.member_id and p.round_id=r.id and r.match_id='${
            uuid(match)
          }'`,
        );
        snapshot = await snap();
        capture("final-tie", snapshot);
        assert(
          array((snapshot.standings as Json).players).every((player) =>
            (player as Json).placement === 1
          ),
          "exact tie shares first",
        );
        assert(
          nested(snapshot, "match", "completed_at") ===
            nested(snapshot, "round", "completed_at"),
          "final timestamp exact",
        );
        assert(
          matchId(
            await edge(host.session, "create-match", {
              client_build: 2,
              request_id: requestId,
              round_count: count,
            }),
          ) === match,
          "create replay after final",
        );
      }
    },
  );

  await scenario(
    "v2 deletion matrix, future-start race and current-final preservation",
    async () => {
      for (
        const boundary of [
          "active",
          "between",
          "final-active",
          "completed",
        ] as const
      ) {
        const host = await createUser(`v2-delete-${boundary}-host`);
        const guest = await createUser(`v2-delete-${boundary}-guest`);
        const match = matchId(
          await edge(host.session, "create-match", {
            client_build: 2,
            request_id: crypto.randomUUID(),
            round_count: 3,
          }),
        );
        const snap = async () =>
          data(
            await edge(host.session, "match-snapshot", {
              client_build: 2,
              match_id: match,
            }),
          );
        assert(
          (await edge(guest.session, "join-match", {
            client_build: 2,
            join_code: nestedString(await snap(), "match", "join_code"),
          })).status === 200,
          "deletion fixture joins",
        );
        const target = boundary.startsWith("final") || boundary === "completed"
          ? 3
          : 1;
        for (let round = 1; round <= target; round++) {
          assert(
            (await edge(host.session, "start-match", {
              client_build: 2,
              match_id: match,
              round_number: round,
            })).status === 200,
            "deletion fixture starts",
          );
          if (
            round < target || boundary === "between" || boundary === "completed"
          ) {
            await sql(
              `update public.player_rounds p set state='forfeited',finished_at=transaction_timestamp(),efficiency_points=0 from public.rounds r where p.round_id=r.id and r.match_id='${
                uuid(match)
              }' and r.round_number=${round}; select private.finalize_round(id) from public.rounds where match_id='${
                uuid(match)
              }' and round_number=${round}`,
            );
          }
        }
        const before = await snap();
        // A held match ensures deletion and same-actor command are separate waiting transactions.
        const barrier = await holdMatchLockBarrier(
          match,
          `gridrace-v2-delete-${crypto.randomUUID()}`,
        );
        let pending: Promise<EdgeResult[]>;
        const pendingRequests: Promise<EdgeResult>[] = [];
        try {
          const deleting = edge(guest.session, "delete-account", {
            client_build: 2,
          });
          pendingRequests.push(deleting);
          await waitForSqlValue(
            `select count(*) from pg_stat_activity where pid<>pg_backend_pid() and wait_event_type='Lock' and query ilike '%begin_account_deletion%'`,
            "1",
            "deletion waits on match barrier",
          );
          const guessing = edge(guest.session, "submit-guess", {
            ...guessBody(match, crypto.randomUUID(), "apple"),
            client_build: 2,
            round_number: target,
          });
          pendingRequests.push(guessing);
          await waitForSqlValue(
            `select count(*) from pg_stat_activity where pid<>pg_backend_pid() and wait_event_type='Lock' and query ilike '%submit_guess%'`,
            "1",
            "submit waits on deletion actor lock",
          );
          pending = Promise.all([deleting, guessing]);
        } finally {
          await barrier.release();
          await Promise.allSettled(pendingRequests);
        }
        const [deleted, guess] = await pending!;
        assert(deleted.status === 200, "deletion completes");
        createdUsers.delete(guest.id);
        assertError(guess, 401, "not_authenticated");
        let snapshot = await snap();
        captureSummary(`deletion-${boundary}`, snapshot);
        assertDeletedMemberIdentity(snapshot);
        const nonfinal = target < 3;
        assert(
          nested(snapshot, "match", "terminal_reason") ===
            (nonfinal ? "account_deleted" : null),
          "deletion reason only nonfinal",
        );
        assert(
          nested(snapshot, "match", "status") ===
            (boundary === "between"
              ? "incomplete"
              : boundary === "completed"
              ? "completed"
              : "in_progress"),
          "deletion status matrix",
        );
        assert(
          nested(snapshot, "match", "completed_at") ===
            (boundary === "completed"
              ? nested(before, "match", "completed_at")
              : null),
          "deletion does not invent completion",
        );
        if (nonfinal) {
          assertError(
            await edge(host.session, "start-match", {
              client_build: 2,
              match_id: match,
              round_number: 2,
            }),
            409,
            "match_incomplete",
          );
        }
        if (boundary === "active" || boundary === "final-active") {
          // Move the synthetic fixture's entire timeline together. The scheduled
          // job, rather than a snapshot/finalizer request, must finish the round.
          await sql(
            `update public.matches set started_at=started_at-interval '185 seconds' where id='${
              uuid(match)
            }'; update public.rounds set starts_at=starts_at-interval '185 seconds',ends_at=ends_at-interval '185 seconds',completed_at=completed_at-interval '185 seconds' where match_id='${
              uuid(match)
            }'; update public.player_rounds p set started_at=p.started_at-interval '185 seconds',finished_at=p.finished_at-interval '185 seconds' from public.rounds r where p.round_id=r.id and r.match_id='${
              uuid(match)
            }'`,
          );
          await waitForSqlValue(
            `select state from public.rounds where match_id='${
              uuid(match)
            }' and round_number=${target}`,
            "revealed",
            "scheduled Cron completes without client requests",
            70_000,
          );
          snapshot = await snap();
          captureSummary(`deletion-${boundary}-revealed`, snapshot);
          assert(
            nested(snapshot, "match", "status") ===
              (nonfinal ? "incomplete" : "completed"),
            "Cron deletion completion boundary",
          );
          assert(
            nested(snapshot, "match", "terminal_reason") ===
              (nonfinal ? "account_deleted" : null),
            "Cron completion reason",
          );
        }
        assert(
          (snapshot.standings as Json).is_final === !nonfinal,
          "partial/final standings boundary",
        );
        const stableRevision = nested(snapshot, "match", "revision");
        assert(
          (await edge(guest.session, "delete-account", { client_build: 2 }))
            .status === 200,
          "deletion receipt replay",
        );
        assert(
          nested(await snap(), "match", "revision") === stableRevision,
          "repeat prep has no revision",
        );
        assert(
          await sqlScalar(
            `select count(*) from private.round_secrets s join public.rounds r on r.id=s.round_id where r.match_id='${
              uuid(match)
            }'`,
          ) === String(target),
          "no future secret after deletion",
        );
        assert(
          await sqlScalar(
            `select count(*) from public.rounds where match_id='${
              uuid(match)
            }' and round_number>${target} and state<>'pending'`,
          ) === "0",
          "Cron never advances",
        );
        assert(
          (await edge(host.session, "delete-account", { client_build: 2 }))
            .status === 200,
          "later deletion completes",
        );
        createdUsers.delete(host.id);
        assert(
          await sqlScalar(
            `select status from public.matches where id='${uuid(match)}'`,
          ) === (nonfinal ? "incomplete" : "completed"),
          "later deletion preserves terminal status",
        );
      }
    },
  );

  await scenario(
    "v2 deletion blocks queued next Start for either actor",
    async () => {
      for (const deleteCreator of [false, true]) {
        const host = await createUser("v2-start-delete-host");
        const guest = await createUser("v2-start-delete-guest");
        const deleting = deleteCreator ? host : guest;
        const survivor = deleteCreator ? guest : host;
        const match = matchId(
          await edge(host.session, "create-match", {
            client_build: 2,
            request_id: crypto.randomUUID(),
            round_count: 3,
          }),
        );
        const lobby = data(
          await edge(host.session, "match-snapshot", {
            client_build: 2,
            match_id: match,
          }),
        );
        assert(
          (await edge(guest.session, "join-match", {
            client_build: 2,
            join_code: nestedString(lobby, "match", "join_code"),
          })).status === 200,
          "Start/delete fixture join",
        );
        assert(
          (await edge(host.session, "start-match", {
            client_build: 2,
            match_id: match,
            round_number: 1,
          })).status === 200,
          "Start/delete first round",
        );
        await sql(
          `update public.player_rounds p set state='forfeited',finished_at=transaction_timestamp(),efficiency_points=0 from public.rounds r where p.round_id=r.id and r.match_id='${
            uuid(match)
          }' and r.round_number=1; select private.finalize_round(id) from public.rounds where match_id='${
            uuid(match)
          }' and round_number=1`,
        );
        const barrier = await holdMatchLockBarrier(
          match,
          `gridrace-v2-next-delete-${crypto.randomUUID()}`,
        );
        const requests: Promise<EdgeResult>[] = [];
        try {
          requests.push(
            edge(deleting.session, "delete-account", { client_build: 2 }),
          );
          await waitForSqlValue(
            `select count(*) from pg_stat_activity where pid<>pg_backend_pid() and wait_event_type='Lock' and query ilike '%begin_account_deletion%'`,
            "1",
            "deletion queued first",
          );
          requests.push(
            edge(host.session, "start-match", {
              client_build: 2,
              match_id: match,
              round_number: 2,
            }),
          );
          await waitForSqlValue(
            `select count(*) from pg_stat_activity where pid<>pg_backend_pid() and wait_event_type='Lock' and query ilike '%start_match%'`,
            "1",
            "captured next Start queued",
          );
        } finally {
          await barrier.release();
          await Promise.allSettled(requests);
        }
        const [deleted, started] = await Promise.all(requests);
        assert(deleted.status === 200, "deletion wins barrier order");
        createdUsers.delete(deleting.id);
        assertError(
          started,
          deleteCreator ? 401 : 409,
          deleteCreator ? "not_authenticated" : "match_incomplete",
        );
        const snapshot = data(
          await edge(survivor.session, "match-snapshot", {
            client_build: 2,
            match_id: match,
          }),
        );
        assert(
          nested(snapshot, "match", "status") === "incomplete",
          "queued Start leaves incomplete",
        );
        assert(
          nested(snapshot, "match", "current_round") === 1,
          "queued Start cannot advance",
        );
        assert(
          await sqlScalar(
            `select count(*) from private.round_secrets s join public.rounds r on r.id=s.round_id where r.match_id='${
              uuid(match)
            }'`,
          ) === "1",
          "queued Start has no future secret",
        );
        captureSummary(
          `deletion-${deleteCreator ? "creator" : "guest"}-queued-start`,
          snapshot,
        );
      }
    },
  );

  await scenario(
    "v2 ordinary reveal waits for creator after scheduled Cron",
    async () => {
      const host = await createUser("v2-cron-host");
      const guest = await createUser("v2-cron-guest");
      const match = matchId(
        await edge(host.session, "create-match", {
          client_build: 2,
          request_id: crypto.randomUUID(),
          round_count: 3,
        }),
      );
      const snap = async () =>
        data(
          await edge(host.session, "match-snapshot", {
            client_build: 2,
            match_id: match,
          }),
        );
      const lobby = await snap();
      assert(
        (await edge(guest.session, "join-match", {
          client_build: 2,
          join_code: nestedString(lobby, "match", "join_code"),
        })).status === 200,
        "Cron fixture join",
      );
      assert(
        (await edge(host.session, "start-match", {
          client_build: 2,
          match_id: match,
          round_number: 1,
        })).status === 200,
        "Cron first Start",
      );
      await sql(
        `update public.matches set started_at=started_at-interval '185 seconds' where id='${
          uuid(match)
        }'; update public.rounds set starts_at=starts_at-interval '185 seconds',ends_at=ends_at-interval '185 seconds' where match_id='${
          uuid(match)
        }'; update public.player_rounds p set started_at=p.started_at-interval '185 seconds' from public.rounds r where p.round_id=r.id and r.match_id='${
          uuid(match)
        }'`,
      );
      await waitForSqlValue(
        `select state from public.rounds where match_id='${
          uuid(match)
        }' and round_number=1`,
        "revealed",
        "scheduled Cron without connected clients",
        70_000,
      );
      const snapshot = await snap();
      assert(
        nested(snapshot, "match", "status") === "in_progress" &&
          nested(snapshot, "match", "terminal_reason") === null,
        "ordinary nonfinal reveal waits",
      );
      assert(
        nested(snapshot, "match", "current_round") === 1 &&
          array(snapshot.revealed_rounds).length === 1,
        "Cron never advances ordinary room",
      );
      assert(
        (snapshot.standings as Json).is_final === false,
        "ordinary partial standings",
      );
      captureSummary("ordinary-cron-nonfinal", snapshot);
      await sql(
        `update public.matches set expires_at=created_at+interval '1 millisecond' where id='${
          uuid(match)
        }'`,
      );
      assert(
        (await edge(host.session, "start-match", {
          client_build: 2,
          match_id: match,
          round_number: 2,
        })).status === 200,
        "lobby expiry does not gate next round",
      );
      const next = await snap();
      assert(
        nested(next, "round", "number") === 2 &&
          nested(next, "round", "state") === "countdown",
        "creator starts next round explicitly",
      );
      assert(
        JSON.stringify(next.revealed_rounds) ===
          JSON.stringify(snapshot.revealed_rounds),
        "prior reveals retained",
      );
    },
  );

  const snapshotMetrics = edgeMetrics.filter((metric) =>
    metric.name === "match-snapshot"
  );
  const slowestMs = Math.max(...edgeMetrics.map((metric) => metric.elapsedMs));
  const largestSnapshot = Math.max(
    ...snapshotMetrics.map((metric) => metric.bytes),
  );
  console.log(
    `PASS live-slice integration ${edgeMetrics.length} requests ${snapshotMetrics.length} snapshots ${largestSnapshot} bytes max ${slowestMs}ms max`,
  );
} finally {
  // Track successful Create responses even if their caller fails before extracting ID.
  // Match removal cascades its private answers, guesses and create receipts only.
  for (const match of createdMatches) {
    await sql(`delete from public.matches where id='${uuid(match)}'`);
  }
  for (const tokenHash of deletionHashes) {
    await sql(
      `delete from private.account_deletion_receipts where token_hash='${tokenHash}'`,
    );
  }
  for (const userId of createdUsers) {
    const prepared = await admin.rpc("delete_account", {
      p_user_id: userId,
      p_client_build: 2,
    });
    assert(prepared.error === null, "fixture deletion preparation");
    const deleted = await admin.auth.admin.deleteUser(userId, false);
    assert(deleted.error === null, "fixture Auth deletion");
  }
}

async function createUser(label: string): Promise<TestUser> {
  const suffix = crypto.randomUUID();
  const email = `${label}-${suffix}@example.test`;
  const password = `GridRace-${suffix}`;
  const created = await admin.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
  });
  if (created.error || !created.data.user) {
    throw new Error("auth fixture creation failed");
  }
  createdUsers.add(created.data.user.id);
  const client = createClient(apiUrl, anonKey, clientOptions);
  const signedIn = await client.auth.signInWithPassword({ email, password });
  if (signedIn.error || !signedIn.data.session) {
    throw new Error("auth fixture sign-in failed");
  }
  return { id: created.data.user.id, session: signedIn.data.session, client };
}

async function createLobbyWithGuest(
  host: TestUser,
  guest: TestUser,
): Promise<string> {
  const created = await edge(host.session, "create-match", {
    client_build: 1,
    request_id: crypto.randomUUID(),
  });
  const matchIdValue = matchId(created);
  const joinCode = await matchJoinCode(host, matchIdValue);
  const joined = await edge(guest.session, "join-match", {
    client_build: 1,
    join_code: joinCode,
  });
  assert(joined.status === 200, "fixture guest join");
  return matchIdValue;
}

async function createPlayingMatch(
  host: TestUser,
  guest: TestUser,
): Promise<string> {
  const matchIdValue = await createLobbyWithGuest(host, guest);
  const started = await edge(host.session, "start-match", {
    client_build: 1,
    match_id: matchIdValue,
  });
  assert(started.status === 200, "fixture match start");
  await sql(
    `update public.rounds set starts_at = transaction_timestamp() - interval '1 second', ends_at = transaction_timestamp() - interval '1 second' + interval '180 seconds' where match_id = '${
      uuid(matchIdValue)
    }'; update public.player_rounds set started_at = clock_timestamp() - interval '1 second' where round_id = (select id from public.rounds where match_id = '${
      uuid(matchIdValue)
    }')`,
  );
  return matchIdValue;
}

async function matchJoinCode(
  user: TestUser,
  matchIdValue: string,
): Promise<string> {
  const snapshot = data(
    await edge(user.session, "match-snapshot", {
      client_build: 1,
      match_id: matchIdValue,
    }),
  );
  return nestedString(snapshot, "match", "join_code");
}

async function matchRoundId(matchIdValue: string): Promise<string> {
  return uuid(
    await sqlScalar(
      `select id from public.rounds where match_id = '${
        uuid(matchIdValue)
      }' and round_number = 1`,
    ),
  );
}

async function matchAnswer(matchIdValue: string): Promise<string> {
  return sqlLiteral(
    await sqlScalar(
      `select secret.answer from private.round_secrets secret join public.rounds round on round.id = secret.round_id where round.match_id = '${
        uuid(matchIdValue)
      }'`,
    ),
  );
}

async function anotherWord(answer: string, offset = 0): Promise<string> {
  assert(Number.isInteger(offset) && offset >= 0, "word fixture offset");
  return sqlLiteral(
    await sqlScalar(
      `select word from private.words where word <> '${
        sqlLiteral(answer)
      }' order by word offset ${offset} limit 1`,
    ),
  );
}

async function holdMatchLock(
  matchIdValue: string,
  seconds: number,
  applicationName?: string,
): Promise<void> {
  assert(
    Number.isInteger(seconds) && seconds > 0 && seconds <= 5,
    "lock duration",
  );
  await sql(
    `begin; select 1 from public.matches where id = '${
      uuid(matchIdValue)
    }' for update; select pg_sleep(${seconds}); commit`,
    applicationName,
  );
}

async function holdMatchLockBarrier(
  matchIdValue: string,
  applicationName: string,
): Promise<{ release: () => Promise<void> }> {
  const child = new Deno.Command("psql", {
    args: [
      ...database.args,
      "-XAtq",
      "-v",
      "ON_ERROR_STOP=1",
      "-c",
      `begin; select 1 from public.matches where id = '${
        uuid(matchIdValue)
      }' for update; select pg_sleep(30); commit`,
    ],
    clearEnv: true,
    env: {
      ...(database.password === "" ? {} : { PGPASSWORD: database.password }),
      PGAPPNAME: applicationName,
    },
    stdout: "piped",
    stderr: "piped",
  }).spawn();
  const completion = child.output();
  try {
    await waitForSqlValue(
      `select count(*) from pg_stat_activity where application_name = '${applicationName}' and state = 'active' and wait_event = 'PgSleep'`,
      "1",
      "match lock barrier acquired",
      10_000,
    );
  } catch (error) {
    child.kill("SIGTERM");
    await completion;
    throw error;
  }
  return {
    release: async () => {
      try {
        assert(
          await sqlScalar(
            `select pg_cancel_backend(pid) from pg_stat_activity where application_name = '${applicationName}'`,
          ) === "t",
          "match lock barrier cancellation",
        );
      } finally {
        const result = await completion;
        assert(!result.success, "match lock barrier released");
      }
    },
  };
}

async function assertMatchLockAvailable(
  matchIdValue: string,
  message: string,
): Promise<void> {
  await sql(
    `begin; select 1 from public.matches where id = '${
      uuid(matchIdValue)
    }' for update nowait; rollback`,
  );
  console.log(`PASS ${message}`);
}

function edge(
  session: Session | null,
  name: string,
  body: Json,
): Promise<EdgeResult> {
  return rawEdge(session, name, JSON.stringify(body));
}

async function rawEdge(
  session: Session | null,
  name: string,
  body: string,
): Promise<EdgeResult> {
  const started = performance.now();
  if (name === "delete-account" && session) {
    deletionHashes.add(await sha256(session.access_token));
  }
  const response = await fetch(`${apiUrl}/functions/v1/${name}`, {
    method: "POST",
    headers: {
      apikey: anonKey,
      authorization: session
        ? `Bearer ${session.access_token}`
        : `Bearer ${anonKey}`,
      "content-type": "application/json",
    },
    body,
  });
  const text = await response.text();
  let parsed: unknown;
  try {
    parsed = JSON.parse(text);
  } catch {
    throw new Error(`non-JSON ${name} response`);
  }
  if (!isJson(parsed)) throw new Error(`invalid ${name} response`);
  const result = {
    status: response.status,
    body: parsed,
    bytes: new TextEncoder().encode(text).byteLength,
    elapsedMs: Math.round(performance.now() - started),
  };
  if (name === "create-match" && response.status === 200) {
    createdMatches.add(matchId(result));
  }
  edgeMetrics.push({ name, bytes: result.bytes, elapsedMs: result.elapsedMs });
  return result;
}

async function subscribeToMatchSignal(
  user: TestUser,
  matchId: string,
): Promise<{ next: Promise<Json>; close: () => Promise<unknown> }> {
  await user.client.realtime.setAuth(user.session.access_token);
  const channel = user.client.channel(`integration-${crypto.randomUUID()}`);
  let received!: (payload: Json) => void;
  const event = new Promise<Json>((resolve) => {
    received = resolve;
  });
  channel.on(
    "postgres_changes",
    {
      event: "UPDATE",
      schema: "public",
      table: "matches",
      filter: `id=eq.${matchId}`,
    },
    (change) => received(isJson(change.new) ? change.new : {}),
  );
  await subscribe(channel);
  await waitForRealtimeSubscription(user.id);
  const next = Promise.race([
    event,
    delay(10_000).then(() => {
      throw new Error("realtime signal timeout");
    }),
  ]);
  return {
    next,
    close: async () => {
      await user.client.removeChannel(channel);
      user.client.realtime.disconnect();
    },
  };
}

async function subscribe(channel: RealtimeChannel): Promise<void> {
  await new Promise<void>((resolve, reject) => {
    channel.subscribe((status) => {
      if (status === "SUBSCRIBED") resolve();
      if (status === "CHANNEL_ERROR" || status === "TIMED_OUT") {
        reject(new Error("realtime subscription failed"));
      }
    });
  });
}

async function waitForRealtimeSubscription(userId: string): Promise<void> {
  const deadline = performance.now() + 10_000;
  while (performance.now() < deadline) {
    if (
      await sqlScalar(
        `select count(*) from realtime.subscription where entity = 'public.matches'::regclass and claims ->> 'sub' = '${
          uuid(userId)
        }'`,
      ) !== "0"
    ) return;
    await delay(100);
  }
  throw new Error("realtime subscription readiness timeout");
}

async function sql(
  statement: string,
  applicationName?: string,
): Promise<string> {
  const command = new Deno.Command("psql", {
    args: [
      ...database.args,
      "-XAtq",
      "-v",
      "ON_ERROR_STOP=1",
      "-c",
      statement,
    ],
    clearEnv: true,
    env: {
      ...(database.password === "" ? {} : { PGPASSWORD: database.password }),
      ...(applicationName === undefined ? {} : { PGAPPNAME: applicationName }),
    },
    stdout: "piped",
    stderr: "piped",
  });
  const result = await command.output();
  if (!result.success) throw new Error("database fixture command failed");
  return new TextDecoder().decode(result.stdout).trim();
}

async function sqlScalar(statement: string): Promise<string> {
  return (await sql(statement)).split("\n").at(-1)?.trim() ?? "";
}

async function waitForSqlValue(
  statement: string,
  expected: string,
  message: string,
  timeoutMilliseconds = 4_000,
): Promise<void> {
  const deadline = performance.now() + timeoutMilliseconds;
  while (performance.now() < deadline) {
    if (await sqlScalar(statement) === expected) return;
    await delay(25);
  }
  throw new Error(message);
}

async function scenario(
  name: string,
  action: () => Promise<void>,
): Promise<void> {
  const started = performance.now();
  await action();
  console.log(`PASS ${name} ${Math.round(performance.now() - started)}ms`);
}

// Keep proof useful without logging private boards, answers, codes or identifiers.
function captureSummary(label: string, snapshot: Json): void {
  console.log(`FIXTURE ${label} ${
    JSON.stringify({
      status: nested(snapshot, "match", "status"),
      currentRound: nested(snapshot, "match", "current_round"),
      roundState: nested(snapshot, "round", "state"),
      revealedCount: array(snapshot.revealed_rounds).length,
      isFinal: isJson(snapshot.standings) ? snapshot.standings.is_final : null,
    })
  }`);
}

function data(result: EdgeResult): Json {
  assert(result.status === 200, "expected success response");
  const value = result.body.data;
  assert(isJson(value), "success envelope");
  return value;
}

function matchId(result: EdgeResult): string {
  const value = data(result).match_id;
  assert(typeof value === "string", "match ID response");
  return uuid(value);
}

function guessBody(matchId: string, requestId: string, word: string): Json {
  return {
    client_build: 1,
    match_id: uuid(matchId),
    round_number: 1,
    request_id: uuid(requestId),
    guess: word,
  };
}

function assertError(result: EdgeResult, status: number, code: string): void {
  assert(result.status === status, `${code} status`);
  assert(
    nestedString(result.body, "error", "code") === code,
    `${code} envelope`,
  );
}

function assertOpponentBoardHidden(snapshot: Json): void {
  const players = array(nested(snapshot, "round", "players"));
  assert(
    players.length === 0 ||
      players.some((player) => isJson(player) && player.board === null),
    "opponent board hidden",
  );
}

function assertAllBoardsVisible(snapshot: Json): void {
  const players = array(nested(snapshot, "round", "players"));
  assert(players.length === 2, "revealed player count");
  assert(
    players.every((player) => isJson(player) && Array.isArray(player.board)),
    "revealed boards visible",
  );
}

function assertDeletedMemberIdentity(snapshot: Json): void {
  const members = array(snapshot.members).filter(isJson);
  assert(members.length === 2, "survivor member count");
  assert(
    members.every((member) => typeof member.is_self === "boolean"),
    "Boolean member identity",
  );
  assert(
    members.filter((member) => member.is_self === true).length === 1,
    "exactly one self",
  );
  const deleted = members.find((member) => member.is_deleted === true);
  assert(deleted?.is_self === false, "deleted member is not self");
}

function nested(value: Json, first: string, second: string): unknown {
  const child = value[first];
  return isJson(child) ? child[second] : undefined;
}

function nestedString(value: Json, first: string, second: string): string {
  const result = nested(value, first, second);
  assert(typeof result === "string", `${first}.${second}`);
  return result;
}

function array(value: unknown): unknown[] {
  assert(Array.isArray(value), "expected array");
  return value;
}

function uuid(value: string): string {
  if (
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(
      value,
    )
  ) {
    throw new Error("invalid fixture UUID");
  }
  return value;
}

function sqlLiteral(value: string): string {
  if (!/^[a-z]{5}$/.test(value)) throw new Error("invalid fixture word");
  return value;
}

function required(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`missing ${name}`);
  return value;
}

function localApiUrl(value: string): string {
  const url = new URL(value);
  assert(
    url.protocol === "http:" &&
      ["127.0.0.1", "localhost"].includes(url.hostname) &&
      url.port === "54321",
    "API_URL must target local Supabase",
  );
  return url.origin;
}

function localDatabase(value: string): LocalDatabase {
  const url = new URL(value);
  assert(
    ["postgres:", "postgresql:"].includes(url.protocol) &&
      ["127.0.0.1", "localhost"].includes(url.hostname) &&
      url.port === "54322" &&
      url.pathname === "/postgres",
    "DB_URL must target local Supabase",
  );
  const password = decodeURIComponent(url.password);
  const args = [
    "--host",
    url.hostname,
    "--port",
    url.port,
    "--username",
    decodeURIComponent(url.username),
    "--dbname",
    decodeURIComponent(url.pathname.slice(1)),
  ];
  assert(
    !args.includes(value) && !args.includes("--password"),
    "database password argv",
  );
  return { args, password };
}

function isJson(value: unknown): value is Json {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

async function sha256(value: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  );
  return Array.from(
    new Uint8Array(digest),
    (byte) => byte.toString(16).padStart(2, "0"),
  ).join("");
}

function delay(milliseconds: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}
