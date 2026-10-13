import { productionDependencies } from "./command.ts";
import { handle as createMatch } from "../create-match/index.ts";
import { handle as deleteAccount } from "../delete-account/index.ts";

const userId = "11111111-1111-4111-8111-111111111111";
const token = "test-original-bearer";
const privateDetail = "dependency-secret-must-not-escape";
const origin = "https://auth-adapter.invalid";

function assertEquals(actual: unknown, expected: unknown): void {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(
      `expected ${JSON.stringify(expected)}, received ${
        JSON.stringify(actual)
      }`,
    );
  }
}

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      "content-type": "application/json",
      "x-supabase-api-version": "2024-01-01",
    },
  });
}

function rejection(status: number, code?: string): Response {
  return json({ code, message: privateDetail }, status);
}

function request(deletion = false): Request {
  return new Request(
    `${origin}/${deletion ? "delete-account" : "create-match"}`,
    {
      method: "POST",
      headers: {
        authorization: `Bearer ${token}`,
        "content-type": "application/json",
      },
      body: JSON.stringify(
        deletion ? { client_build: 1 } : {
          client_build: 1,
          request_id: "22222222-2222-4222-8222-222222222222",
        },
      ),
    },
  );
}

// Exercise production environment selection and the actual pinned SDK. The fetch
// replacement prevents network access; restore both globals even on an assertion failure.
async function withRuntime(
  respond: (url: string, init?: RequestInit) => Response | Promise<Response>,
  action: () => Promise<void>,
): Promise<void> {
  const originalGet = Deno.env.get;
  const originalFetch = globalThis.fetch;
  Deno.env.get = (name) =>
    ({
      SUPABASE_URL: origin,
      SUPABASE_PUBLISHABLE_KEY: "test-publishable-key",
      SUPABASE_SECRET_KEY: "test-service-key",
    } as Record<string, string>)[name];
  globalThis.fetch = (input, init) =>
    Promise.resolve(
      respond(input instanceof Request ? input.url : String(input), init),
    );
  try {
    await action();
  } finally {
    Deno.env.get = originalGet;
    globalThis.fetch = originalFetch;
  }
}

Deno.test("production Auth adapter remotely validates the original bearer before gameplay RPC", async () => {
  const calls: string[] = [];
  await withRuntime((url, init) => {
    calls.push(url);
    if (url === `${origin}/auth/v1/user`) {
      assertEquals(init?.method, "GET");
      assertEquals(
        new Headers(init?.headers).get("authorization"),
        `Bearer ${token}`,
      );
      return json({ id: userId });
    }
    assertEquals(url, `${origin}/rest/v1/rpc/create_match`);
    assertEquals(
      new Headers(init?.headers).get("authorization"),
      "Bearer test-service-key",
    );
    assertEquals(JSON.parse(String(init?.body)).p_user_id, userId);
    return json({ data: { match_id: userId } });
  }, async () => {
    const response = await createMatch(request());
    assertEquals(response.status, 200);
    assertEquals(await response.json(), { data: { match_id: userId } });
  });
  assertEquals(calls, [
    `${origin}/auth/v1/user`,
    `${origin}/rest/v1/rpc/create_match`,
  ]);
});

const failures: [string, () => Response, number][] = [
  ["invalid JWT", () => rejection(403, "bad_jwt"), 401],
  ["missing user", () => rejection(404, "user_not_found"), 401],
  ["banned user", () => rejection(403, "user_banned"), 401],
  ["missing remote session", () => rejection(400, "session_not_found"), 401],
  ["legacy credential rejection", () => rejection(401), 401],
  ["network failure", () => {
    throw new TypeError(privateDetail);
  }, 500],
  ["server failure", () => rejection(500, "unexpected_failure"), 500],
  ["gateway failure", () => new Response(privateDetail, { status: 502 }), 500],
  ["other server failure", () => rejection(599, "bad_jwt"), 500],
  ["quota failure", () => rejection(429, "over_request_rate_limit"), 500],
  [
    "quota with session error code",
    () => rejection(429, "session_not_found"),
    500,
  ],
  [
    "server with session error code",
    () => rejection(599, "session_not_found"),
    500,
  ],
  ["unknown Auth code", () => rejection(401, "future_unknown_failure"), 500],
  ["unexpected API failure", () => rejection(400, "unexpected_failure"), 500],
  [
    "malformed error JSON",
    () => new Response(privateDetail, { status: 401 }),
    500,
  ],
  ["malformed success JSON", () => new Response(privateDetail), 500],
  ["missing user ID", () => json({}), 500],
  ["invalid user ID", () => json({ id: "invalid" }), 500],
  ["null success", () => json(null), 500],
];

for (const [name, response, expectedStatus] of failures) {
  Deno.test(`production Auth ${name} returns safe ${expectedStatus} without gameplay RPC`, async () => {
    const calls: string[] = [];
    await withRuntime((url) => {
      calls.push(url);
      assertEquals(url, `${origin}/auth/v1/user`);
      return response();
    }, async () => {
      const result = await createMatch(request());
      assertEquals(result.status, expectedStatus);
      assertEquals(result.headers.get("cache-control"), "no-store");
      assertEquals(
        await result.json(),
        expectedStatus === 401
          ? {
            error: {
              code: "not_authenticated",
              message: "Sign in and try again.",
            },
          }
          : {
            error: {
              code: "internal_error",
              message: "Something went wrong. Try again.",
            },
          },
      );
    });
    assertEquals(calls, [`${origin}/auth/v1/user`]);
  });
}

Deno.test("production Auth adapter throws sanitized uncertainty to non-gameplay callers", async () => {
  await withRuntime(
    () => rejection(429, "over_request_rate_limit"),
    async () => {
      try {
        await productionDependencies().authenticate(token);
        throw new Error("expected adapter failure");
      } catch (error) {
        assertEquals(
          error instanceof Error && error.message,
          "authentication unavailable",
        );
      }
    },
  );
});

for (const state of ["completed", "pending", "missing"] as const) {
  Deno.test(`production deletion ${state} receipt preserves Auth outage behavior`, async () => {
    const calls: string[] = [];
    await withRuntime((url) => {
      calls.push(url);
      if (url.endsWith("/rpc/account_deletion_status")) {
        return json({
          data: {
            status: state,
            ...(state === "pending" ? { user_id: userId } : {}),
          },
        });
      }
      if (state === "missing") {
        assertEquals(url, `${origin}/auth/v1/user`);
        return rejection(503, "unexpected_failure");
      }
      if (url === `${origin}/auth/v1/admin/users/${userId}`) return json({});
      assertEquals(url, `${origin}/rest/v1/rpc/complete_account_deletion`);
      return json({ data: { status: "completed" } });
    }, async () => {
      const response = await deleteAccount(request(true));
      assertEquals(response.status, state === "missing" ? 500 : 200);
      assertEquals(
        await response.json(),
        state === "missing"
          ? {
            error: {
              code: "internal_error",
              message: "Something went wrong. Try again.",
            },
          }
          : { data: { deleted: true } },
      );
    });
    assertEquals(
      calls,
      state === "completed"
        ? [`${origin}/rest/v1/rpc/account_deletion_status`]
        : state === "pending"
        ? [
          `${origin}/rest/v1/rpc/account_deletion_status`,
          `${origin}/auth/v1/admin/users/${userId}`,
          `${origin}/rest/v1/rpc/complete_account_deletion`,
        ]
        : [
          `${origin}/rest/v1/rpc/account_deletion_status`,
          `${origin}/auth/v1/user`,
        ],
    );
  });
}
