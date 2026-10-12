// Bounded backend proof units; each action owns its own setup and fixtures.
const scenarioIDs: Record<string, string> = {
  "gateway authentication and create retry": "auth-create",
  "RLS secrecy and realtime refresh signal": "rls-realtime",
  "competing joins converge": "competing-joins",
  "submission receipt concurrency domains": "receipt-concurrency",
  "finalizer and sixth guess converge": "finalizer-sixth-guess",
  "deadline lock wait uses transaction ordering": "deadline-ordering",
  "scheduled finalization and multi-match deletion share lock order":
    "finalizer-deletion-lock-order",
  "deletion races preserve canonical state": "deletion-races",
  "same-account join and deletion serialize": "join-deletion",
  "rate-counter concurrency completes without deadlock": "rate-concurrency",
  "lobby deletion isolation": "lobby-deletion",
  "deletion partial-stage recovery": "deletion-recovery",
  "v2 configured rounds, target concurrency, receipts and exact standings":
    "v2-rounds-standings",
  "v2 deletion matrix, future-start race and current-final preservation":
    "v2-deletion",
  "v2 deletion blocks queued next Start for either actor":
    "v2-queued-start-deletion",
  "v2 ordinary reveal waits for creator after scheduled Cron": "v2-cron",
};

export function backendScenarioID(description: string): string {
  const id = scenarioIDs[description];
  if (!id) throw new Error("unregistered backend scenario");
  return id;
}

export const backendScenarios = Object.values(scenarioIDs);

export function parseBackendSelection(args: string[]): {
  action: "run" | "help" | "list";
  names: string[];
  focused: boolean;
} {
  if (args.length === 0) {
    return { action: "run", names: [...backendScenarios], focused: false };
  }
  if (
    args.length === 1 &&
    (args[0] === "--help" || args[0] === "--list-scenarios")
  ) {
    return {
      action: args[0] === "--help" ? "help" : "list",
      names: [],
      focused: false,
    };
  }
  if (args.length !== 2 || args[0] !== "--scenarios") {
    throw new Error(
      "REFUSED: expected --scenarios NAME[,NAME...], --help or --list-scenarios",
    );
  }
  const names = args[1].split(",");
  if (
    names.some((name) => !backendScenarios.some((known) => known === name)) ||
    new Set(names).size !== names.length
  ) {
    throw new Error(
      "REFUSED: empty, unknown or duplicate backend scenario name",
    );
  }
  return { action: "run", names, focused: true };
}
