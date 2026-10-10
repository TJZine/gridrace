#!/usr/bin/env python3
"""Regression checks for corpus input and cross-evidence boundaries."""

from __future__ import annotations

import argparse
from contextlib import closing
import bz2
import hashlib
import importlib.util
import io
import json
import os
import shutil
import sqlite3
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
SCRIPT = ROOT / "scripts/build_accepted_guesses.py"
SPEC = importlib.util.spec_from_file_location("build_accepted_guesses", SCRIPT)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError(f"cannot load {SCRIPT}")
BUILD = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(BUILD)


def load_script(name: str):
    spec = importlib.util.spec_from_file_location(name, ROOT / f"scripts/{name}.py")
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load {name}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


CHECK = load_script("check_word_pack")
PARENT = load_script("parent_revision_pass")


class RevisionIndexBoundaryTests(unittest.TestCase):
    def test_valid_bytes_are_verified_before_parsing(self) -> None:
        raw = b'{"title":"alpha","pageId":"1"}\n'
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "revision-index.jsonl"
            path.write_bytes(raw)
            with mock.patch.object(
                BUILD, "FIVE_LETTER_INDEX_SHA256", hashlib.sha256(raw).hexdigest()
            ):
                self.assertEqual(
                    BUILD.load_revision_index(path),
                    {"alpha": {"title": "alpha", "pageId": "1"}},
                )

    def test_invalid_revision_inputs_fail_before_outputs_change(self) -> None:
        cases = {
            "mismatched": b'{"title":"alpha"}\n',
            "absent": None,
            "unreadable": "directory",
        }
        for label, content in cases.items():
            with self.subTest(label=label), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                revision_index = root / "revision-index.jsonl"
                if content == "directory":
                    revision_index.mkdir()
                elif content is not None:
                    revision_index.write_bytes(content)
                outputs = {
                    root / "pack.json": b"pack sentinel\n",
                    root / "provenance.jsonl": b"provenance sentinel\n",
                    root / "manifest.json": b"manifest sentinel\n",
                }
                for path, value in outputs.items():
                    path.write_bytes(value)

                args = argparse.Namespace(revision_index=str(revision_index))
                with self.assertRaises(ValueError) as raised:
                    BUILD.run(args)

                message = str(raised.exception)
                self.assertIn("revision index", message)
                for path, value in outputs.items():
                    self.assertEqual(path.read_bytes(), value, path.name)


class RetainedInputBoundaryTests(unittest.TestCase):
    def test_hermetic_file_and_sqlite_identity_boundaries(self) -> None:
        identity = BUILD.input_identity
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            path = root / "chunk-000.jsonl"
            raw = b'{"word":"alpha"}\n'
            expected = {path.name: hashlib.sha256(raw).hexdigest()}
            path.write_bytes(raw)
            self.assertEqual(identity.verified_files(root, "chunk-*.jsonl", expected, "candidate"),
                             {path.name: raw})
            path.write_bytes(raw + b" ")
            with self.assertRaisesRegex(ValueError, "identity mismatch"):
                identity.verified_files(root, "chunk-*.jsonl", expected, "candidate")
            path.unlink()
            with self.assertRaisesRegex(ValueError, "file set mismatch"):
                identity.verified_files(root, "chunk-*.jsonl", expected, "candidate")
            path.write_bytes(raw)
            unexpected = root / "chunk-unexpected.jsonl"
            unexpected.write_bytes(raw)
            with self.assertRaisesRegex(ValueError, "file set mismatch"):
                identity.verified_files(root, "chunk-*.jsonl", expected, "candidate")
            unexpected.unlink()
            self.assertEqual(identity.verified_files(root, "chunk-*.jsonl", expected, "candidate"),
                             {path.name: raw})
            database = root / "bodies.sqlite"
            with closing(sqlite3.connect(database)) as connection, connection:
                connection.execute("CREATE TABLE pages(namespace_id INTEGER, title TEXT, body TEXT)")
                connection.executemany("INSERT INTO pages VALUES(0,?,?)", [("alpha", "body"), ("unused", "ignored")])
            body_identity = {"alpha": hashlib.sha256(b"body").hexdigest()}
            self.assertEqual(identity.verified_database_bodies(database, body_identity), {"alpha": "body"})
            for operation in ("substituted", "missing", "duplicate"):
                with self.subTest(operation=operation):
                    with closing(sqlite3.connect(database)) as connection, connection:
                        connection.execute("DELETE FROM pages WHERE title='alpha'")
                        if operation != "missing":
                            connection.execute("INSERT INTO pages VALUES(0,'alpha',?)",
                                               ("changed" if operation == "substituted" else "body",))
                        if operation == "duplicate":
                            connection.execute("INSERT INTO pages VALUES(0,'alpha','body')")
                    with self.assertRaisesRegex(ValueError, "SQLite consumed"):
                        identity.verified_database_bodies(database, body_identity)
            with closing(sqlite3.connect(database)) as connection, connection:
                connection.execute("DELETE FROM pages WHERE title='alpha'")
                connection.execute("INSERT INTO pages VALUES(0,'alpha','body')")
            self.assertEqual(identity.verified_database_bodies(database, body_identity), {"alpha": "body"})

    @unittest.skipUnless(
        os.environ.get("GRIDRACE_CORPUS_INPUT_INTEGRATION") == "1",
        "real retained-input controls require GRIDRACE_CORPUS_INPUT_INTEGRATION=1 and preserved corpus",
    )
    def test_actual_consumed_input_failures_leave_all_outputs_unchanged(self) -> None:
        # Real retained inputs, copied into owned storage. The SQLite fixture
        # preserves every consumed row while excluding irrelevant cache pages.
        attestation = BUILD.input_identity.load_attestation(BUILD.PACKS)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            defaults = BUILD.pinned_defaults()
            candidates = root / "candidates"
            targets = root / "targets"
            candidates.mkdir()
            targets.mkdir()
            for source, destination, patterns in (
                (Path(defaults["wiktionary_json"]), candidates, ("chunk-*.jsonl",)),
                (Path(defaults["target_json"]), targets, ("target-*.jsonl", "target-*.pages.json")),
            ):
                for pattern in patterns:
                    for path in source.glob(pattern):
                        shutil.copyfile(path, destination / path.name)
            inputs = {}
            for field, source in (
                ("baseline", BUILD.PACKS / "baseline-accepted-frozen.txt"),
                ("revision_index", Path(defaults["revision_index"])),
                ("extra_revisions", BUILD.PACKS / "daily-classic-en-US-v1-parent-revisions.json"),
            ):
                inputs[field] = root / source.name
                shutil.copyfile(source, inputs[field])
            database = root / "bodies.sqlite"
            bodies = BUILD.input_identity.verified_database_bodies(
                Path(defaults["database"]), attestation["databaseBodies"]
            )
            with closing(sqlite3.connect(database)) as connection, connection:
                connection.execute("CREATE TABLE pages(namespace_id INTEGER, title TEXT, body TEXT)")
                connection.execute("CREATE INDEX pages_title ON pages(namespace_id, title)")
                connection.executemany("INSERT INTO pages VALUES(0,?,?)", bodies.items())
            args = argparse.Namespace(
                **{key: str(value) for key, value in inputs.items()},
                wiktionary_json=str(candidates), target_json=str(targets), database=str(database),
                pack=str(root / "daily-classic-en-US-v1.json"),
                provenance=str(root / "daily-classic-en-US-v1-PROVENANCE.jsonl"),
                provenance_manifest=str(root / "daily-classic-en-US-v1-PROVENANCE.manifest.json"),
                prior_explicit=str(root / "absent-diagnostic"),
            )
            shutil.copyfile(BUILD.PACKS / "daily-classic-en-US-v1.json", args.pack)
            BUILD.run(args)
            outputs = {Path(path): Path(path).read_bytes() for path in
                       (args.pack, args.provenance, args.provenance_manifest)}
            self.assertEqual(outputs[Path(args.pack)], (BUILD.PACKS / Path(args.pack).name).read_bytes())
            self.assertEqual(outputs[Path(args.provenance)], (BUILD.PACKS / Path(args.provenance).name).read_bytes())

            def fail(label: str, reason: str) -> None:
                with self.subTest(label=label):
                    with self.assertRaisesRegex(ValueError, reason):
                        BUILD.run(args)
                    self.assertEqual({path: path.read_bytes() for path in outputs}, outputs)

            for directory_path, pattern, reason in (
                (candidates, "chunk-*.jsonl", "candidate JSONL"),
                (targets, "target-*.jsonl", "target JSONL"),
                (targets, "target-*.pages.json", "target coverage"),
            ):
                path = sorted(directory_path.glob(pattern))[0]
                original = path.read_bytes()
                path.write_bytes(original + b" ")
                fail(pattern + " substituted", reason)
                path.unlink()
                fail(pattern + " missing", reason)
                path.write_bytes(original)
                extra = directory_path / pattern.replace("*", "unexpected")
                extra.write_bytes(original)
                fail(pattern + " unexpected", reason)
                extra.unlink()
            for field, path in inputs.items():
                original = path.read_bytes()
                path.write_bytes(original + b" ")
                fail(field + " substituted", {"baseline": "baseline", "revision_index": "revision index", "extra_revisions": "parent revisions"}[field])
                path.unlink()
                fail(field + " missing", {"baseline": "baseline", "revision_index": "revision index", "extra_revisions": "parent revisions"}[field])
                path.write_bytes(original)
            title = next(iter(bodies))
            for operation in ("substituted", "missing", "duplicate"):
                with closing(sqlite3.connect(database)) as connection, connection:
                    if operation == "substituted":
                        connection.execute("UPDATE pages SET body='substituted' WHERE title=?", (title,))
                    elif operation == "missing":
                        connection.execute("DELETE FROM pages WHERE title=?", (title,))
                    else:
                        connection.execute("INSERT INTO pages VALUES(0,?,?)", (title, bodies[title]))
                fail("SQLite " + operation, "SQLite")
                with closing(sqlite3.connect(database)) as connection, connection:
                    connection.execute("DELETE FROM pages WHERE title=?", (title,))
                    connection.execute("INSERT INTO pages VALUES(0,?,?)", (title, bodies[title]))
            database.rename(root / "database-held.sqlite")
            fail("SQLite file missing", "SQLite")
            (root / "database-held.sqlite").rename(database)
            # An unused row is outside the membership input contract.
            with closing(sqlite3.connect(database)) as connection, connection:
                connection.execute("INSERT INTO pages VALUES(1,'unrelated','unused')")
            # Restoration earns a full successful transform, rather than a
            # validator-only pass. All three deterministic outputs match.
            BUILD.run(args)
            self.assertEqual({path: path.read_bytes() for path in outputs}, outputs)

    def test_absent_intermediates_fail_full_gate_but_portable_stays_offline(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            packs = root / "packs"
            shutil.copytree(CHECK.PACKS, packs)
            absent = {key: root / "absent" / Path(value).name
                      for key, value in BUILD.pinned_defaults().items()}
            self.assertTrue(all(not path.exists() for path in absent.values()))
            manifests = {path: path.read_bytes() for path in packs.glob("*.manifest.json")}
            with (
                mock.patch.object(CHECK, "PACKS", packs),
                mock.patch.object(CHECK, "builder_intermediate_paths", return_value=absent),
                mock.patch("sys.stderr", new_callable=io.StringIO) as errors,
                mock.patch("sys.stdout", new_callable=io.StringIO),
            ):
                with mock.patch.object(sys, "argv", ["check_word_pack", "--write-manifest"]):
                    self.assertEqual(CHECK.main(), 1)
                self.assertIn("source UNAVAILABLE", errors.getvalue())
                self.assertEqual({path: path.read_bytes() for path in manifests}, manifests)
                with mock.patch.object(sys, "argv", ["check_word_pack", "--checked-in-only"]):
                    self.assertEqual(CHECK.main(), 0)

    def test_source_failure_precedes_checker_manifest_refresh(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            packs = Path(directory)
            shutil.copytree(CHECK.PACKS, packs, dirs_exist_ok=True)
            manifests = {path: path.read_bytes() for path in packs.glob("*.manifest.json")}
            with (
                mock.patch.object(CHECK, "PACKS", packs),
                mock.patch.object(CHECK, "run_source_gate", side_effect=ValueError("source identity mismatch")),
                mock.patch.object(sys, "argv", ["check_word_pack", "--write-manifest"]),
                mock.patch("sys.stderr", new_callable=io.StringIO),
            ):
                self.assertEqual(CHECK.main(), 1)
                self.assertEqual({path: path.read_bytes() for path in manifests}, manifests)

    def test_rehashed_attestation_is_not_a_new_approved_checkpoint(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            packs = Path(directory)
            shutil.copytree(CHECK.PACKS, packs, dirs_exist_ok=True)
            path = packs / BUILD.input_identity.ATTESTATION_FILE
            attestation = json.loads(path.read_bytes())
            attestation["targetFiles"][next(iter(attestation["targetFiles"]))] = "0" * 64
            raw = (json.dumps(attestation, indent=2, sort_keys=True) + "\n").encode()
            path.write_bytes(raw)
            manifest_path = packs / CHECK.PROVENANCE_MANIFEST_FILE
            manifest = json.loads(manifest_path.read_bytes())
            manifest["inputs"]["retainedInputAttestationSha256"] = hashlib.sha256(raw).hexdigest()
            manifest_path.write_text(json.dumps(manifest))
            with mock.patch.object(CHECK, "PACKS", packs):
                pack_raw = (packs / f"{CHECK.DAILY_ID}.json").read_bytes()
                with self.assertRaisesRegex(ValueError, "attestation identity mismatch"):
                    CHECK.validate_chain(json.loads(pack_raw), pack_raw)
            outputs = {packs / name: b"sentinel" for name in ("out-pack", "out-rows", "out-manifest")}
            for output, content in outputs.items():
                output.write_bytes(content)
            revision_index = packs / "fixture-revisions.jsonl"
            revision_raw = b'{"title":"alpha","pageId":"1"}\n'
            revision_index.write_bytes(revision_raw)
            args = argparse.Namespace(
                revision_index=str(revision_index),
                baseline=str(packs / "baseline-accepted-frozen.txt"),
                pack=str(packs / "out-pack"), provenance=str(packs / "out-rows"),
                provenance_manifest=str(packs / "out-manifest"),
            )
            with (
                mock.patch.object(BUILD, "PACKS", packs),
                mock.patch.object(BUILD, "FIVE_LETTER_INDEX_SHA256", hashlib.sha256(revision_raw).hexdigest()),
            ):
                with self.assertRaisesRegex(ValueError, "attestation identity mismatch"):
                    BUILD.run(args)
                self.assertEqual({output: output.read_bytes() for output in outputs}, outputs)
                path.unlink()
                with self.assertRaisesRegex(ValueError, "attestation unavailable"):
                    BUILD.run(args)
                self.assertEqual({output: output.read_bytes() for output in outputs}, outputs)


class ParentEvidenceTests(unittest.TestCase):
    def test_portable_gate_rejects_rehashed_contradictory_tuple(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            packs = Path(directory) / "packs"
            shutil.copytree(CHECK.PACKS, packs)
            pack_raw = (packs / f"{CHECK.DAILY_ID}.json").read_bytes()
            pack = json.loads(pack_raw)
            with mock.patch.object(CHECK, "PACKS", packs):
                CHECK.validate_chain(pack, pack_raw)
                provenance = packs / CHECK.PROVENANCE_FILE
                original = provenance.read_bytes()
                rows = [json.loads(line) for line in original.splitlines()]
                row = next(row for row in rows if row["revision_status"] == "dump_parent")
                manifest_path = packs / CHECK.PROVENANCE_MANIFEST_FILE
                original_manifest = manifest_path.read_bytes()
                for field in ("page_id", "revision_id", "timestamp"):
                    with self.subTest(field=field):
                        old = row[field]
                        row[field] = "contradictory"
                        raw = ("".join(json.dumps(r) + "\n" for r in rows)).encode()
                        provenance.write_bytes(raw)
                        manifest = json.loads(original_manifest)
                        manifest["provenanceSha256"] = hashlib.sha256(raw).hexdigest()
                        manifest_path.write_text(json.dumps(manifest))
                        with self.assertRaisesRegex(ValueError, "contradicts"):
                            CHECK.validate_chain(pack, pack_raw)
                        with (
                            mock.patch.object(sys, "argv", [
                                "check_word_pack", "--checked-in-only", "--write-manifest"
                            ]),
                            mock.patch("sys.stderr", new_callable=io.StringIO),
                        ):
                            manifests = {path: path.read_bytes() for path in packs.glob("*.manifest.json")}
                            self.assertEqual(CHECK.main(), 1)
                            self.assertEqual({path: path.read_bytes() for path in manifests}, manifests)
                        row[field] = old
                provenance.write_bytes(original)
                manifest_path.write_bytes(original_manifest)
                CHECK.validate_chain(pack, pack_raw)

    def test_shared_parent_and_missing_revision_representation(self) -> None:
        row = {"page": "parent", "revision_status": "dump_parent", "page_id": "1",
               "revision_id": "2", "timestamp": "time"}
        found = {"parent": {"title": "parent", "pageId": "1", "revisionId": "2", "timestamp": "time"}}
        unavailable = {"page": "missing", "revision_status": "unavailable",
                       "page_id": None, "revision_id": None, "timestamp": None}
        CHECK.validate_parent_revisions([row, dict(row), unavailable], found, ["missing"])
        schema_row = dict(CHECK.load_provenance()[0][0])
        schema_row.update(revision_status="unavailable", page_id=None, revision_id=None, timestamp=None)
        CHECK.check_provenance_row(schema_row, 0)
        schema_row["revision_status"] = "dump_parent"
        with self.assertRaisesRegex(ValueError, "must carry page/revision/timestamp"):
            CHECK.check_provenance_row(schema_row, 0)
        # Empty dump values normalize to null, as in the builder. The full
        # provenance schema separately rejects nulls for dump_parent rows.
        null_row = dict(row, revision_id=None)
        found["parent"]["revisionId"] = ""
        CHECK.validate_parent_revisions([null_row], found, [])
        with self.assertRaisesRegex(ValueError, "revision_id"):
            CHECK.validate_parent_revisions([row], found, [])
        with self.assertRaisesRegex(ValueError, "absent"):
            CHECK.validate_parent_revisions([row], {}, [])
        with self.assertRaisesRegex(ValueError, "overlap"):
            CHECK.validate_parent_revisions([], found, ["parent"])

    def test_entire_compressed_dump_verified_before_early_hit_output(self) -> None:
        xml = b"<mediawiki><page><title>parent</title><ns>0</ns><id>1</id><revision><id>2</id><timestamp>time</timestamp><text>body</text></revision></page></mediawiki>"
        raw = bz2.compress(xml)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            dump = root / "dump.bz2"
            titles = root / "titles.json"
            titles.write_text('["parent"]')
            output = root / "out.json"
            sentinel = b"existing output\n"
            argv = ["parent_revision_pass", "--dump", str(dump), "--titles-file", str(titles),
                    "--provenance", str(root / "unused"), "--output", str(output)]
            with (
                mock.patch.object(PARENT, "DUMP_SHA256", hashlib.sha256(raw).hexdigest()),
                mock.patch.object(sys, "argv", argv),
                mock.patch("sys.stdout", new_callable=io.StringIO),
            ):
                for bad in (bz2.compress(xml.replace(b"body", b"wrong")), raw[:-5], raw + b"changed tail"):
                    dump.write_bytes(bad)
                    output.write_bytes(sentinel)
                    with self.assertRaisesRegex(ValueError, "SHA-256"):
                        PARENT.main()
                    self.assertEqual(output.read_bytes(), sentinel)
                dump.write_bytes(raw)
                self.assertEqual(PARENT.main(), 0)
                result = json.loads(output.read_text())
                self.assertEqual(result["found"]["parent"]["revisionId"], "2")
                self.assertEqual(result["pages_scanned"], 1)


if __name__ == "__main__":
    unittest.main()
