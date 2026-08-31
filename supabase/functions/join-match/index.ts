import {
  authorize,
  clientBuild,
  databaseEnvelope,
  type Dependencies,
  errorResponse,
  exactKeys,
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
      if (!exactKeys(body, ["client_build", "join_code"])) {
        return errorResponse("internal_error", 400);
      }
      const build = clientBuild(body.client_build);
      if (build === null) return errorResponse("client_update_required");
      const code = joinCode(body.join_code);
      if (code === null) return errorResponse("match_not_joinable", 400);
      const authorized = await authorize(token, dependencies);
      if (!authorized.ok) return authorized.response;
      return databaseEnvelope(
        await authorized.value.service.rpc("join_match", {
          p_user_id: authorized.value.userId,
          p_client_build: build,
          p_join_code: code,
          p_ip_hash: null,
        }),
      );
    });
}

export const handle = makeHandler();
export default { fetch: handle };
