#!/usr/bin/env python3
"""Controlled receipt completion race on an exclusively leased local database.

GRIDRACE_LOCAL_INTEGRATION=1 DB_URL=<loopback URL> python3 -B \
    scripts/test_deletion_receipt_race.py [--expect-deadlock]

Run --expect-deadlock against the predecessor, then run without it after the
forward migration. A SHARE table-lock barrier lets both calls take their first
lock before group UPDATE proceeds. The old implementation holds distinct token
rows; the repair holds one operation lock and queues the other call before its
token lock. Separate-operation calls must both reach the table barrier, proving
the repair is not a global lock. Only unique owned receipts are created/deleted;
no Auth identities, table definitions, functions or migrations are changed.
"""

import argparse
import hashlib
import os
import subprocess
import time
import uuid
from urllib.parse import unquote, urlsplit


class Database:
    def __init__(self):
        if os.environ.get("GRIDRACE_LOCAL_INTEGRATION") != "1":
            raise RuntimeError("local integration opt-in required")
        url = urlsplit(os.environ.get("DB_URL", ""))
        if (url.scheme not in ("postgres", "postgresql")
                or url.hostname not in ("localhost", "127.0.0.1")
                or not url.port or url.path != "/postgres" or url.query or url.fragment):
            raise RuntimeError("DB_URL must identify a leased loopback postgres database")
        self.args = ["psql", "-XAtq", "-v", "ON_ERROR_STOP=1",
                     "-v", "VERBOSITY=sqlstate", "--host", url.hostname,
                     "--port", str(url.port), "--username", unquote(url.username or ""),
                     "--dbname", "postgres"]
        # Do not inherit service/pg connection overrides or pass secrets in argv.
        self.env = {"PATH": os.environ.get("PATH", ""),
                    "PGPASSWORD": unquote(url.password or ""), "PGCONNECT_TIMEOUT": "5"}

    def start(self, name):
        return subprocess.Popen(self.args, env={**self.env, "PGAPPNAME": name},
                                stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, text=True)

    def sql(self, statement):
        result = subprocess.run(self.args, env=self.env, input=statement,
                                capture_output=True, text=True, timeout=15)
        if result.returncode:
            # Receipt digests and server diagnostics are credential-derived data.
            raise RuntimeError("control SQL failed (diagnostics suppressed)")
        return result.stdout.strip()


def write(child, statement):
    child.stdin.write(statement + "\n")
    child.stdin.flush()


def wait_for(db, statement, expected):
    deadline = time.monotonic() + 8
    while time.monotonic() < deadline:
        if db.sql(statement) == str(expected):
            return
        time.sleep(0.05)
    raise RuntimeError("controlled lock barrier did not reach the required state")


def stop(child):
    if child.poll() is None:
        child.terminate()
        try:
            child.communicate(timeout=5)
        except subprocess.TimeoutExpired:
            child.kill()
            child.communicate(timeout=5)


def run_pair(db, prefix, tokens, expect_deadlock, separate=False):
    holder_name = prefix + "-holder"
    names = [prefix + "-a", prefix + "-b"]
    holder = db.start(holder_name)
    calls = []
    try:
        write(holder, "begin; set local statement_timeout='12s'; "
              "lock table private.account_deletion_receipts in share mode;")
        wait_for(db, f"""select count(*) from pg_locks l join pg_stat_activity a
            on a.pid=l.pid where a.application_name='{holder_name}'
            and l.relation='private.account_deletion_receipts'::regclass
            and l.mode='ShareLock' and l.granted;""", 1)
        for name, token in zip(names, tokens):
            child = db.start(name)
            calls.append(child)
            write(child, "set statement_timeout='12s'; set deadlock_timeout='100ms'; "
                  "set role service_role; "
                  f"select public.complete_account_deletion('{token}') #>> '{{data,status}}';\n\\q")
        # Every call must be blocked inside completion, not merely scheduled.
        name_list = ",".join(f"'{name}'" for name in names)
        wait_for(db, f"""select count(*) from pg_stat_activity
            where application_name in ({name_list}) and wait_event_type='Lock';""", 2)
        relation_waiters = db.sql(f"""select count(*) from pg_locks l
            join pg_stat_activity a on a.pid=l.pid
            where a.application_name in ({name_list}) and not l.granted
            and l.relation='private.account_deletion_receipts'::regclass
            and l.mode='RowExclusiveLock';""")
        advisory_waiters = db.sql(f"""select count(*) from pg_locks l
            join pg_stat_activity a on a.pid=l.pid
            where a.application_name in ({name_list}) and not l.granted
            and l.locktype='advisory';""")
        expected = ("2", "0") if separate or expect_deadlock else ("1", "1")
        if (relation_waiters, advisory_waiters) != expected:
            raise RuntimeError("calls did not establish the intended lock ordering")
        write(holder, "commit;\n\\q")
        holder.communicate(timeout=15)
        if holder.returncode:
            raise RuntimeError("barrier release failed")
        results = [child.communicate(timeout=15) for child in calls]
        completed = sum(child.returncode == 0 and output.strip() == "completed"
                        for child, (output, _) in zip(calls, results))
        deadlocks = sum(child.returncode != 0 and "40P01" in error
                        for child, (_, error) in zip(calls, results))
        if expect_deadlock:
            if (completed, deadlocks) != (1, 1):
                raise RuntimeError("predecessor did not reproduce one completion and one 40P01")
        elif completed != 2 or deadlocks:
            raise RuntimeError("both completion calls must succeed without deadlock")
        print(f"PASS {'separate operations' if separate else 'rotated tokens'}: "
              f"{completed} completed, {deadlocks} deadlock; observed lock barrier")
    finally:
        # Closing these sessions rolls back/releases run-owned locks on failures.
        for child in calls:
            stop(child)
        stop(holder)


def revalidation_control(db, prefix, token, operation, replacement=None):
    holder = db.start(prefix + "-holder")
    call = db.start(prefix + "-call")
    try:
        write(holder, "begin; set local statement_timeout='12s'; "
              f"select pg_advisory_xact_lock(hashtextextended('{operation}',2));")
        wait_for(db, f"""select count(*) from pg_locks l join pg_stat_activity a
            on a.pid=l.pid where a.application_name='{prefix}-holder'
            and l.locktype='advisory' and l.granted;""", 1)
        write(call, "set statement_timeout='12s'; set role service_role; "
              f"select public.complete_account_deletion('{token}') #>> '{{error,code}}';\n\\q")
        wait_for(db, f"""select count(*) from pg_locks l join pg_stat_activity a
            on a.pid=l.pid where a.application_name='{prefix}-call'
            and l.locktype='advisory' and not l.granted;""", 1)
        if replacement is None:
            db.sql(f"delete from private.account_deletion_receipts where token_hash='{token}';")
        else:
            db.sql(f"update private.account_deletion_receipts set deletion_id='{replacement}' "
                   f"where token_hash='{token}';")
        write(holder, "commit;\n\\q")
        holder.communicate(timeout=15)
        output, _ = call.communicate(timeout=15)
        if holder.returncode or call.returncode or output.strip() != "request_conflict":
            raise RuntimeError("unlocked lookup was not revalidated after operation wait")
        if replacement is not None and db.sql(
                f"select status from private.account_deletion_receipts where token_hash='{token}';") != "pending":
            raise RuntimeError("changed operation identity was completed")
        print(f"PASS revalidation after {'removal' if replacement is None else 'identity change'}")
    finally:
        stop(call)
        stop(holder)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--expect-deadlock", action="store_true")
    options = parser.parse_args()
    db = Database()
    run_id = uuid.uuid4().hex
    tokens = [hashlib.sha256(f"{run_id}-{i}".encode()).hexdigest() for i in range(6)]
    operations = [str(uuid.uuid4()) for _ in range(6)]
    token_list = ",".join(f"'{token}'" for token in tokens)
    receipt_operations = [operations[0], operations[0], *operations[1:5]]
    rows = ",".join(f"('{token}','{operation}')"
                    for token, operation in zip(tokens, receipt_operations))
    try:
        db.sql("insert into private.account_deletion_receipts (token_hash,deletion_id) "
               f"values {rows};")
        run_pair(db, "receipt-" + run_id + "-rotated", tokens[:2], options.expect_deadlock)
        if db.sql(f"""select count(*) from private.account_deletion_receipts
            where token_hash in ({token_list}) and status='completed'
            and user_id is null and completed_at is not null;""") != "2":
            raise RuntimeError("rotated completion did not terminalize exactly its operation")
        for token in tokens[:2]:
            if db.sql("set role service_role; "
                      f"select public.complete_account_deletion('{token}') #>> '{{data,status}}';") != "completed":
                raise RuntimeError("idempotent retry failed")
        run_pair(db, "receipt-" + run_id + "-separate", tokens[2:4], False, separate=True)
        if db.sql(f"""select count(*) from private.account_deletion_receipts
            where token_hash in ({token_list}) and status='completed'
            and user_id is null and completed_at is not null;""") != "4":
            raise RuntimeError("separate completion state is invalid")
        print("PASS operation-scoped terminal state and idempotent retries")
        if not options.expect_deadlock:
            revalidation_control(db, "receipt-" + run_id + "-removed", tokens[4], operations[3])
            revalidation_control(db, "receipt-" + run_id + "-changed", tokens[5], operations[4], operations[5])
    finally:
        db.sql(f"delete from private.account_deletion_receipts where token_hash in ({token_list});")
        if db.sql(f"select count(*) from private.account_deletion_receipts where token_hash in ({token_list});") != "0":
            raise RuntimeError("owned receipt cleanup failed")
        print("PASS owned receipt cleanup")


if __name__ == "__main__":
    try:
        main()
    except RuntimeError as error:
        raise SystemExit(f"FAIL receipt race: {error}")
    except (subprocess.TimeoutExpired, OSError, ValueError):
        # Never print raw subprocess output/URL, which can carry fixture digests.
        raise SystemExit("FAIL receipt race (diagnostics suppressed; check lease/tools/barrier)")
