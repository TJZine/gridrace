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
        !exactKeys(body, [
          "client_build",
          "request_id",
          "predecessor_match_id",
          "generation",
          "action",
          "expected_participation_epoch",
        ]) ||
        !isUuid(body.request_id) || !isUuid(body.predecessor_match_id) ||
        typeof body.generation !== "number" ||
        !Number.isInteger(body.generation) || body.generation < 1 ||
        body.generation > 2147483647 ||
        typeof body.expected_participation_epoch !== "number" ||
        !Number.isSafeInteger(body.expected_participation_epoch) ||
        body.expected_participation_epoch < 0 ||
        typeof body.action !== "string" ||
        !["offer", "accept", "cancel", "decline"].includes(body.action)
      ) {
        return errorResponse("internal_error", 400);
      }
      const authorized = await authorize(token, dependencies);
      if (!authorized.ok) return authorized.response;
      return databaseEnvelope(
        await authorized.value.service.rpc("rematch_command", {
          p_user_id: authorized.value.userId,
          p_client_build: build,
          p_request_id: body.request_id,
          p_predecessor_match_id: body.predecessor_match_id,
          p_generation: body.generation,
          p_action: body.action,
          p_expected_participation_epoch: body.expected_participation_epoch,
        }),
      );
    });
}
export const handle = makeHandler();
export default { fetch: handle };
