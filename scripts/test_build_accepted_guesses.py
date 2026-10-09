#!/usr/bin/env python3
"""Regression checks for corpus input and cross-evidence boundaries."""

from __future__ import annotations

import argparse
import bz2
import hashlib
import importlib.util
import io
import json
import shutil
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]
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
