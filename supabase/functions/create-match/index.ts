import {
  authorize,
  clientBuild,
  databaseEnvelope,
  type Dependencies,
  errorResponse,
  exactKeys,
  isUuid,
  readRequest,
  safely,
} from "../_shared/command.ts";

export function makeHandler(dependencies?: Dependencies) {
  return (request: Request) =>
    safely(async () => {
      const parsed = await readRequest(request);
      if (!parsed.ok) return parsed.response;
      const { body, token } = parsed.value;
      const build = clientBuild(body.client_build);
      const keys = build !== null && build >= 2
        ? ["client_build", "request_id", "round_count"]
        : ["client_build", "request_id"];
      if (
        !exactKeys(body, keys) &&
        !(build === null && exactKeys(body, [...keys, "round_count"]))
      ) {
        return errorResponse("internal_error", 400);
      }
      if (build === null) {
        return errorResponse("client_update_required");
      }
      if (!isUuid(body.request_id)) {
        return errorResponse("internal_error", 400);
      }
      if (build >= 2 && ![1, 3, 5].includes(body.round_count as number)) {
        return errorResponse("invalid_match_configuration");
      }
      const authorized = await authorize(token, dependencies);
      if (!authorized.ok) return authorized.response;
      return databaseEnvelope(
        await authorized.value.service.rpc("create_match", {
          p_user_id: authorized.value.userId,
          p_client_build: build,
          p_ip_hash: null,
          p_request_id: body.request_id,
          ...(build >= 2 ? { p_round_count: body.round_count } : {}),
        }),
      );
    });
}

export const handle = makeHandler();
export default { fetch: handle };
