#!/usr/bin/env python3
"""Validate checked-in word packs, manifests, and deterministic generation.

``--checked-in-only`` (portable, stdlib-only, no Wiktionary reads) asserts the
complete checked-in evidence chain: frozen baseline count/hash/shape, ordered
answer count/hash, provenance row validity (uniqueness, rule vocabulary,
rule-specific evidence fields, revision-status vocabulary), the set identity
final == baseline union provenance, target-coverage aggregate totals, and
recomputed file-hash agreement across the pack, provenance, baseline,
parent-revisions sidecar, and both manifests. It runs on every machine,
including CI, which uses only this flag.

No flags (source gate, fail-closed) revalidates that same portable chain,
then regenerates the pack, provenance, and builder-owned provenance manifest
from the pinned Wiktionary intermediates into a temporary directory (via
``scripts/build_accepted_guesses.py`` with its pinned defaults) and compares
pack, provenance, and provenance-manifest hashes/bytes to the checked-in
files. Builder import, syntax, execution, and comparison failures are errors.
Where the required intermediates are absent the gate reports UNAVAILABLE and
exits nonzero; it never prints a pass it did not earn.
``--probe-intermediates`` is the separate informational probe: it reports
which pinned intermediates exist and always exits 0 without validating
anything.

``--write-manifest`` refreshes the checker-owned pack manifests (development
and daily) after the chain's structural validation passes, then re-verifies
manifest agreement to prove the repair. It cannot fabricate the
builder-owned provenance attestation: after any intentional transform or
metadata change, run ``python3 scripts/build_accepted_guesses.py`` first
(rewrites pack, provenance, and the provenance manifest), then this flag,
then the plain gates.
"""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import re
import shutil
import subprocess
import sys
import tempfile
import time
from collections import Counter
from pathlib import Path
from typing import Callable

from generate_daily_word_pack import BANNED_ANSWERS


ROOT = Path(__file__).resolve().parents[1]
PACKS = ROOT / "shared/word-packs"
SCRIPTS = ROOT / "scripts"
WORD = re.compile(r"[a-z]{5}", re.ASCII)
SOURCE_CASE = re.compile(r"[A-Za-z]{5}", re.ASCII)
LOCATOR = re.compile(r"chunk-[A-Za-z0-9]+\.jsonl:[1-9][0-9]*", re.ASCII)

DAILY_ID = "daily-classic-en-US-v1"
BASELINE_FILE = "baseline-accepted-frozen.txt"
PROVENANCE_FILE = f"{DAILY_ID}-PROVENANCE.jsonl"
PROVENANCE_MANIFEST_FILE = f"{DAILY_ID}-PROVENANCE.manifest.json"
PARENT_REVISIONS_FILE = f"{DAILY_ID}-parent-revisions.json"

BASELINE_COUNT = 8508
BASELINE_SHA256 = "f045112edcf1fb2889b58a947f0e4323323247c0a8190ed885fb734bfcd11853"
ANSWERS_COUNT = 725
ANSWERS_SHA256 = "31330cbe412018d0ea94991c321d032def17def40e725fcadc90363b11cebda9"

RULES = ("standalone", "explicit_arg", "explicit_altsection", "explicit_reciprocal")
REVISION_STATUSES = ("five_letter_index", "dump_parent", "unavailable")
PROVENANCE_KEYS = frozenset(
    {
        "normalized",
        "source_case",
        "page",
        "parent",
        "rule",
        "pos",
        "sense_index",
        "head_template",
        "head_arg",
        "alt_section",
        "pointer_locator",
        "pointer_sense",
        "pointer_target",
        "locator",
        "page_id",
        "revision_id",
        "timestamp",
        "revision_status",
    }
)

DUMP_SHA256 = "0b7f554b1884e52e1c06de74cecab5e370c6b9f765711cedb0759f6d14c5e719"
WIKTEXTRACT_COMMIT = "ccec6f120efedd84f57fe0f1631e89408e9cb62a"
WIKITEXTPROCESSOR_COMMIT = "4deed5191c9e4cb61ee1a4c822e3f6686ae8541b"
FIVE_LETTER_INDEX_SHA256 = "b140a40bf5d0e327d99d1ef032719b83319387a67b35defd7736e2f6264ab70d"
WIKTIONARY_CHUNKS = 99
WIKTIONARY_RECORDS = 125730
WIKTIONARY_TRANSFORM = (
    "tightened explicit forms + relationship eligibility "
    "(standalone|explicit_arg|explicit_altsection|explicit_reciprocal)"
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


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


def load_development_seed_words() -> tuple[list[str], int]:
    """Load and validate the development pack for seed generation."""
    pack, _ = load(PACKS / "development-en-US-v1.json")
    validate_development(pack)
    format_version = pack["formatVersion"]
    require(isinstance(format_version, int), "development formatVersion must be an integer")
    return words(pack.get("words"), "development words"), format_version


def load_baseline() -> tuple[list[str], bytes]:
    raw = (PACKS / BASELINE_FILE).read_bytes()
    require(
        raw.endswith(b"\n") and b"\r" not in raw,
        "baseline file must use LF line endings with a trailing newline",
    )
    entries = raw.decode("ascii").splitlines()
    require(
        len(entries) == BASELINE_COUNT,
        f"baseline count is {len(entries)}, expected frozen {BASELINE_COUNT}",
    )
    require(
        sha256(raw) == BASELINE_SHA256,
        "baseline file hash does not match the frozen baseline",
    )
    require(
        all(WORD.fullmatch(entry) is not None for entry in entries),
        "baseline entries must be lowercase five-letter ASCII",
    )
    require(len(set(entries)) == len(entries), "baseline file contains a duplicate")
    require(entries == sorted(entries), "baseline file must be sorted")
    return entries, raw


def check_provenance_row(row: object, index: int) -> None:
    label = f"provenance row {index + 1}"
    require(isinstance(row, dict), f"{label} must be a JSON object")
    assert isinstance(row, dict)
    keys = set(row.keys())
    require(
        keys == PROVENANCE_KEYS,
        f"{label} has an unexpected schema: "
        f"missing={sorted(PROVENANCE_KEYS - keys)} "
        f"unexpected={sorted(keys - PROVENANCE_KEYS)}",
    )
    normalized = row["normalized"]
    source_case = row["source_case"]
    page = row["page"]
    parent = row["parent"]
    rule = row["rule"]
    require(
        isinstance(normalized, str) and WORD.fullmatch(normalized) is not None,
        f"{label} has an invalid normalized spelling",
    )
    require(
        isinstance(source_case, str)
        and SOURCE_CASE.fullmatch(source_case) is not None
        and source_case.lower() == normalized,
        f"{label} source_case must be the five-letter source spelling of normalized",
    )
    require(rule in RULES, f"{label} has an unknown rule {rule!r}")
    locator = row["locator"]
    require(
        isinstance(locator, str) and LOCATOR.fullmatch(locator) is not None,
        f"{label} has an invalid record locator",
    )
    pos = row["pos"]
    require(isinstance(pos, str) and bool(pos), f"{label} has an invalid pos")
    require(
        isinstance(page, str) and bool(page),
        f"{label} must carry a non-empty evidence page",
    )
    status = row["revision_status"]
    require(status in REVISION_STATUSES, f"{label} has an unknown revision_status")
    page_id = row["page_id"]
    revision_id = row["revision_id"]
    timestamp = row["timestamp"]
    if status == "unavailable":
        require(
            page_id is None and revision_id is None and timestamp is None,
            f"{label} with unavailable revision_status must carry null revision ids",
        )
    else:
        require(
            isinstance(page_id, str)
            and bool(page_id)
            and isinstance(revision_id, str)
            and bool(revision_id)
            and isinstance(timestamp, str)
            and bool(timestamp),
            f"{label} with revision_status {status} must carry page/revision/timestamp",
        )
    if rule == "standalone":
        require(parent is None, f"{label} standalone row must have a null parent")
        require(page == source_case, f"{label} standalone row page must equal source_case")
        require(
            isinstance(row["sense_index"], int) and row["sense_index"] >= 0,
            f"{label} standalone row must carry sense_index and locator",
        )
        require(
            row["head_template"] is None
            and row["head_arg"] is None
            and row["alt_section"] is None
            and row["pointer_locator"] is None
            and row["pointer_sense"] is None
            and row["pointer_target"] is None,
            f"{label} standalone row must leave non-standalone evidence fields null",
        )
    elif rule == "explicit_arg":
        require(
            isinstance(parent, str) and bool(parent) and page == parent,
            f"{label} explicit_arg row page must equal its parent",
        )
        require(
            row["sense_index"] is None,
            f"{label} explicit_arg row must leave sense_index null",
        )
        require(
            isinstance(row["head_template"], str)
            and bool(row["head_template"])
            and isinstance(row["head_arg"], str)
            and bool(row["head_arg"]),
            f"{label} explicit_arg row must carry head_template/head_arg and locator",
        )
        require(
            row["alt_section"] is None
            and row["pointer_locator"] is None
            and row["pointer_sense"] is None
            and row["pointer_target"] is None,
            f"{label} explicit_arg row must leave non-arg evidence fields null",
        )
    elif rule == "explicit_altsection":
        require(
            isinstance(parent, str) and bool(parent) and page == parent,
            f"{label} explicit_altsection row page must equal its parent",
        )
        require(
            isinstance(row["sense_index"], int) and row["sense_index"] >= 0,
            f"{label} explicit_altsection row must carry sense_index and locator",
        )
        require(
            isinstance(row["alt_section"], str) and bool(row["alt_section"]),
            f"{label} explicit_altsection row must carry alt_section and locator",
        )
        require(
            row["head_template"] is None
            and row["head_arg"] is None
            and row["pointer_locator"] is None
            and row["pointer_sense"] is None
            and row["pointer_target"] is None,
            f"{label} explicit_altsection row must leave non-altsection evidence fields null",
        )
    else:  # explicit_reciprocal
        require(
            isinstance(parent, str) and bool(parent) and page == parent,
            f"{label} explicit_reciprocal row page must equal its parent",
        )
        require(
            row["sense_index"] is None,
            f"{label} explicit_reciprocal row must leave sense_index null",
        )
        require(
            row["head_template"] is None
            and row["head_arg"] is None
            and row["alt_section"] is None,
            f"{label} explicit_reciprocal row must leave non-reciprocal evidence fields null",
        )
        pointer_locator = row["pointer_locator"]
        require(
            isinstance(pointer_locator, str)
            and LOCATOR.fullmatch(pointer_locator) is not None,
            f"{label} explicit_reciprocal row must carry pointer_locator and locator",
        )
        require(
            isinstance(row["pointer_sense"], int) and row["pointer_sense"] >= 0,
            f"{label} explicit_reciprocal row must carry pointer_sense and locator",
        )
        require(
            row["pointer_target"] == parent,
            f"{label} explicit_reciprocal row must carry pointer_target and locator",
        )


def load_provenance() -> tuple[list[dict[str, object]], bytes]:
    raw = (PACKS / PROVENANCE_FILE).read_bytes()
    require(raw.endswith(b"\n"), "provenance file must end with a newline")
    lines = raw.decode("utf-8").splitlines()
    require(all(line.strip() for line in lines), "provenance file contains a blank line")
    rows = [json.loads(line) for line in lines]
    for index, row in enumerate(rows):
        check_provenance_row(row, index)
    normalized = [row["normalized"] for row in rows]
    require(
        len(set(normalized)) == len(normalized),
        "provenance normalized spellings contain a duplicate",
    )
    require(
        normalized == sorted(normalized),
        "provenance rows must be sorted by normalized spelling",
    )
    return rows, raw


def load_provenance_manifest() -> dict[str, object]:
    raw = (PACKS / PROVENANCE_MANIFEST_FILE).read_bytes()
    manifest = json.loads(raw.decode("utf-8"))
    require(isinstance(manifest, dict), "provenance manifest must be a JSON object")
    return manifest


def validate_chain(
    pack: dict[str, object], pack_raw: bytes
) -> tuple[list[str], bytes]:
    """Assert the full checked-in evidence chain; return pass lines and prov bytes."""
    baseline, baseline_raw = load_baseline()
    baseline_set = set(baseline)
    baseline_line = (
        "word-pack chain OK: baseline "
        f"{len(baseline)} entries, sha256 {sha256(baseline_raw)} "
        "(sorted unique lowercase ASCII)"
    )

    accepted = words(pack.get("acceptedGuesses"), "daily accepted guesses")
    answers = words(pack.get("answers"), "daily answers")
    require(
        len(answers) == ANSWERS_COUNT,
        f"ordered answer count is {len(answers)}, expected {ANSWERS_COUNT}",
    )
    projection = "".join(f"{entry}\n" for entry in answers).encode("ascii")
    require(
        sha256(projection) == ANSWERS_SHA256,
        "ordered answer projection hash does not match the pinned answers",
    )
    answers_line = (
        "word-pack chain OK: ordered answers "
        f"{len(answers)} entries, projection sha256 {sha256(projection)}"
    )

    rows, prov_raw = load_provenance()
    prov_set = {row["normalized"] for row in rows}
    rule_counts = Counter(str(row["rule"]) for row in rows)
    status_counts = Counter(str(row["revision_status"]) for row in rows)
    provenance_line = (
        "word-pack chain OK: provenance "
        f"{len(rows)} rows, sha256 {sha256(prov_raw)} "
        "(rules "
        + " ".join(f"{rule}={rule_counts.get(rule, 0)}" for rule in RULES)
        + "; revisions "
        + " ".join(f"{status}={status_counts.get(status, 0)}" for status in REVISION_STATUSES)
        + ")"
    )

    final_set = set(accepted)
    missing_baseline = baseline_set - final_set
    require(
        not missing_baseline,
        "baseline is not preserved in final accepted guesses: "
        f"{len(missing_baseline)} baseline entries missing",
    )
    missing_from_final = prov_set - final_set
    require(
        not missing_from_final,
        "every provenance row must be in final accepted guesses: "
        f"{len(missing_from_final)} provenance rows missing from final",
    )
    without_evidence = final_set - baseline_set - prov_set
    require(
        not without_evidence,
        "every addition over baseline must have a provenance row: "
        f"{len(without_evidence)} final entries without baseline or provenance evidence",
    )
    require(
        final_set == baseline_set | prov_set,
        "final accepted guesses must equal baseline union provenance.normalized",
    )
    set_line = (
        "word-pack chain OK: final accepted "
        f"{len(final_set)} entries equal baseline union provenance "
        f"({len(final_set - baseline_set)} additions over baseline)"
    )

    manifest = load_provenance_manifest()
    require(manifest.get("formatVersion") == 1, "provenance manifest formatVersion must be 1")
    require(
        manifest.get("provenanceFile") == PROVENANCE_FILE,
        "provenance manifest provenanceFile must name the provenance file",
    )
    require(
        manifest.get("packFile") == f"{DAILY_ID}.json",
        "provenance manifest packFile must name the daily pack",
    )
    require(
        manifest.get("provenanceCount") == len(rows),
        "provenance manifest count does not match provenance rows: "
        f"{manifest.get('provenanceCount')} vs {len(rows)}",
    )
    require(
        manifest.get("wiktionaryCount") == len(rows),
        "provenance manifest wiktionary count does not match provenance rows",
    )
    require(
        manifest.get("acceptedGuessCount") == len(final_set),
        "provenance manifest accepted count does not match final accepted guesses",
    )
    require(
        manifest.get("baselineCount") == len(baseline_set),
        "provenance manifest baseline count does not match the frozen baseline",
    )
    require(
        manifest.get("baselineSha256") == BASELINE_SHA256 == sha256(baseline_raw),
        "provenance manifest baseline hash does not match the frozen baseline file",
    )
    require(
        manifest.get("provenanceSha256") == sha256(prov_raw),
        "provenance file hash does not match its manifest",
    )
    require(
        manifest.get("packSha256") == sha256(pack_raw),
        "pack file hash does not match the provenance manifest",
    )
    require(
        manifest.get("wiktionaryTransform") == WIKTIONARY_TRANSFORM,
        "provenance manifest transform record changed",
    )
    inputs = manifest.get("inputs")
    require(isinstance(inputs, dict), "provenance manifest inputs must be an object")
    assert isinstance(inputs, dict)
    require(
        inputs.get("dumpSha256") == DUMP_SHA256,
        "provenance manifest dump pin does not match the pinned Wiktionary dump",
    )
    require(
        inputs.get("wiktextractCommit") == WIKTEXTRACT_COMMIT,
        "provenance manifest wiktextract pin changed",
    )
    require(
        inputs.get("wikitextprocessorCommit") == WIKITEXTPROCESSOR_COMMIT,
        "provenance manifest wikitextprocessor pin changed",
    )
    require(
        inputs.get("fiveLetterRevisionIndexSha256") == FIVE_LETTER_INDEX_SHA256,
        "provenance manifest revision-index pin changed",
    )
    require(
        inputs.get("wiktionaryJsonChunks") == WIKTIONARY_CHUNKS,
        "provenance manifest chunk count does not match the pinned extraction",
    )
    require(
        inputs.get("wiktionaryJsonRecords") == WIKTIONARY_RECORDS,
        "provenance manifest record count does not match the pinned extraction",
    )
    require(
        sum(rule_counts.get(rule, 0) for rule in RULES) == len(rows),
        "provenance rule counts do not sum to the provenance row count",
    )
    require(
        sum(status_counts.get(status, 0) for status in REVISION_STATUSES) == len(rows),
        "provenance revision-status counts do not sum to the provenance row count",
    )
    for field in (
        "supportedRelationshipTargets",
        "referencedRelationshipTargets",
        "unresolvedRelationshipTargets",
        "candidateNeededRelationshipTargets",
        "absentNeededRelationshipTargets",
        "uncoveredNeededRelationshipTargets",
        "targetJsonRecords",
        "targetJsonChunks",
        "targetJsonTitles",
    ):
        value = inputs.get(field)
        require(
            isinstance(value, int) and value >= 0,
            f"provenance manifest inputs.{field} must be a non-negative integer",
        )
    require(
        inputs.get("uncoveredNeededRelationshipTargets") == 0,
        "every absent relationship target needed by candidate five-letter "
        "standalone/form records must be present in the targeted-coverage "
        "title lists: "
        f"{inputs.get('uncoveredNeededRelationshipTargets')} uncovered",
    )
    require(
        inputs.get("absentNeededRelationshipTargets")
        <= inputs.get("candidateNeededRelationshipTargets"),
        "provenance manifest absent needed targets cannot exceed candidate "
        "needed targets",
    )
    require(
        inputs.get("absentNeededRelationshipTargets") <= inputs.get("targetJsonTitles"),
        "provenance manifest absent needed targets cannot exceed the "
        "targeted-coverage title count",
    )
    require(
        inputs.get("targetJsonChunks") >= 1 and inputs.get("targetJsonRecords") >= 1,
        "provenance manifest target-coverage extraction must be non-empty",
    )
    sidecar_raw = (PACKS / PARENT_REVISIONS_FILE).read_bytes()
    require(
        sha256(sidecar_raw) == inputs.get("parentRevisionsSha256"),
        "parent-revisions sidecar hash does not match the provenance manifest",
    )
    sidecar = json.loads(sidecar_raw.decode("utf-8"))
    require(isinstance(sidecar, dict), "parent-revisions sidecar must be a JSON object")
    found = sidecar.get("found")
    missing_sidecar = sidecar.get("missing")
    require(
        isinstance(found, dict) and isinstance(missing_sidecar, list),
        "parent-revisions sidecar must carry found/missing maps",
    )
    dump_parent_pages = {
        str(row["page"]) for row in rows if row["revision_status"] == "dump_parent"
    }
    uncovered = dump_parent_pages - set(found.keys())
    require(
        not uncovered,
        "every dump_parent provenance page must be covered by the parent-revisions sidecar: "
        f"{len(uncovered)} pages uncovered",
    )
    manifest_line = (
        "word-pack chain OK: pack sha256 "
        f"{sha256(pack_raw)} agrees across pack and provenance manifests; "
        f"parent-revisions sha256 {sha256(sidecar_raw)} agrees with provenance manifest"
    )
    return [baseline_line, answers_line, provenance_line, set_line, manifest_line], prov_raw


def validate_one(
    pack_id: str,
    validator: Callable[[dict[str, object]], tuple[int, int]],
) -> tuple[dict[str, object], bytes, bytes, tuple[int, int]]:
    pack_path = PACKS / f"{pack_id}.json"
    manifest_path = PACKS / f"{pack_id}.manifest.json"
    pack, raw = load(pack_path)
    counts = validator(pack)
    expected = manifest_bytes(pack, raw, counts[0], counts[1])
    return pack, raw, expected, counts


def builder_intermediate_paths() -> dict[str, Path]:
    """Resolve the maintenance transform's pinned intermediate defaults.

    Paths come from ``build_accepted_guesses.pinned_defaults()`` so the gate
    stays in sync by construction. Import, syntax, and resolution failures
    raise ValueError and are gate errors, never skips.
    """
    try:
        spec = importlib.util.spec_from_file_location(
            "gridrace_builder_defaults_probe", str(SCRIPTS / "build_accepted_guesses.py")
        )
        if spec is None or spec.loader is None:
            raise ValueError("cannot locate loader for scripts/build_accepted_guesses.py")
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)  # type: ignore[union-attr]
        defaults = module.pinned_defaults()
    except Exception as error:
        raise ValueError(
            f"source gate cannot load scripts/build_accepted_guesses.py: {error}"
        ) from error
    return {key: Path(value) for key, value in defaults.items()}


def probe_intermediates() -> int:
    """Report which pinned intermediates exist; informational only, exit 0."""
    try:
        paths = builder_intermediate_paths()
    except ValueError as error:
        print(f"word-pack intermediates probe: unloadable ({error})")
        return 0
    for key in sorted(paths):
        print(f"word-pack intermediates probe: {key} {'present' if paths[key].exists() else 'ABSENT'}")
    return 0


def run_source_gate(pack_raw: bytes, prov_raw: bytes, prov_manifest_raw: bytes) -> None:
    """Regenerate pack+provenance+manifest from pinned intermediates and compare bytes.

    Fail-closed: every failure mode raises. Missing intermediates report
    UNAVAILABLE instead of passing.
    """
    paths = builder_intermediate_paths()
    absent = [key for key, path in paths.items() if not path.exists()]
    if absent:
        raise ValueError(
            "word-pack source UNAVAILABLE: pinned Wiktionary intermediates not present "
            f"({', '.join(sorted(absent))}); no pass earned (use --checked-in-only "
            "for the portable gate or --probe-intermediates to inspect)"
        )
    started = time.monotonic()
    tmpdir = Path(tempfile.mkdtemp(prefix="wordpack-source-"))
    try:
        seed = tmpdir / f"{DAILY_ID}.json"
        out_provenance = tmpdir / PROVENANCE_FILE
        out_manifest = tmpdir / PROVENANCE_MANIFEST_FILE
        seed.write_bytes(pack_raw)
        completed = subprocess.run(
            [
                sys.executable,
                str(SCRIPTS / "build_accepted_guesses.py"),
                "--pack",
                str(seed),
                "--provenance",
                str(out_provenance),
                "--provenance-manifest",
                str(out_manifest),
            ],
            cwd=str(ROOT),
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            check=False,
        )
        require(
            completed.returncode == 0,
            "source regeneration failed: " + (completed.stdout or "")[-2000:],
        )
        regen_pack = seed.read_bytes()
        regen_prov = out_provenance.read_bytes()
        regen_manifest = out_manifest.read_bytes()
        require(
            sha256(regen_pack) == sha256(pack_raw),
            "regenerated pack hash does not match the checked-in pack",
        )
        require(
            sha256(regen_prov) == sha256(prov_raw),
            "regenerated provenance hash does not match checked-in provenance",
        )
        require(
            regen_manifest == prov_manifest_raw,
            "regenerated provenance manifest bytes do not match the checked-in "
            "provenance manifest",
        )
    finally:
        shutil.rmtree(tmpdir, ignore_errors=True)
    elapsed = time.monotonic() - started
    print(
        "word-pack source OK: regenerated pack, provenance, and "
        "provenance-manifest hashes/bytes match checked-in files in "
        f"{elapsed:.1f}s",
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--write-manifest",
        action="store_true",
        help="replace pack manifests with deterministic values after validating packs",
    )
    parser.add_argument(
        "--checked-in-only",
        action="store_true",
        help="validate checked-in packs and manifests without the pinned source corpus",
    )
    parser.add_argument(
        "--probe-intermediates",
        action="store_true",
        help="report which pinned intermediates exist; informational only",
    )
    args = parser.parse_args()

    if args.probe_intermediates:
        return probe_intermediates()

    try:
        dev_pack, dev_raw, dev_expected, development = validate_one(
            "development-en-US-v1", validate_development
        )
        daily_pack, daily_raw, daily_expected, daily = validate_one(
            DAILY_ID, validate_daily
        )
        chain_lines, prov_raw = validate_chain(daily_pack, daily_raw)
        dev_manifest_path = PACKS / "development-en-US-v1.manifest.json"
        daily_manifest_path = PACKS / f"{DAILY_ID}.manifest.json"
        if args.write_manifest:
            dev_manifest_path.write_bytes(dev_expected)
            daily_manifest_path.write_bytes(daily_expected)
            require(
                dev_manifest_path.read_bytes() == dev_expected
                and daily_manifest_path.read_bytes() == daily_expected,
                "manifest refresh did not persist; re-run the builder first, "
                "then --write-manifest, then the plain gates",
            )
            print("word-pack manifests refreshed and re-verified")
        else:
            require(
                dev_manifest_path.read_bytes() == dev_expected,
                "development-en-US-v1.manifest.json is stale "
                "(run with --write-manifest to refresh after validating the chain)",
            )
            require(
                daily_manifest_path.read_bytes() == daily_expected,
                "daily-classic-en-US-v1.manifest.json is stale "
                "(run with --write-manifest to refresh after validating the chain; "
                "if the chain itself fails, re-run "
                "python3 scripts/build_accepted_guesses.py first)",
            )
        for line in chain_lines:
            print(line)
        if not args.checked_in_only:
            run_source_gate(
                daily_raw,
                prov_raw,
                (PACKS / PROVENANCE_MANIFEST_FILE).read_bytes(),
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
