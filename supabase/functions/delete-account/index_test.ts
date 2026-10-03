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
  data: unknown;
  error?: unknown;
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
      return await Promise.resolve({
        data: step.data,
        error: step.error ?? null,
      });
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
  return requestWith({ client_build: 1 }, TOKEN);
}

function requestWith(body: unknown, token: string | null): Request {
  const headers: Record<string, string> = {
    "content-type": "application/json",
  };
  if (token !== null) headers.authorization = `Bearer ${token}`;
  return new Request("http://localhost/delete-account", {
    method: "POST",
    headers,
    body: JSON.stringify(body),
  });
}

function requestRaw(raw: string): Request {
  return new Request("http://localhost/delete-account", {
    method: "POST",
    headers: {
      authorization: `Bearer ${TOKEN}`,
      "content-type": "application/json",
    },
    body: raw,
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

interface InputFailure {
  name: string;
  request: () => Request;
  status: number;
  code: string;
}

const inputFailures: InputFailure[] = [
  {
    name: "rejects a non-JSON deletion body",
    request: () => requestRaw("{invalid"),
    status: 400,
    code: "internal_error",
  },
  {
    name: "rejects a deletion body with the wrong keys",
    request: () => requestWith({}, TOKEN),
    status: 400,
    code: "internal_error",
  },
  {
    name: "rejects an outdated deletion build",
    request: () => requestWith({ client_build: 0 }, TOKEN),
    status: 426,
    code: "client_update_required",
  },
  {
    name: "rejects a deletion request without a bearer",
    request: () => requestWith({ client_build: 1 }, null),
    status: 401,
    code: "not_authenticated",
  },
];

for (const failure of inputFailures) {
  Deno.test(failure.name, async () => {
    const test = harness([]);

    const response = await makeHandler(test.dependencies)(failure.request());

    assertEquals(response.status, failure.status);
    assertEquals(
      ((await body(response)).error as JsonObject)?.code,
      failure.code,
    );
    assertEquals(test.rpcCalls.length, 0);
    assertEquals(test.authenticateCalls, 0);
  });
}

Deno.test("maps a typed begin_account_deletion error without touching Auth", async () => {
  const test = harness([
    { name: "account_deletion_status", data: { data: { status: "missing" } } },
    {
      name: "begin_account_deletion",
      data: { error: { code: "rate_limited" } },
    },
  ]);

  const response = await makeHandler(test.dependencies)(request());

  assertEquals(response.status, 429);
  assertEquals(await body(response), {
    error: {
      code: "rate_limited",
      message: "Too many attempts. Try again shortly.",
    },
  });
  assertEquals(test.authenticateCalls, 1);
  assertEquals(test.deletedUsers, []);
});

Deno.test("surfaces a PostgREST status failure as internal_error", async () => {
  const test = harness([
    {
      name: "account_deletion_status",
      data: null,
      error: { code: "PGRST301", message: "row-level security" },
    },
  ], { authenticatedUser: null });

  const response = await makeHandler(test.dependencies)(request());

  assertEquals(response.status, 500);
  assertEquals(test.authenticateCalls, 0);
  assertEquals(test.deletedUsers, []);
});

Deno.test("rejects an unknown deletion receipt status", async () => {
  const test = harness([
    {
      name: "account_deletion_status",
      data: { data: { status: "archived" } },
    },
  ], { authenticatedUser: null });

  const response = await makeHandler(test.dependencies)(request());

  assertEquals(response.status, 500);
  assertEquals(test.authenticateCalls, 0);
  assertEquals(test.deletedUsers, []);
});

Deno.test("rejects a begin receipt issued for a different user", async () => {
  const test = harness([
    { name: "account_deletion_status", data: { data: { status: "missing" } } },
    {
      name: "begin_account_deletion",
      data: {
        data: {
          status: "pending",
          user_id: "40000000-0000-0000-0000-000000000002",
        },
      },
    },
  ]);

  const response = await makeHandler(test.dependencies)(request());

  assertEquals(response.status, 500);
  assertEquals(test.authenticateCalls, 1);
  assertEquals(test.deletedUsers, []);
});

Deno.test("maps a typed complete_account_deletion error after Auth removal", async () => {
  const test = harness([
    {
      name: "account_deletion_status",
      data: { data: { status: "pending", user_id: USER_ID } },
    },
    {
      name: "complete_account_deletion",
      data: { error: { code: "request_conflict" } },
    },
  ], { authenticatedUser: null });

  const response = await makeHandler(test.dependencies)(request());

  assertEquals(response.status, 409);
  assertEquals(await body(response), {
    error: {
      code: "request_conflict",
      message: "This request conflicts with an earlier attempt.",
    },
  });
  assertEquals(test.authenticateCalls, 0);
  assertEquals(test.deletedUsers, [USER_ID]);
  assertEquals(test.rpcCalls.map((call) => call.name), [
    "account_deletion_status",
    "complete_account_deletion",
  ]);
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
