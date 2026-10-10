"""The approved retained-input checkpoint, independent of extraction-origin claims."""

from __future__ import annotations

from contextlib import closing
import hashlib
import json
import re
import sqlite3
from pathlib import Path

ATTESTATION_FILE = "daily-classic-en-US-v1-retained-inputs.json"
ATTESTATION_SHA256 = "6500a4d872bf80dbff1679670ed3de8abcd40925d9e2c82f7555994d2931307f"
SHA256 = re.compile(r"[0-9a-f]{64}\Z")


def verified_bytes(path: Path, expected: str, label: str) -> bytes:
    try:
        raw = path.read_bytes()
    except OSError as error:
        raise ValueError(f"{label} unavailable: {path}") from error
    if hashlib.sha256(raw).hexdigest() != expected:
        raise ValueError(f"{label} identity mismatch: {path}")
    return raw


def load_attestation(packs: Path) -> dict:
    raw = verified_bytes(packs / ATTESTATION_FILE, ATTESTATION_SHA256, "retained-input attestation")
    attestation = json.loads(raw)
    if (attestation.get("formatVersion") != 1
            or attestation.get("kind") != "retained-input-identity"
            or attestation.get("historicalOrigin") != "unverified"):
        raise ValueError("unsupported retained-input attestation contract")
    for field in ("candidateFiles", "targetFiles", "coverageFiles", "databaseBodies"):
        entries = attestation.get(field)
        if not isinstance(entries, dict) or not entries or not all(
            isinstance(key, str) and key and isinstance(value, str) and SHA256.fullmatch(value)
            for key, value in entries.items()
        ):
            raise ValueError(f"invalid retained-input attestation {field}")
    return attestation


def verified_files(directory: Path, pattern: str, expected: dict[str, str], label: str) -> dict[str, bytes]:
    paths = {path.name: path for path in directory.glob(pattern)}
    if set(paths) != set(expected):
        raise ValueError(f"{label} file set mismatch: missing {len(set(expected) - set(paths))}, "
                         f"unexpected {len(set(paths) - set(expected))}")
    # Verify and parse these same bytes; do not reopen inputs after validation.
    return {name: verified_bytes(paths[name], expected[name], label) for name in sorted(paths)}


def verified_database_bodies(database: Path, expected: dict[str, str]) -> dict[str, str]:
    """Pin logical consumed rows, rather than SQLite file layout or unused pages."""
    bodies = {}
    try:
        with closing(sqlite3.connect(database.resolve().as_uri() + "?mode=ro&immutable=1", uri=True)) as connection:
            for title, digest in expected.items():
                rows = connection.execute(
                    "SELECT body FROM pages WHERE namespace_id=0 AND title=?", (title,)
                ).fetchall()
                if len(rows) != 1 or not isinstance(rows[0][0], str):
                    raise ValueError("SQLite consumed title set mismatch")
                body = rows[0][0]
                if hashlib.sha256(body.encode("utf-8")).hexdigest() != digest:
                    raise ValueError("SQLite consumed body identity mismatch")
                bodies[title] = body
    except sqlite3.Error as error:
        raise ValueError("SQLite consumed evidence unavailable") from error
    return bodies
