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
      if (build === null || build < 3) {
        return errorResponse("client_update_required");
      }
      if (
        !exactKeys(body, ["client_build", "match_id", "round_number"])
      ) return errorResponse("internal_error", 400);
      if (!isUuid(body.match_id)) return errorResponse("internal_error", 400);
      if (
        (typeof body.round_number !== "number" ||
          !Number.isInteger(body.round_number) || body.round_number < 1 ||
          body.round_number > 5)
      ) {
        return errorResponse("round_not_active");
      }
      const authorized = await authorize(token, dependencies);
      if (!authorized.ok) return authorized.response;
      return databaseEnvelope(
        await authorized.value.service.rpc("start_match", {
          p_user_id: authorized.value.userId,
          p_client_build: build,
          p_match_id: body.match_id,
          p_round_number: body.round_number,
        }),
      );
    });
}

export const handle = makeHandler();
export default { fetch: handle };
