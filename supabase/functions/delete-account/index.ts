import {
  authorize,
  clientBuild,
  databaseData,
  type Dependencies,
  errorResponse,
  exactKeys,
  readRequest,
  safely,
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
      const authorized = await authorize(token, dependencies);
      if (!authorized.ok) return authorized.response;

      const prepared = databaseData(
        await authorized.value.service.rpc("delete_account", {
          p_user_id: authorized.value.userId,
          p_client_build: build,
        }),
      );
      if (!prepared.ok) return prepared.response;
      if (prepared.value.deleted !== true) {
        return errorResponse(
          "internal_error",
        );
      }

      const { error } = await authorized.value.service.deleteUser(
        authorized.value.userId,
        false,
      );
      if (error !== null && error.code !== "user_not_found") {
        return errorResponse("internal_error");
      }
      return successResponse({ deleted: true });
    });
}

export const handle = makeHandler();
export default { fetch: handle };
