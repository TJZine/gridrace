#!/usr/bin/env python3
"""Validate the development word pack and its deterministic manifest."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import sys


ROOT = Path(__file__).resolve().parents[1]
PACK = ROOT / "shared/word-packs/development-en-US-v1.json"
MANIFEST = ROOT / "shared/word-packs/development-en-US-v1.manifest.json"
WORD = re.compile(r"[a-z]{5}", re.ASCII)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def load_pack() -> tuple[dict[str, object], bytes]:
    raw = PACK.read_bytes()
    pack = json.loads(raw.decode("utf-8"))
    require(isinstance(pack, dict), "word pack must be a JSON object")
    canonical = (json.dumps(pack, indent=2, ensure_ascii=True) + "\n").encode()
    require(raw == canonical, "word pack JSON is not in deterministic format")
    return pack, raw


def validate_pack(pack: dict[str, object]) -> list[str]:
    require(pack.get("formatVersion") == 1, "formatVersion must be 1")
    require(pack.get("id") == "development-en-US-v1", "unexpected pack id")
    require(pack.get("locale") == "en-US", "locale must be en-US")
    require(pack.get("wordLength") == 5, "wordLength must be 5")
    require(
        pack.get("usage")
        == {
            "answerCount": 100,
            "acceptedGuesses": "sameAsAnswers",
            "limitation": (
                "Phase 1 development only; this is not a production accepted-guess "
                "lexicon."
            ),
        },
        "usage metadata must describe the Phase 1-only accepted-list limitation",
    )
    require(
        pack.get("provenance")
        == {
            "method": (
                "Original manual compilation for GridRace from ordinary English "
                "vocabulary."
            ),
            "commercialListUse": (
                "No commercial game list or third-party word corpus was copied, "
                "scraped, or adapted."
            ),
            "reviewedOn": "2026-08-30",
            "license": (
                "No standalone license grant; repository copyright applies until "
                "the owner adopts a license."
            ),
        },
        "provenance or licensing metadata is incomplete",
    )
    require(
        pack.get("manualReview")
        == {
            "familiar": True,
            "nonProper": True,
            "nonAbbreviated": True,
            "sensitiveTermsReviewed": True,
        },
        "manual review attestations must all be true",
    )

    words = pack.get("words")
    require(isinstance(words, list), "words must be an array")
    require(all(isinstance(word, str) for word in words), "every word must be a string")
    typed_words = [word for word in words if isinstance(word, str)]
    require(len(typed_words) == 100, "word pack must contain exactly 100 words")
    require(len(set(typed_words)) == 100, "word pack contains a duplicate")
    require(typed_words == sorted(typed_words), "word pack must be sorted")
    invalid = [word for word in typed_words if WORD.fullmatch(word) is None]
    require(not invalid, f"words must be lowercase five-letter ASCII: {invalid}")
    return typed_words


def manifest_bytes(pack: dict[str, object], raw: bytes, word_count: int) -> bytes:
    manifest = {
        "formatVersion": 1,
        "source": PACK.name,
        "packID": pack["id"],
        "packVersion": pack["formatVersion"],
        "locale": pack["locale"],
        "wordLength": pack["wordLength"],
        "answerCount": word_count,
        "acceptedGuessCount": word_count,
        "sha256": hashlib.sha256(raw).hexdigest(),
    }
    return (json.dumps(manifest, indent=2) + "\n").encode()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--write-manifest",
        action="store_true",
        help="replace the manifest with the deterministic value",
    )
    args = parser.parse_args()

    try:
        pack, raw = load_pack()
        words = validate_pack(pack)
        expected = manifest_bytes(pack, raw, len(words))
        if args.write_manifest:
            MANIFEST.write_bytes(expected)
        else:
            require(
                MANIFEST.read_bytes() == expected,
                "manifest is stale; run with --write-manifest",
            )
    except (OSError, UnicodeError, json.JSONDecodeError, ValueError) as error:
        print(f"word-pack check failed: {error}", file=sys.stderr)
        return 1

    print(f"word-pack check passed: {len(words)} words")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
