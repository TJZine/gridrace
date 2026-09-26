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
  await Promise.all(
    [...createdUsers].map((userId) =>
      admin.auth.admin.deleteUser(userId, false)
    ),
  );
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
): Promise<void> {
  assert(
    Number.isInteger(seconds) && seconds > 0 && seconds <= 5,
    "lock duration",
  );
  await sql(
    `begin; select 1 from public.matches where id = '${
      uuid(matchIdValue)
    }' for update; select pg_sleep(${seconds}); commit`,
  );
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

async function sql(statement: string): Promise<string> {
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
    env: database.password === "" ? {} : { PGPASSWORD: database.password },
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

async function scenario(
  name: string,
  action: () => Promise<void>,
): Promise<void> {
  const started = performance.now();
  await action();
  console.log(`PASS ${name} ${Math.round(performance.now() - started)}ms`);
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
