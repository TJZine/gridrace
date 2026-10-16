import {
  backendScenarioID,
  backendScenarios,
  parseBackendSelection,
} from "./scenario_selection.ts";

function assert(value: unknown): asserts value {
  if (!value) throw new Error("selector expectation failed");
}

Deno.test("default backend selection preserves all registered independent scenarios", () => {
  const selected = parseBackendSelection([]);
  assert(selected.action === "run" && !selected.focused);
  assert(selected.names.length === 21);
  assert(new Set(selected.names).size === selected.names.length);
  assert(selected.names.join(",") === backendScenarios.join(","));
});

Deno.test("focused backend selection, harmless help and list", () => {
  const selected = parseBackendSelection([
    "--scenarios",
    "auth-create,current-rounds-standings",
  ]);
  assert(selected.focused && selected.names.length === 2);
  assert(parseBackendSelection(["--help"]).action === "help");
  assert(parseBackendSelection(["--list-scenarios"]).action === "list");
});

Deno.test("empty unknown duplicate and malformed backend arguments refuse", () => {
  for (
    const args of [
      [""],
      ["--scenarios"],
      ["--scenarios", ""],
      ["--scenarios", "auth-create,"],
      ["--scenarios", ",auth-create"],
      ["--scenarios", "auth-create,,current-cron"],
      ["--scenarios", "auth-create,unknown"],
      ["--scenarios", "auth-create,auth-create"],
      ["--scenarios", "auth-create\nunknown"],
      ["--help", "--scenarios", "auth-create"],
      ["--unknown"],
    ]
  ) {
    let refused = false;
    try {
      parseBackendSelection(args);
    } catch {
      refused = true;
    }
    assert(refused);
  }
});

Deno.test("backend registry covers actual driver actions exactly", async () => {
  const source = await Deno.readTextFile(
    new URL("./live_slice_test.ts", import.meta.url),
  );
  const names = [...source.matchAll(/await scenario\(\s*"([^"]+)"/g)]
    .map((match) => backendScenarioID(match[1]));
  assert(names.join(",") === backendScenarios.join(","));
});
