import {
  type DatabaseResult,
  type Dependencies,
  type JsonObject,
  type ServiceClient,
} from "../_shared/command.ts";
import { makeHandler } from "./index.ts";

const USER_ID = "40000000-0000-0000-0000-000000000001";
const TOKEN = "signed-bearer-token";

interface RpcStep {
  name: string;
  data: JsonObject;
}

interface Harness {
  dependencies: Dependencies;
  rpcCalls: Array<{ name: string; parameters: JsonObject }>;
  deletedUsers: string[];
  get authenticateCalls(): number;
}

function harness(
  steps: RpcStep[],
  options: {
    authenticatedUser?: string | null;
    deleteError?: { code?: string; status?: number } | null;
  } = {},
): Harness {
  const rpcCalls: Array<{ name: string; parameters: JsonObject }> = [];
  const deletedUsers: string[] = [];
  let authenticateCalls = 0;
  const service: ServiceClient = {
    async rpc(name, parameters): Promise<DatabaseResult> {
      rpcCalls.push({ name, parameters });
      const step = steps.shift();
      assert(step !== undefined, `unexpected RPC ${name}`);
      assertEquals(name, step.name);
      return await Promise.resolve({ data: step.data, error: null });
    },
    async deleteUser(userId) {
      deletedUsers.push(userId);
      return await Promise.resolve({ error: options.deleteError ?? null });
    },
  };
  return {
    dependencies: {
      async authenticate() {
        authenticateCalls += 1;
        return await Promise.resolve(
          options.authenticatedUser === undefined
            ? USER_ID
            : options.authenticatedUser,
        );
      },
      createService: () => service,
    },
    rpcCalls,
    deletedUsers,
    get authenticateCalls() {
      return authenticateCalls;
    },
  };
}

function request(): Request {
  return new Request("http://localhost/delete-account", {
    method: "POST",
    headers: {
      authorization: `Bearer ${TOKEN}`,
      "content-type": "application/json",
    },
    body: JSON.stringify({ client_build: 1 }),
  });
}

async function body(response: Response): Promise<JsonObject> {
  return await response.json() as JsonObject;
}

Deno.test("deletes app data and Auth before completing the receipt", async () => {
  const test = harness([
    { name: "account_deletion_status", data: { data: { status: "missing" } } },
    {
      name: "begin_account_deletion",
      data: { data: { status: "pending", user_id: USER_ID } },
    },
    {
      name: "complete_account_deletion",
      data: { data: { status: "completed" } },
    },
  ]);

  const response = await makeHandler(test.dependencies)(request());

  assertEquals(response.status, 200);
  assertEquals(await body(response), { data: { deleted: true } });
  assertEquals(test.authenticateCalls, 1);
  assertEquals(test.deletedUsers, [USER_ID]);
  assertEquals(test.rpcCalls.map((call) => call.name), [
    "account_deletion_status",
    "begin_account_deletion",
    "complete_account_deletion",
  ]);
  const tokenHash = test.rpcCalls[0].parameters.p_token_hash;
  assert(typeof tokenHash === "string" && /^[0-9a-f]{64}$/.test(tokenHash));
  assert(tokenHash !== TOKEN, "raw bearer must not enter the database");
  assertEquals(test.rpcCalls[1].parameters.p_token_hash, tokenHash);
  assertEquals(test.rpcCalls[2].parameters.p_token_hash, tokenHash);
});

Deno.test("confirms a completed deletion with the same stale bearer", async () => {
  const test = harness([
    {
      name: "account_deletion_status",
      data: { data: { status: "completed" } },
    },
  ], { authenticatedUser: null });

  const response = await makeHandler(test.dependencies)(request());

  assertEquals(response.status, 200);
  assertEquals(await body(response), { data: { deleted: true } });
  assertEquals(test.authenticateCalls, 0);
  assertEquals(test.deletedUsers, []);
});

Deno.test("resumes a pending deletion before Auth identity removal", async () => {
  const test = harness([
    {
      name: "account_deletion_status",
      data: { data: { status: "pending", user_id: USER_ID } },
    },
    {
      name: "complete_account_deletion",
      data: { data: { status: "completed" } },
    },
  ], { authenticatedUser: null });

  const response = await makeHandler(test.dependencies)(request());

  assertEquals(response.status, 200);
  assertEquals(test.authenticateCalls, 0);
  assertEquals(test.deletedUsers, [USER_ID]);
});

Deno.test("completes a pending receipt after Auth was already deleted", async () => {
  const test = harness([
    {
      name: "account_deletion_status",
      data: { data: { status: "pending" } },
    },
    {
      name: "complete_account_deletion",
      data: { data: { status: "completed" } },
    },
  ], { authenticatedUser: null });

  const response = await makeHandler(test.dependencies)(request());

  assertEquals(response.status, 200);
  assertEquals(test.authenticateCalls, 0);
  assertEquals(test.deletedUsers, []);
});

Deno.test("keeps a pending receipt retryable when Auth deletion fails", async () => {
  const test = harness([
    {
      name: "account_deletion_status",
      data: { data: { status: "pending", user_id: USER_ID } },
    },
  ], { deleteError: { code: "provider_failure" } });

  const response = await makeHandler(test.dependencies)(request());

  assertEquals(response.status, 500);
  assertEquals(test.deletedUsers, [USER_ID]);
  assertEquals(test.rpcCalls.length, 1);
});

Deno.test("requires current authentication when no receipt exists", async () => {
  const test = harness([
    { name: "account_deletion_status", data: { data: { status: "missing" } } },
  ], { authenticatedUser: null });

  const response = await makeHandler(test.dependencies)(request());

  assertEquals(response.status, 401);
  assertEquals(test.authenticateCalls, 1);
  assertEquals(test.deletedUsers, []);
});

function assert(
  condition: unknown,
  message = "assertion failed",
): asserts condition {
  if (!condition) throw new Error(message);
}

function assertEquals(actual: unknown, expected: unknown): void {
  const left = JSON.stringify(actual);
  const right = JSON.stringify(expected);
  if (left !== right) throw new Error(`expected ${right}, received ${left}`);
}
