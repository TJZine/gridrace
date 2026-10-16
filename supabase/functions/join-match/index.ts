import {
  authorize,
  clientBuild,
  databaseEnvelope,
  type Dependencies,
  errorResponse,
  exactKeys,
  isUuid,
  joinCode,
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
      if (build === null || build < 3) {
        return errorResponse("client_update_required");
      }
      if (
        !exactKeys(body, [
          "client_build",
          "request_id",
          "join_code",
          "expected_match_id",
        ]) ||
        !isUuid(body.request_id) ||
        (body.expected_match_id !== null && !isUuid(body.expected_match_id))
      ) {
        return errorResponse("internal_error", 400);
      }
      const code = joinCode(body.join_code);
      if (code === null) return errorResponse("match_not_joinable");
      const authorized = await authorize(token, dependencies);
      if (!authorized.ok) return authorized.response;
      return databaseEnvelope(
        await authorized.value.service.rpc("join_match", {
          p_user_id: authorized.value.userId,
          p_client_build: build,
          p_join_code: code,
          p_ip_hash: null,
          p_request_id: body.request_id,
          p_expected_match_id: body.expected_match_id,
        }),
      );
    });
}

export const handle = makeHandler();
export default { fetch: handle };
