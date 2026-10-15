import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
DRIVER = ROOT / "scripts/run_live_match_integration.sh"
PARSER = ROOT / "scripts/live_integration_selection.sh"
NAMES = "deletion-receipt,daily,product-1,product-3,product-5,mixed-3,cron-1,cron-3,deletion-1,deletion-3,friends-1,friends-3,friends-5,snapshot-1,friends-signal,friends-invitation,friends-closure,friends-3-race,backend"


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

    def test_friends_artifact_plan_keeps_predecessor_successor_and_rollback_distinct(self):
        invocations = []
        for pair, count in enumerate([1, 3, 5], 1):
            for process in ["host", "guest"]:
                invocations.append(("friends", count, pair, "predecessor", 1, process, process))
                for phase in ["predecessor", "successor"]:
                    for target in range(1 if phase == "successor" else 2, count + 1):
                        invocations.append(("friends", count, pair, phase, target, f"advance-{process}", process))
                for role in ["friends-both", "friends-recover", "friends-resume"]:
                    invocations.append(("friends", count, pair, "predecessor", count, role, process))
        for process in ["host", "guest"]:
            invocations.append(("friends", 1, 4, "predecessor", 1, process, process))
        paths = []
        for invocation in invocations:
            result = subprocess.run(["bash", "-c", 'source "$1"; shift; integration_client_log_basename "$@"',
                                     "artifact", str(PARSER), *map(str, invocation)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0)
            paths.append(result.stdout)
        self.assertEqual(len(paths), len(set(paths)), "No log or corresponding xcresult may be reused")
        self.assertTrue(all(path.endswith(".log") for path in paths))

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

    def test_actual_cleanup_rejects_incomplete_and_nounset_runs_even_if_exit_trap_sees_zero(self):
        source = DRIVER.read_text()
        cleanup = source[source.index("cleanup() {"):source.index("trap cleanup EXIT")]
        for trigger, completed, expected in [("true", 1, 0), ("true", 0, 1),
                                             ('printf "%s" "$UNDEFINED_COMPLETION_SENTINEL"', 0, 1)]:
            with tempfile.TemporaryDirectory() as directory:
                prefix = r"""
set -euo pipefail
work_dir=$1
host_pid=''; guest_pid=''; third_pid=''; failed_guess=''; cron_restore_required=0
run_completed=$2
baseline='{"auth":0,"matches":0}'
baseline_receipts='[]'
declare -a created_users=() created_matches=() proof_simulators=()
sql_scalar() {
  case $1 in
    *jsonb_build_object*) printf '%s' "$baseline" ;;
    *account_deletion_receipts*) printf '%s' "$baseline_receipts" ;;
    *) printf '%s' "$baseline" ;;
  esac
}
check_lock() { return 0; }
"""
                code = prefix + cleanup + "\ntrap cleanup EXIT\n" + trigger
                result = subprocess.run(["bash", "-c", code, "completion-control", directory, str(completed)],
                                        capture_output=True, text=True)
                self.assertEqual(result.returncode, expected, result.stderr)
                status = (Path(directory) / "cleanup-status.txt").read_text()
                self.assertIn("cleanup_failed=0", status)
                self.assertIn(f"run_completed={completed}", status)
                self.assertEqual("did not reach" in result.stderr, completed == 0)

    def test_actual_scheduler_pause_restores_after_applied_pause_reports_failure(self):
        source = DRIVER.read_text()
        cleanup = source[source.index("cleanup() {"):source.index("trap cleanup EXIT")]
        snapshot = source[source.index("if integration_selected snapshot-1; then") :]
        pause = snapshot[snapshot.index("\n") + 1:snapshot.index("  start_pair cron 1")]
        with tempfile.TemporaryDirectory() as directory:
            prefix = r"""
set -euo pipefail
work_dir=$1
host_pid=''; guest_pid=''; third_pid=''; failed_guess=''; cron_restore_required=0
cron_job_id=''; cron_baseline_active=''; run_completed=0
baseline='{"auth":0,"matches":0}'
baseline_receipts='[]'
declare -a created_users=() created_matches=() proof_simulators=() installed_simulators=()
printf t > "$work_dir/active"
sql_scalar() {
  printf '%s\n' "$1" >> "$work_dir/sql-queries"
  case $1 in
    "select count(*) from cron.job "*) printf 1 ;;
    "select jobid from cron.job "*) printf 41 ;;
    "select active from cron.job where jobid=41 and username=current_user") cat "$work_dir/active" ;;
    "select cron.alter_job(41, active:=false)")
      printf f > "$work_dir/active"
      printf pause-applied > "$work_dir/pause-applied"
      return 17 ;; # The mutation committed, but dispatch reports a lost result.
    "select cron.alter_job(41, active:=true)") printf t > "$work_dir/active" ;;
    "update private.live_feature_configuration set allow_new_rematches=false") return 0 ;;
    *jsonb_build_object*) printf '%s' "$baseline" ;;
    *account_deletion_receipts*) printf '%s' "$baseline_receipts" ;;
    *) return 99 ;;
  esac
}
check_lock() { return 0; }
"""
            code = prefix + cleanup + "\ntrap cleanup EXIT\n" + pause
            result = subprocess.run(["bash", "-c", code, "pause-result-loss", directory],
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, 17, result.stderr)
            proof = Path(directory)
            self.assertTrue((proof / "pause-applied").exists())
            self.assertEqual((proof / "active").read_text(), "t")
            queries = (proof / "sql-queries").read_text().splitlines()
            pause_query = "select cron.alter_job(41, active:=false)"
            restore_query = "select cron.alter_job(41, active:=true)"
            self.assertEqual(queries.count(restore_query), 1)
            self.assertLess(queries.index(pause_query), queries.index(restore_query))
            self.assertEqual(queries[queries.index(restore_query) + 1],
                             "select active from cron.job where jobid=41 and username=current_user")
            self.assertEqual((proof / "cleanup-status.txt").read_text(),
                             "cleanup_failed=0\nrun_completed=0\n")

    def test_disposable_log_gate_rejects_skips_and_inspection_errors_with_cleanup(self):
        source = DRIVER.read_text()

        def function(name):
            start = source.index(f"{name}() {{")
            end = source.index("\n}\n", start) + 3
            return source[start:end]

        method = "testLocalSupabaseTwoClientSyncAndDeletionWhenConfigured"
        marker = "PASS disposable Daily two-client sync and deletion"
        for case, log, scanner_error, succeeds in [
            ("passed-only", f"{method} passed\n{marker}\n", False, True),
            ("passed-plus-skipped", f"{method} passed\n{method} skipped\n{marker}\n", False, False),
            ("missing-positive", f"{method} skipped\n{marker}\n", False, False),
            ("scanner-error", f"{method} passed\n{marker}\n", True, False),
        ]:
            with self.subTest(case=case), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                (root / "fixture.log").write_text(log)
                script = r'''
set -euo pipefail
work_dir=$1
host_simulator=owned-simulator
run_tag=dummy-run
receipt_name=dummy-receipt
API_URL=http://127.0.0.1:1
ANON_KEY=dummy-public-key
host_pid=""; guest_pid=""; third_pid=""; failed_guess=""; cron_restore_required=0
run_completed=1
baseline='{"auth":0,"matches":0}'
baseline_receipts='[]'
SERVICE_ROLE_KEY=dummy-service-key
DB_URL=dummy-db-url
declare -a created_users=() created_matches=() proof_simulators=(owned-simulator) installed_simulators=(owned-simulator)
xcode_flags=(-disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile -skipPackageUpdates)
derived_data=$work_dir
package_cache=$work_dir
create_user() {
  fixture_user_id=owned-user; fixture_email=dummy@example.test; fixture_password=dummy
  created_users+=("$fixture_user_id")
}
write_receipt() { :; }
env() { cat "$work_dir/fixture.log"; }
xcrun() {
  printf '%s\n' "$*" >> "$work_dir/runtime-operations.txt"
  if [[ $1 == simctl && $2 == get_app_container ]]; then printf '%s\n' "$work_dir/client-container"; fi
}
scan_client_credentials() { [[ $1 == "$work_dir/client-container" ]]; }
sql_scalar() {
  printf '%s\n' "$1" >> "$work_dir/sql-operations.txt"
  case $1 in
    *jsonb_build_object*) printf '%s\n' "$baseline" ;;
    *account_deletion_receipts*) printf '%s\n' "$baseline_receipts" ;;
    *) printf '0\n' ;;
  esac
}
check_lock() { :; }
'''
                if scanner_error:
                    script += r'''
rg() {
  if [[ $1 == -qi ]]; then
    echo 'private scanner diagnostic' >&2
    return 2
  fi
  command rg "$@"
}
'''
                script += function("cleanup") + "\ntrap cleanup EXIT\n"
                script += function("run_disposable_daily_test") + "\n"
                script += f"run_disposable_daily_test GridRaceTests/DailySyncTests/{method} daily\n"
                script += f"rg -q '{marker}' \"$work_dir/daily.log\"\n"
                result = subprocess.run(["bash", "-c", script, "log-gate", directory],
                                        capture_output=True, text=True)
                self.assertEqual(result.returncode, 0 if succeeds else 1, result.stdout + result.stderr)
                self.assertEqual((root / "cleanup-status.txt").read_text(), "cleanup_failed=0\nrun_completed=1\n")
                self.assertIn("delete from auth.users where id='owned-user'",
                              (root / "sql-operations.txt").read_text())
                self.assertIn("delete owned-simulator", (root / "runtime-operations.txt").read_text())
                self.assertNotIn("private scanner diagnostic", result.stderr)
                self.assertNotIn(directory, result.stderr)
                self.assertEqual("PASS disposable daily Auth deletion verified by host" in result.stdout,
                                 succeeds, result.stdout + result.stderr)

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
