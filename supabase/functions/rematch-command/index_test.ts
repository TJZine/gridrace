import { type JsonObject } from "../_shared/command.ts";
import { createCommandInvoker } from "../_shared/command_test_fixture.ts";
import { makeHandler } from "./index.ts";
const USER = "40000000-0000-0000-0000-000000000001";
const MATCH = "50000000-0000-0000-0000-000000000001";
const REQUEST = "60000000-0000-0000-0000-000000000001";
const invoke = createCommandInvoker(makeHandler, USER);
function body(): JsonObject {
  return {
    client_build: 3,
    request_id: REQUEST,
    predecessor_match_id: MATCH,
    generation: 1,
    action: "offer",
    expected_participation_epoch: 0,
  };
}
function post(data: unknown) {
  return new Request("http://localhost/rematch-command", {
    method: "POST",
    headers: {
      authorization: "Bearer token",
      "content-type": "application/json",
    },
    body: JSON.stringify(data),
  });
}
function equal(actual: unknown, expected: unknown) {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(
      `expected ${JSON.stringify(expected)}; got ${JSON.stringify(actual)}`,
    );
  }
}
for (const action of ["offer", "accept", "cancel", "decline"]) {
  Deno.test(`rematch ${action} maps exact identity and epoch`, async () => {
    const data = {
      predecessor_match_id: MATCH,
      generation: 1,
      state: "offered",
      successor_match_id: null,
    };
    const result = await invoke({
      request: post({ ...body(), action }),
      rpcResults: [{ data: { data }, error: null }],
    });
    equal(result.response.status, 200);
    equal(result.rpcCalls, [{
      name: "rematch_command",
      parameters: {
        p_user_id: USER,
        p_client_build: 3,
        p_request_id: REQUEST,
        p_predecessor_match_id: MATCH,
        p_generation: 1,
        p_action: action,
        p_expected_participation_epoch: 0,
      },
    }]);
    equal(result.body, { data });
  });
}
for (
  const [name, change] of Object.entries({
    old_build: { client_build: 2 },
    extra_key: { extra: true },
    invalid_request: { request_id: "UPPER" },
    bad_match: { predecessor_match_id: null },
    zero_generation: { generation: 0 },
    wide_generation: { generation: 2147483648 },
    fractional_generation: { generation: 1.1 },
    negative_epoch: { expected_participation_epoch: -1 },
    unsafe_epoch: { expected_participation_epoch: 9007199254740992 },
    bad_action: { action: "resume" },
  })
) {
  Deno.test(`rematch rejects ${name} before authorization`, async () => {
    const result = await invoke({ request: post({ ...body(), ...change }) });
    equal(result.response.status, name === "old_build" ? 426 : 400);
    equal(result.authenticateCalls, 0);
    equal(result.rpcCalls, []);
  });
}
for (
  const [code, status] of [
    ["rematch_unavailable", 409],
    ["rematch_expired", 410],
    ["participation_changed", 409],
    ["answer_pool_unavailable", 409],
    ["request_conflict", 409],
    ["rate_limited", 429],
  ] as const
) {
  Deno.test(`rematch safe ${code} mapping`, async () => {
    const result = await invoke({
      request: post(body()),
      rpcResults: [{
        data: { error: { code, message: "private diagnostic" } },
        error: null,
      }],
    });
    equal(result.response.status, status);
    equal((result.body.error as JsonObject).code, code);
    if (JSON.stringify(result.body).includes("private diagnostic")) {
      throw new Error("leaked database message");
    }
  });
}
