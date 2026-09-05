import { createClient } from "@supabase/supabase-js";

export const ERROR_MESSAGES = {
  not_authenticated: "Sign in and try again.",
  not_a_match_member: "You are not part of this match.",
  match_not_joinable: "This match cannot be joined.",
  room_full: "This room is full.",
  room_expired: "This room has expired.",
  not_host: "Only the creator can start this match.",
  not_enough_players: "Two players are required.",
  round_not_active: "This round is not active.",
  round_already_finished: "This round has already finished.",
  invalid_guess_format: "Enter a five-letter word.",
  word_not_accepted: "That word is not accepted.",
  rate_limited: "Too many attempts. Try again shortly.",
  client_update_required: "Update the app to continue.",
  request_conflict: "This request conflicts with an earlier attempt.",
  internal_error: "Something went wrong. Try again.",
} as const;

export type ErrorCode = keyof typeof ERROR_MESSAGES;
export type JsonObject = Record<string, unknown>;

const ERROR_STATUS: Record<ErrorCode, number> = {
  not_authenticated: 401,
  not_a_match_member: 403,
  match_not_joinable: 409,
  room_full: 409,
  room_expired: 410,
  not_host: 403,
  not_enough_players: 409,
  round_not_active: 409,
  round_already_finished: 409,
  invalid_guess_format: 400,
  word_not_accepted: 422,
  rate_limited: 429,
  client_update_required: 426,
  request_conflict: 409,
  internal_error: 500,
};

const JSON_HEADERS = {
  "cache-control": "no-store",
  "content-type": "application/json; charset=utf-8",
};
const MAX_REQUEST_BYTES = 2048;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const CLIENT_OPTIONS = {
  auth: {
    autoRefreshToken: false,
    detectSessionInUrl: false,
    persistSession: false,
  },
};

export interface DatabaseResult {
  data: unknown;
  error: unknown;
}

export interface DeleteResult {
  error: { code?: string; status?: number } | null;
}

export interface ServiceClient {
  rpc(name: string, parameters: JsonObject): Promise<DatabaseResult>;
  deleteUser(userId: string, shouldSoftDelete: false): Promise<DeleteResult>;
}

export interface Dependencies {
  authenticate(token: string): Promise<string | null>;
  createService(): ServiceClient;
}

export interface ParsedRequest {
  body: JsonObject;
  token: string;
}

export interface AuthorizedRequest {
  service: ServiceClient;
  userId: string;
}

export type Result<T> =
  | { ok: true; value: T }
  | { ok: false; response: Response };

export function errorResponse(
  code: ErrorCode,
  status = ERROR_STATUS[code],
  headers: HeadersInit = {},
): Response {
  return new Response(
    JSON.stringify({ error: { code, message: ERROR_MESSAGES[code] } }),
    { status, headers: { ...JSON_HEADERS, ...headers } },
  );
}

export function successResponse(data: JsonObject): Response {
  return new Response(JSON.stringify({ data }), {
    status: 200,
    headers: JSON_HEADERS,
  });
}

export async function safely(
  action: () => Promise<Response>,
): Promise<Response> {
  try {
    return await action();
  } catch {
    return errorResponse("internal_error");
  }
}

export async function readRequest(
  request: Request,
): Promise<Result<ParsedRequest>> {
  if (request.method !== "POST") {
    return {
      ok: false,
      response: errorResponse("internal_error", 405, { allow: "POST" }),
    };
  }

  const authorization = request.headers.get("authorization");
  const bearer = authorization?.match(/^Bearer ([^\s]{1,4096})$/);
  if (!bearer) {
    return { ok: false, response: errorResponse("not_authenticated") };
  }

  if (
    !request.headers.get("content-type")?.toLowerCase().startsWith(
      "application/json",
    )
  ) {
    return { ok: false, response: errorResponse("internal_error", 400) };
  }

  const declaredLength = request.headers.get("content-length");
  if (declaredLength !== null) {
    const length = Number(declaredLength);
    if (!Number.isInteger(length) || length < 0 || length > MAX_REQUEST_BYTES) {
      return { ok: false, response: errorResponse("internal_error", 400) };
    }
  }

  const text = await readBoundedText(request, MAX_REQUEST_BYTES);
  if (text === null || text.length === 0) {
    return { ok: false, response: errorResponse("internal_error", 400) };
  }

  let body: unknown;
  try {
    body = JSON.parse(text);
  } catch {
    return { ok: false, response: errorResponse("internal_error", 400) };
  }
  if (!isObject(body)) {
    return { ok: false, response: errorResponse("internal_error", 400) };
  }
  return { ok: true, value: { body, token: bearer[1] } };
}

async function readBoundedText(
  request: Request,
  maximumBytes: number,
): Promise<string | null> {
  const reader = request.body?.getReader();
  if (!reader) return null;

  const chunks: Uint8Array[] = [];
  let length = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      length += value.byteLength;
      if (length > maximumBytes) {
        try {
          await reader.cancel();
        } catch {
          // The size violation owns the stable client response even if cancellation fails.
        }
        return null;
      }
      chunks.push(value);
    }
  } finally {
    reader.releaseLock();
  }

  const bytes = new Uint8Array(length);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  try {
    return new TextDecoder("utf-8", { fatal: true }).decode(bytes);
  } catch {
    return null;
  }
}

export async function authorize(
  token: string,
  supplied?: Dependencies,
): Promise<Result<AuthorizedRequest>> {
  const dependencies = supplied ?? productionDependencies();
  const userId = await dependencies.authenticate(token);
  if (userId === null || !isUuid(userId)) {
    return { ok: false, response: errorResponse("not_authenticated") };
  }
  return {
    ok: true,
    value: { service: dependencies.createService(), userId },
  };
}

export function databaseEnvelope(result: DatabaseResult): Response {
  const parsed = databaseData(result);
  return parsed.ok ? successResponse(parsed.value) : parsed.response;
}

export function databaseData(result: DatabaseResult): Result<JsonObject> {
  if (result.error !== null || !isObject(result.data)) {
    return { ok: false, response: errorResponse("internal_error") };
  }
  const keys = Object.keys(result.data);
  if (keys.length !== 1) {
    return { ok: false, response: errorResponse("internal_error") };
  }
  if (keys[0] === "data" && isObject(result.data.data)) {
    return { ok: true, value: result.data.data };
  }
  if (keys[0] === "error" && isObject(result.data.error)) {
    const code = result.data.error.code;
    if (typeof code === "string" && code in ERROR_MESSAGES) {
      return { ok: false, response: errorResponse(code as ErrorCode) };
    }
  }
  return { ok: false, response: errorResponse("internal_error") };
}

export function exactKeys(body: JsonObject, keys: readonly string[]): boolean {
  const actual = Object.keys(body);
  return actual.length === keys.length &&
    keys.every((key) => actual.includes(key));
}

export function clientBuild(value: unknown): number | null {
  return typeof value === "number" && Number.isInteger(value) && value >= 1 &&
      value <= 2147483647
    ? value
    : null;
}

export function isUuid(value: unknown): value is string {
  return typeof value === "string" && UUID.test(value);
}

export function joinCode(value: unknown): string | null {
  if (
    typeof value !== "string" || value.length !== 6 ||
    !/^[A-Za-z2-9]+$/.test(value)
  ) {
    return null;
  }
  const normalized = value.toUpperCase();
  return /^[A-HJ-NP-Z2-9]{6}$/.test(normalized) ? normalized : null;
}

export function guess(value: unknown): string | null {
  return typeof value === "string" && /^[A-Za-z]{5}$/.test(value)
    ? value.toUpperCase()
    : null;
}

export function productionDependencies(): Dependencies {
  const url = requiredEnvironment("SUPABASE_URL");
  const publishableKey = environmentKey(
    "SUPABASE_PUBLISHABLE_KEYS",
    "SUPABASE_PUBLISHABLE_KEY",
    "SUPABASE_ANON_KEY",
  );
  const authClient = createClient(url, publishableKey, CLIENT_OPTIONS);

  return {
    async authenticate(token) {
      const { data, error } = await authClient.auth.getUser(token);
      return error === null && data.user ? data.user.id : null;
    },
    createService() {
      const secretKey = environmentKey(
        "SUPABASE_SECRET_KEYS",
        "SUPABASE_SECRET_KEY",
        "SUPABASE_SERVICE_ROLE_KEY",
      );
      const client = createClient(url, secretKey, CLIENT_OPTIONS);
      return {
        async rpc(name, parameters) {
          const { data, error } = await client.rpc(name, parameters);
          return { data, error };
        },
        async deleteUser(userId, shouldSoftDelete) {
          const { error } = await client.auth.admin.deleteUser(
            userId,
            shouldSoftDelete,
          );
          return { error };
        },
      };
    },
  };
}

function isObject(value: unknown): value is JsonObject {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function requiredEnvironment(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new Error("missing function environment");
  return value;
}

function environmentKey(
  mapName: string,
  singleName: string,
  legacyName: string,
): string {
  const map = Deno.env.get(mapName);
  if (map) {
    const value = JSON.parse(map)?.default;
    if (typeof value === "string" && value.length > 0) return value;
    throw new Error("invalid function environment");
  }
  return Deno.env.get(singleName) ?? requiredEnvironment(legacyName);
}
