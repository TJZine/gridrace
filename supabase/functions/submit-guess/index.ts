import {
  authorize,
  clientBuild,
  databaseEnvelope,
  type Dependencies,
  errorResponse,
  exactKeys,
  guess,
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
      if (
        !exactKeys(body, [
          "client_build",
          "match_id",
          "round_number",
          "request_id",
          "guess",
        ])
      ) return errorResponse("internal_error", 400);
      const build = clientBuild(body.client_build);
      if (build === null) return errorResponse("client_update_required");
      if (!isUuid(body.match_id) || !isUuid(body.request_id)) {
        return errorResponse("internal_error", 400);
      }
      if (body.round_number !== 1) return errorResponse("round_not_active");
      const normalizedGuess = guess(body.guess);
      if (normalizedGuess === null) {
        return errorResponse("invalid_guess_format");
      }
      const authorized = await authorize(token, dependencies);
      if (!authorized.ok) return authorized.response;
      return databaseEnvelope(
        await authorized.value.service.rpc("submit_guess", {
          p_user_id: authorized.value.userId,
          p_client_build: build,
          p_match_id: body.match_id,
          p_round_number: 1,
          p_request_id: body.request_id,
          p_guess: normalizedGuess,
          p_ip_hash: null,
        }),
      );
    });
}

export const handle = makeHandler();
export default { fetch: handle };
