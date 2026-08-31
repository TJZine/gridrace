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
      if (!exactKeys(body, ["client_build", "match_id"])) {
        return errorResponse("internal_error", 400);
      }
      const build = clientBuild(body.client_build);
      if (build === null) return errorResponse("client_update_required");
      if (!isUuid(body.match_id)) return errorResponse("internal_error", 400);
      const authorized = await authorize(token, dependencies);
      if (!authorized.ok) return authorized.response;
      return databaseEnvelope(
        await authorized.value.service.rpc("match_snapshot", {
          p_user_id: authorized.value.userId,
          p_client_build: build,
          p_match_id: body.match_id,
        }),
      );
    });
}

export const handle = makeHandler();
export default { fetch: handle };
