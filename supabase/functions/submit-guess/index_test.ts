import {
  type DatabaseResult,
  type Dependencies,
  type JsonObject,
} from "../_shared/command.ts";
import { makeHandler } from "./index.ts";

const USER_ID = "40000000-0000-0000-0000-000000000001";
const MATCH_ID = "50000000-0000-0000-0000-000000000001";
const REQUEST_ID = "60000000-0000-0000-0000-000000000001";
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
  return new Request("http://localhost/submit-guess", {
    method: "POST",
    headers,
    body: JSON.stringify(body),
  });
}

function postRaw(raw: string, contentType = "application/json"): Request {
  return new Request("http://localhost/submit-guess", {
    method: "POST",
    headers: {
      authorization: `Bearer ${TOKEN}`,
      "content-type": contentType,
    },
    body: raw,
  });
}

function get(): Request {
  return new Request("http://localhost/submit-guess", {
    method: "GET",
    headers: {
      authorization: `Bearer ${TOKEN}`,
      "content-type": "application/json",
    },
  });
}

function validBody(): JsonObject {
  return {
    client_build: 7,
    match_id: MATCH_ID,
    round_number: 1,
    request_id: REQUEST_ID,
    guess: "crane",
  };
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

Deno.test("submits a guess through the submit_guess RPC", async () => {
  const invoked = await invoke({
    request: post(validBody()),
    rpcResults: [ok({ match_id: MATCH_ID, round_number: 1, correct: false })],
  });

  assertEquals(invoked.response.status, 200);
  assertEquals(invoked.body, {
    data: { match_id: MATCH_ID, round_number: 1, correct: false },
  });
  assertEquals(invoked.rpcCalls.length, 1);
  assertEquals(invoked.rpcCalls[0].name, "submit_guess");
  assertEquals(invoked.rpcCalls[0].parameters, {
    p_user_id: USER_ID,
    p_client_build: 7,
    p_match_id: MATCH_ID,
    p_round_number: 1,
    p_request_id: REQUEST_ID,
    p_guess: "CRANE",
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
    name: "rejects a body missing guess",
    request: () =>
      post({
        client_build: 7,
        match_id: MATCH_ID,
        round_number: 1,
        request_id: REQUEST_ID,
      }),
    status: 400,
    code: "internal_error",
    rpcCalls: 0,
    authenticateCalls: 0,
  },
  {
    name: "rejects a body with an extra key",
    request: () => post({ ...validBody(), hint: true }),
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
    request: () => postRaw(JSON.stringify(validBody()), "text/plain"),
    status: 400,
    code: "internal_error",
    rpcCalls: 0,
    authenticateCalls: 0,
  },
  {
    name: "rejects a missing bearer token",
    request: () => post(validBody(), null),
    status: 401,
    code: "not_authenticated",
    rpcCalls: 0,
    authenticateCalls: 0,
  },
  {
    name: "rejects an unknown bearer",
    request: () => post(validBody()),
    authenticate: null,
    status: 401,
    code: "not_authenticated",
    rpcCalls: 0,
    authenticateCalls: 1,
  },
  {
    name: "rejects an outdated build",
    request: () => post({ ...validBody(), client_build: 0 }),
    status: 426,
    code: "client_update_required",
    rpcCalls: 0,
    authenticateCalls: 0,
  },
  {
    name: "rejects a malformed match_id",
    request: () => post({ ...validBody(), match_id: "not-a-uuid" }),
    status: 400,
    code: "internal_error",
    rpcCalls: 0,
    authenticateCalls: 0,
  },
  {
    name: "rejects a malformed request_id",
    request: () => post({ ...validBody(), request_id: "not-a-uuid" }),
    status: 400,
    code: "internal_error",
    rpcCalls: 0,
    authenticateCalls: 0,
  },
  {
    name: "rejects a non-current round",
    request: () => post({ ...validBody(), round_number: 2 }),
    status: 409,
    code: "round_not_active",
    rpcCalls: 0,
    authenticateCalls: 0,
  },
  {
    name: "rejects a non-alphabetic guess",
    request: () => post({ ...validBody(), guess: "abc12" }),
    status: 400,
    code: "invalid_guess_format",
    rpcCalls: 0,
    authenticateCalls: 0,
  },
  {
    name: "maps a typed word-not-accepted error",
    request: () => post(validBody()),
    rpcResults: [domainError("word_not_accepted")],
    status: 422,
    code: "word_not_accepted",
    rpcCalls: 1,
    authenticateCalls: 1,
  },
  {
    name: "maps a typed request-conflict error",
    request: () => post(validBody()),
    rpcResults: [domainError("request_conflict")],
    status: 409,
    code: "request_conflict",
    rpcCalls: 1,
    authenticateCalls: 1,
  },
  {
    name: "maps a PostgREST failure to internal_error",
    request: () => post(validBody()),
    rpcResults: [transportError()],
    status: 500,
    code: "internal_error",
    rpcCalls: 1,
    authenticateCalls: 1,
  },
  {
    name: "rejects a malformed success envelope",
    request: () => post(validBody()),
    rpcResults: [{ data: { points: 3 }, error: null }],
    status: 500,
    code: "internal_error",
    rpcCalls: 1,
    authenticateCalls: 1,
  },
  {
    name: "rejects an unknown error code",
    request: () => post(validBody()),
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
