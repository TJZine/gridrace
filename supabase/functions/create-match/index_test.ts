import {
  type DatabaseResult,
  type Dependencies,
  type JsonObject,
} from "../_shared/command.ts";
import { makeHandler } from "./index.ts";

const USER_ID = "40000000-0000-0000-0000-000000000001";
const MATCH_ID = "50000000-0000-0000-0000-000000000001";
const TOKEN = "signed-bearer-token";

interface RpcCall {
  name: string;
  parameters: JsonObject;
}

interface Invocation {
  request: Request;
  authenticate?: string | null;
  rpcResults?: DatabaseResult[];
}

interface Invoked {
  response: Response;
  body: JsonObject;
  rpcCalls: RpcCall[];
  authenticateCalls: number;
}

async function invoke(invocation: Invocation): Promise<Invoked> {
  const rpcCalls: RpcCall[] = [];
  const queued = [...(invocation.rpcResults ?? [])];
  let authenticateCalls = 0;
  const dependencies: Dependencies = {
    async authenticate() {
      authenticateCalls += 1;
      const user = invocation.authenticate === undefined
        ? USER_ID
        : invocation.authenticate;
      return await Promise.resolve(user);
    },
    createService: () => ({
      async rpc(name: string, parameters: JsonObject) {
        rpcCalls.push({ name, parameters });
        const result = queued.shift();
        if (!result) throw new Error(`unexpected RPC ${name}`);
        return await Promise.resolve(result);
      },
      deleteUser() {
        return Promise.reject(new Error("unexpected deleteUser"));
      },
    }),
  };
  const response = await makeHandler(dependencies)(invocation.request);
  return {
    response,
    body: await response.json() as JsonObject,
    rpcCalls,
    authenticateCalls,
  };
}

function post(body: unknown, token: string | null = TOKEN): Request {
  const headers: Record<string, string> = {
    "content-type": "application/json",
  };
  if (token !== null) headers.authorization = `Bearer ${token}`;
  return new Request("http://localhost/create-match", {
    method: "POST",
    headers,
    body: JSON.stringify(body),
  });
}

function postRaw(raw: string, contentType = "application/json"): Request {
  return new Request("http://localhost/create-match", {
    method: "POST",
    headers: {
      authorization: `Bearer ${TOKEN}`,
      "content-type": contentType,
    },
    body: raw,
  });
}

function get(): Request {
  return new Request("http://localhost/create-match", {
    method: "GET",
    headers: {
      authorization: `Bearer ${TOKEN}`,
      "content-type": "application/json",
    },
  });
}

function ok(data: JsonObject): DatabaseResult {
  return { data: { data }, error: null };
}

function domainError(code: string): DatabaseResult {
  return { data: { error: { code } }, error: null };
}

function transportError(): DatabaseResult {
  return {
    data: null,
    error: { code: "PGRST301", message: "row-level security" },
  };
}

function codeOf(body: JsonObject): unknown {
  return (body.error as JsonObject | undefined)?.code;
}

Deno.test("creates a match through the create_match RPC", async () => {
  const invoked = await invoke({
    request: post({ client_build: 7 }),
    rpcResults: [ok({ match_id: MATCH_ID, join_code: "ABC234" })],
  });

  assertEquals(invoked.response.status, 200);
  assertEquals(invoked.body, {
    data: { match_id: MATCH_ID, join_code: "ABC234" },
  });
  assertEquals(invoked.rpcCalls.length, 1);
  assertEquals(invoked.rpcCalls[0].name, "create_match");
  assertEquals(invoked.rpcCalls[0].parameters, {
    p_user_id: USER_ID,
    p_client_build: 7,
    p_ip_hash: null,
  });
  assertEquals(invoked.authenticateCalls, 1);
});

interface FailureCase {
  name: string;
  request: () => Request;
  authenticate?: string | null;
  rpcResults?: DatabaseResult[];
  status: number;
  code: string;
  rpcCalls: number;
  authenticateCalls: number;
}

const failures: FailureCase[] = [
  {
    name: "rejects a non-JSON body",
    request: () => postRaw("{invalid"),
    status: 400,
    code: "internal_error",
    rpcCalls: 0,
    authenticateCalls: 0,
  },
  {
    name: "rejects a body missing client_build",
    request: () => post({}),
    status: 400,
    code: "internal_error",
    rpcCalls: 0,
    authenticateCalls: 0,
  },
  {
    name: "rejects a body with an extra key",
    request: () => post({ client_build: 7, match_id: MATCH_ID }),
    status: 400,
    code: "internal_error",
    rpcCalls: 0,
    authenticateCalls: 0,
  },
  {
    name: "rejects a non-POST method",
    request: () => get(),
    status: 405,
    code: "internal_error",
    rpcCalls: 0,
    authenticateCalls: 0,
  },
  {
    name: "rejects a non-JSON content type",
    request: () => postRaw(JSON.stringify({ client_build: 7 }), "text/plain"),
    status: 400,
    code: "internal_error",
    rpcCalls: 0,
    authenticateCalls: 0,
  },
  {
    name: "rejects a missing bearer token",
    request: () => post({ client_build: 7 }, null),
    status: 401,
    code: "not_authenticated",
    rpcCalls: 0,
    authenticateCalls: 0,
  },
  {
    name: "rejects an unknown bearer",
    request: () => post({ client_build: 7 }),
    authenticate: null,
    status: 401,
    code: "not_authenticated",
    rpcCalls: 0,
    authenticateCalls: 1,
  },
  {
    name: "rejects an outdated build",
    request: () => post({ client_build: 0 }),
    status: 426,
    code: "client_update_required",
    rpcCalls: 0,
    authenticateCalls: 0,
  },
  {
    name: "maps a typed rate-limit error",
    request: () => post({ client_build: 7 }),
    rpcResults: [domainError("rate_limited")],
    status: 429,
    code: "rate_limited",
    rpcCalls: 1,
    authenticateCalls: 1,
  },
  {
    name: "maps a PostgREST failure to internal_error",
    request: () => post({ client_build: 7 }),
    rpcResults: [transportError()],
    status: 500,
    code: "internal_error",
    rpcCalls: 1,
    authenticateCalls: 1,
  },
  {
    name: "rejects a malformed success envelope",
    request: () => post({ client_build: 7 }),
    rpcResults: [{ data: { match: {} }, error: null }],
    status: 500,
    code: "internal_error",
    rpcCalls: 1,
    authenticateCalls: 1,
  },
  {
    name: "rejects an unknown error code",
    request: () => post({ client_build: 7 }),
    rpcResults: [domainError("no_such_code")],
    status: 500,
    code: "internal_error",
    rpcCalls: 1,
    authenticateCalls: 1,
  },
];

for (const failure of failures) {
  Deno.test(failure.name, async () => {
    const invoked = await invoke({ ...failure, request: failure.request() });
    assertEquals(invoked.response.status, failure.status);
    assertEquals(codeOf(invoked.body), failure.code);
    assertEquals(invoked.rpcCalls.length, failure.rpcCalls);
    assertEquals(invoked.authenticateCalls, failure.authenticateCalls);
  });
}

function assertEquals(actual: unknown, expected: unknown): void {
  const left = JSON.stringify(actual);
  const right = JSON.stringify(expected);
  if (left !== right) throw new Error(`expected ${right}, received ${left}`);
}
