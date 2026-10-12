"""Hermetic selector/admission controls; never starts the integration runtime."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
DRIVER = ROOT / "scripts/run_live_match_integration.sh"
PARSER = ROOT / "scripts/live_integration_selection.sh"
NAMES = "deletion-receipt,daily,product-1,product-3,product-5,mixed-3,cron-1,cron-3,deletion-1,deletion-3,backend"


class SelectionTests(unittest.TestCase):
    def parse(self, *args):
        return subprocess.run(
            ["bash", "-c", 'set -eu; source "$1"; shift; parse_integration_selection "$@"; printf "%s|%s|%s" "$selection_action" "$selection_scope" "$selected_scenarios"', "selector", str(PARSER), *args],
            capture_output=True, text=True, check=False,
        )

    def test_full_default_and_focused_membership(self):
        self.assertEqual(self.parse().stdout, f"run|full|{NAMES}")
        result = self.parse("--scenarios", "daily,product-3")
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "run|focused|daily,product-3")
        self.assertEqual(self.parse("--scenarios", NAMES).stdout, f"run|focused|{NAMES}")
        for name in NAMES.split(","):
            self.assertEqual(self.parse("--scenarios", name).returncode, 0)

    def test_invalid_selections_refuse_before_runtime(self):
        for args in [("",), ("--scenarios",), ("--scenarios", ""),
                     ("--scenarios", ",daily"), ("--scenarios", "daily,"),
                     ("--scenarios", "daily,,backend"), ("--scenarios", "daily,unknown"),
                     ("--scenarios", "daily,daily"), ("--scenarios", "daily\nunknown"),
                     ("--unknown",), ("--help", "--scenarios", "daily")]:
            with self.subTest(args=args):
                result = subprocess.run(["bash", str(DRIVER), *args], capture_output=True, text=True)
                self.assertEqual(result.returncode, 2)
                self.assertNotIn("PROOF_DIRECTORY", result.stdout)
                self.assertNotIn("UNAVAILABLE", result.stderr)

    def test_help_list_and_admission_do_not_invoke_runtime_tools(self):
        with tempfile.TemporaryDirectory() as directory:
            marker = Path(directory) / "runtime-called"
            for name in ["git", "npx", "mktemp", "xcrun", "xcodebuild", "curl", "psql"]:
                stub = Path(directory) / name
                stub.write_text(f'#!/bin/sh\nprintf called >> "{marker}"\nexit 99\n')
                stub.chmod(0o755)
            env = dict(os.environ, PATH=f"{directory}:{os.environ['PATH']}")
            env.pop("GRIDRACE_LOCAL_INTEGRATION", None)
            for args in [("--help",), ("--list-scenarios",), (), ("--scenarios", "daily")]:
                result = subprocess.run(["bash", str(DRIVER), *args], env=env, capture_output=True, text=True)
                self.assertEqual(result.returncode, 0 if args and args[0] in ("--help", "--list-scenarios") else 2)
                self.assertFalse(marker.exists())
            env.update(GRIDRACE_LOCAL_INTEGRATION="1", GRIDRACE_INTEGRATION_STACK_DIR=f"{directory}/missing-stack")
            result = subprocess.run(["bash", str(DRIVER), "--scenarios", "daily"], env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 2)
            self.assertFalse(marker.exists(), "branch must not control admission before exact stack guards")

    def test_backend_entrypoint_info_and_invalid_selection_need_no_permissions(self):
        command = ["deno", "run", "--cached-only", "--config",
                   str(ROOT / "supabase/functions/deno.json"),
                   str(ROOT / "supabase/tests/integration/live_slice_test.ts")]
        for args in [("--help",), ("--list-scenarios",), ("--scenarios", ""),
                     ("--scenarios", "auth-create,unknown"), ("--help", "extra")]:
            with self.subTest(args=args):
                result = subprocess.run(command + list(args), capture_output=True, text=True)
                self.assertEqual(result.returncode, 0 if len(args) == 1 else 1)
                if len(args) > 1:
                    self.assertIn("REFUSED", result.stderr)
                self.assertNotIn("NotCapable", result.stderr)
                self.assertNotIn("missing GRIDRACE", result.stderr)


if __name__ == "__main__":
    unittest.main()
