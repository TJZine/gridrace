import {
  authorize,
  clientBuild,
  databaseEnvelope,
  type Dependencies,
  errorResponse,
  exactKeys,
  readRequest,
  safely,
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
      const authorized = await authorize(token, dependencies);
      if (!authorized.ok) return authorized.response;
      return databaseEnvelope(
        await authorized.value.service.rpc("create_match", {
          p_user_id: authorized.value.userId,
          p_client_build: build,
          p_ip_hash: null,
        }),
      );
    });
}

export const handle = makeHandler();
export default { fetch: handle };
