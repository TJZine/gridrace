#!/usr/bin/env python3
"""Validate checked-in word packs, manifests, and deterministic generation."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import sys
from typing import Callable

from generate_daily_word_pack import BANNED_ANSWERS, build as build_daily_pack


ROOT = Path(__file__).resolve().parents[1]
PACKS = ROOT / "shared/word-packs"
WORD = re.compile(r"[a-z]{5}", re.ASCII)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def load(path: Path) -> tuple[dict[str, object], bytes]:
    raw = path.read_bytes()
    value = json.loads(raw.decode("utf-8"))
    require(isinstance(value, dict), f"{path.name} must be a JSON object")
    canonical = (json.dumps(value, indent=2, ensure_ascii=True) + "\n").encode()
    require(raw == canonical, f"{path.name} is not in deterministic JSON format")
    return value, raw


def words(value: object, label: str) -> list[str]:
    require(isinstance(value, list), f"{label} must be an array")
    require(all(isinstance(word, str) for word in value), f"{label} must contain strings")
    result = [word for word in value if isinstance(word, str)]
    require(len(result) == len(set(result)), f"{label} contains a duplicate")
    invalid = [word for word in result if WORD.fullmatch(word) is None]
    require(not invalid, f"{label} must be lowercase five-letter ASCII: {invalid[:5]}")
    return result


def manifest_bytes(pack: dict[str, object], raw: bytes, answers: int, accepted: int) -> bytes:
    manifest = {
        "formatVersion": 1,
        "source": f"{pack['id']}.json",
        "packID": pack["id"],
        "packVersion": pack["formatVersion"],
    }
    if "scheduleVersion" in pack:
        manifest["scheduleVersion"] = pack["scheduleVersion"]
    if "epochDay" in pack:
        manifest["epochDay"] = pack["epochDay"]
    manifest.update(
        {
            "locale": pack["locale"],
            "wordLength": pack["wordLength"],
            "answerCount": answers,
            "acceptedGuessCount": accepted,
            "sha256": hashlib.sha256(raw).hexdigest(),
        }
    )
    return (json.dumps(manifest, indent=2, ensure_ascii=True) + "\n").encode()


def validate_development(pack: dict[str, object]) -> tuple[int, int]:
    require(pack.get("formatVersion") == 1, "development formatVersion must be 1")
    require(pack.get("id") == "development-en-US-v1", "unexpected development pack id")
    require(pack.get("locale") == "en-US", "development locale must be en-US")
    require(pack.get("wordLength") == 5, "development wordLength must be 5")
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
        "development usage metadata changed",
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
        "development provenance or licensing metadata changed",
    )
    require(
        pack.get("manualReview")
        == {
            "familiar": True,
            "nonProper": True,
            "nonAbbreviated": True,
            "sensitiveTermsReviewed": True,
        },
        "development manual review attestations must all be true",
    )
    entries = words(pack.get("words"), "development words")
    require(len(entries) == 100, "development pack must contain exactly 100 words")
    require(entries == sorted(entries), "development words must be sorted")
    return len(entries), len(entries)


def validate_daily(pack: dict[str, object]) -> tuple[int, int]:
    require(pack.get("formatVersion") == 1, "daily formatVersion must be 1")
    require(pack.get("id") == "daily-classic-en-US-v1", "unexpected daily pack id")
    require(pack.get("locale") == "en-US", "daily locale must be en-US")
    require(pack.get("wordLength") == 5, "daily wordLength must be 5")
    require(pack.get("scheduleVersion") == 1, "daily scheduleVersion must be 1")
    require(pack.get("epochDay") == 20696, "daily epoch must be 2026-08-31 UTC")
    require(
        pack.get("schedulePolicy")
        == "Fixed answer order; never reorder or remove published v1 entries.",
        "daily schedule policy must preserve published assignments",
    )
    require(
        pack.get("manualReview")
        == {
            "answersFamiliar": True,
            "answersNonProper": True,
            "answersNonAbbreviated": True,
            "answersSensitiveTermsReviewed": True,
        },
        "daily answer review attestations must all be true",
    )

    accepted = words(pack.get("acceptedGuesses"), "daily accepted guesses")
    answers = words(pack.get("answers"), "daily answers")
    require(accepted == sorted(accepted), "daily accepted guesses must be sorted")
    require(len(accepted) >= 8_000, "daily accepted-guess list is too narrow")
    require(len(answers) >= 365, "daily answer schedule must cover at least one year")
    require(set(answers) <= set(accepted), "every daily answer must be an accepted guess")
    require(not (set(answers) & BANNED_ANSWERS), "daily answers contain a banned term")
    return len(answers), len(accepted)


def validate_one(
    pack_id: str,
    validator: Callable[[dict[str, object]], tuple[int, int]],
    write_manifest: bool,
) -> tuple[int, int]:
    pack_path = PACKS / f"{pack_id}.json"
    manifest_path = PACKS / f"{pack_id}.manifest.json"
    pack, raw = load(pack_path)
    answer_count, accepted_count = validator(pack)
    expected = manifest_bytes(pack, raw, answer_count, accepted_count)
    if write_manifest:
        manifest_path.write_bytes(expected)
    else:
        require(manifest_path.read_bytes() == expected, f"{manifest_path.name} is stale")
    return answer_count, accepted_count


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--write-manifest",
        action="store_true",
        help="replace manifests with deterministic values after validating packs",
    )
    args = parser.parse_args()

    try:
        development = validate_one(
            "development-en-US-v1", validate_development, args.write_manifest
        )
        daily = validate_one("daily-classic-en-US-v1", validate_daily, args.write_manifest)
        generated_pack, generated_manifest = build_daily_pack()
        require(
            (PACKS / "daily-classic-en-US-v1.json").read_bytes() == generated_pack,
            "daily pack is stale; run scripts/generate_daily_word_pack.py",
        )
        require(
            (PACKS / "daily-classic-en-US-v1.manifest.json").read_bytes()
            == generated_manifest,
            "daily manifest differs from deterministic generation",
        )
    except (OSError, UnicodeError, json.JSONDecodeError, ValueError) as error:
        print(f"word-pack check failed: {error}", file=sys.stderr)
        return 1

    print(
        "word-pack check passed: "
        f"development {development[0]} words; "
        f"Daily Classic {daily[0]} answers, {daily[1]} accepted guesses"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
