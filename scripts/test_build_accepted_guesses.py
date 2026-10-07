#!/usr/bin/env python3
"""Focused tests for the fail-closed revision-index input boundary."""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
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


if __name__ == "__main__":
    unittest.main()
