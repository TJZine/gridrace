import { createCommandInvoker } from "./command_test_fixture.ts";
import { makeHandler as create } from "../create-match/index.ts";
import { makeHandler as join } from "../join-match/index.ts";
import { makeHandler as start } from "../start-match/index.ts";
import { makeHandler as submit } from "../submit-guess/index.ts";
import { makeHandler as snapshot } from "../match-snapshot/index.ts";
import { makeHandler as rematch } from "../rematch-command/index.ts";
const id = "40000000-0000-0000-0000-000000000001";
const commands = [
  { name: "create", handler: create, body: { request_id: id, round_count: 3 } },
  {
    name: "join",
    handler: join,
    body: { request_id: id, join_code: "ABC234", expected_match_id: null },
  },
  { name: "start", handler: start, body: { match_id: id, round_number: 1 } },
  {
    name: "submit",
    handler: submit,
    body: { request_id: id, match_id: id, round_number: 1, guess: "APPLE" },
  },
  { name: "snapshot", handler: snapshot, body: { match_id: id } },
  {
    name: "rematch",
    handler: rematch,
    body: {
      request_id: id,
      predecessor_match_id: id,
      generation: 1,
      action: "offer",
      expected_participation_epoch: 0,
    },
  },
];
for (const command of commands) {
  for (const client_build of [1, 2]) {
    Deno.test(`${command.name} rejects obsolete build ${client_build} before Auth/RPC`, async () => {
      const invoked = await createCommandInvoker(command.handler, id)({
        request: new Request("http://localhost/" + command.name, {
          method: "POST",
          headers: {
            authorization: "Bearer token",
            "content-type": "application/json",
          },
          body: JSON.stringify({ ...command.body, client_build }),
        }),
      });
      if (
        invoked.response.status !== 426 || invoked.authenticateCalls !== 0 ||
        invoked.rpcCalls.length !== 0
      ) throw new Error("obsolete command dispatched");
    });
  }
}
