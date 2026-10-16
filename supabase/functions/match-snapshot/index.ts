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
      if (build === null || build < 3) {
        return errorResponse("client_update_required");
      }
      if (!isUuid(body.match_id)) return errorResponse("internal_error", 400);
      const authorized = await authorize(token, dependencies);
      if (!authorized.ok) return authorized.response;
      const parameters = {
        p_user_id: authorized.value.userId,
        p_client_build: build,
        p_match_id: body.match_id,
      };
      for (let attempt = 0; attempt < 3; attempt++) {
        const result = await authorized.value.service.rpc(
          "match_snapshot",
          parameters,
        );
        const error = result.error as
          | { code?: string; message?: string }
          | null;
        if (
          error?.code === "40001" &&
          error.message === "snapshot_roster_changed" && attempt < 2
        ) continue;
        return databaseEnvelope(result);
      }
      return errorResponse("internal_error");
    });
}

export const handle = makeHandler();
export default { fetch: handle };
