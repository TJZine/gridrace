import {
  clientBuild,
  databaseData,
  type Dependencies,
  errorResponse,
  exactKeys,
  isUuid,
  productionDependencies,
  readRequest,
  safely,
  type ServiceClient,
  successResponse,
} from "../_shared/command.ts";

export function makeHandler(dependencies?: Dependencies) {
  return (request: Request) =>
    safely(async () => {
      const parsed = await readRequest(request);
      if (!parsed.ok) return parsed.response;
      const { body, token } = parsed.value;
      if (!exactKeys(body, ["client_build"])) {
        return errorResponse("internal_error", 400);
      }
      const build = clientBuild(body.client_build);
      if (build === null) {
        return errorResponse("client_update_required");
      }

      const runtime = dependencies ?? productionDependencies();
      const service = runtime.createService();
      const tokenHash = await sha256(token);
      const receipt = databaseData(
        await service.rpc("account_deletion_status", {
          p_token_hash: tokenHash,
        }),
      );
      if (!receipt.ok) return receipt.response;

      if (receipt.value.status === "completed") {
        return successResponse({ deleted: true });
      }
      if (receipt.value.status === "pending") {
        const userId = receipt.value.user_id;
        if (userId !== undefined && !isUuid(userId)) {
          return errorResponse("internal_error");
        }
        return await deleteIdentityAndComplete(
          service,
          tokenHash,
          userId as string | undefined,
        );
      }
      if (receipt.value.status !== "missing") {
        return errorResponse("internal_error");
      }

      const userId = await runtime.authenticate(token);
      if (!isUuid(userId)) return errorResponse("not_authenticated");

      const prepared = databaseData(
        await service.rpc("begin_account_deletion", {
          p_user_id: userId,
          p_client_build: build,
          p_token_hash: tokenHash,
        }),
      );
      if (!prepared.ok) return prepared.response;
      if (prepared.value.status === "completed") {
        return successResponse({ deleted: true });
      }
      if (
        prepared.value.status !== "pending" ||
        prepared.value.user_id !== userId
      ) return errorResponse("internal_error");

      return await deleteIdentityAndComplete(service, tokenHash, userId);
    });
}

async function deleteIdentityAndComplete(
  service: ServiceClient,
  tokenHash: string,
  userId?: string,
): Promise<Response> {
  if (userId !== undefined) {
    const { error } = await service.deleteUser(userId, false);
    if (error !== null && error.code !== "user_not_found") {
      return errorResponse("internal_error");
    }
  }

  const completed = databaseData(
    await service.rpc("complete_account_deletion", {
      p_token_hash: tokenHash,
    }),
  );
  if (!completed.ok) return completed.response;
  return completed.value.status === "completed"
    ? successResponse({ deleted: true })
    : errorResponse("internal_error");
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

export const handle = makeHandler();
export default { fetch: handle };
