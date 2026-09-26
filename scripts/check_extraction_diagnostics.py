#!/usr/bin/env python3
"""Regroup Wiktextract console diagnostics with an overlap-safe classifier.

Method: scan preserved ``chunk-*.console`` files for lines containing
``ERROR:`` and bucket each line by substring match. This is diagnostics
accounting only -- it never reads the dump, the SQLite page cache, or any
extraction JSONL, and it changes no production transform.

Corrected rule: membership-related and non-membership-related substring
matches are computed independently (order-free). A line matching at least
one term from EACH list resolves to ``ambiguous_overlap`` -- a non-silent,
reviewable bucket -- and never to whichever list happened to be checked
first. Lines matching only one list keep their one-sided bucket; lines
matching neither stay ``unresolved_context``. The classifier is
deterministic: boolean flag combination only, no set-order dependence, and
all reported aggregates are emitted in sorted order.

The legacy ``scripts/analyze_validation.py::classify_error`` checked the
non-membership list first, so an overlapping line was silently filed as
``non_membership_field`` (harmless) purely by check order. The only two
overlapping lines in the preserved run-2 consoles are both of this shape --
a translations-module error on a page whose TITLE contains "inflection":

  1. ``inflection/English/noun: ERROR: LUA error in #invoke('translations',
     'show', 'interwiki=tpos') parent ('Template:t+', ...) at ['inflection',
     'Template:t+', '#invoke', '#invoke']``
     matches non-membership term ``translation`` (the failing module) AND
     membership term ``inflection`` (the page title, not a field).
     Legacy verdict: ``non_membership_field``. Corrected: ``ambiguous_overlap``.
  2. ``point of inflection/English/noun: ERROR: LUA error in
     #invoke('translations', 'show', 'interwiki=tpos') parent
     ('Template:t+', ...) at ['point of inflection', ...]``
     same double match (``translation`` + title word ``inflection``).
     Legacy verdict: ``non_membership_field``. Corrected: ``ambiguous_overlap``.

These are the only 2 overlaps among 9,022 ERROR lines; the rule generalizes
to any future line matching both term lists.

Usage:
  python3 scripts/check_extraction_diagnostics.py --consoles <console-dir>
  python3 scripts/check_extraction_diagnostics.py --consoles <dir> --json out.json

CI does not run this script: its inputs are cache-resident preserved
consoles, not repository fixtures (see docs/word-pack-diagnostics.md).
"""

from __future__ import annotations

import argparse
import json
import re
from collections import Counter
from pathlib import Path

# Same term lists as scripts/analyze_validation.py::classify_error, kept
# side by side so neither list shadows the other.
NON_MEMBERSHIP_TERMS = (
    "translation", "etymolog", "cite-", "#invoke('quote", "pronunciation",
    "audio", "rhym", "#invoke('string/templates", "#invoke('number list",
    "#invoke('links/templates", "#invoke('columns", "#invoke('mapframe",
    "#invoke('etymon", "template:+obj", "#invoke('usex/templates",
    "#invoke('nyms", "#invoke('affix/templates",
)
MEMBERSHIP_TERMS = (
    "headword", "inflection", "form-of", "form of", "alternative forms",
    "labels", "poscatboiler",
)

NON_MEMBERSHIP_FIELD = "non_membership_field"
POTENTIAL_MEMBERSHIP_FIELD = "potential_membership_field"
UNRESOLVED_CONTEXT = "unresolved_context"
AMBIGUOUS_OVERLAP = "ambiguous_overlap"


def classify(line: str) -> str:
    """Order-free bucket: any line matching both lists is ambiguous."""
    lowered = line.lower()
    has_non = any(term in lowered for term in NON_MEMBERSHIP_TERMS)
    has_mem = any(term in lowered for term in MEMBERSHIP_TERMS)
    if has_non and has_mem:
        return AMBIGUOUS_OVERLAP
    if has_non:
        return NON_MEMBERSHIP_FIELD
    if has_mem:
        return POTENTIAL_MEMBERSHIP_FIELD
    return UNRESOLVED_CONTEXT


def classify_legacy(line: str) -> str:
    """Legacy order-dependent bucket (non-membership checked first)."""
    lowered = line.lower()
    if any(term in lowered for term in NON_MEMBERSHIP_TERMS):
        return NON_MEMBERSHIP_FIELD
    if any(term in lowered for term in MEMBERSHIP_TERMS):
        return POTENTIAL_MEMBERSHIP_FIELD
    return UNRESOLVED_CONTEXT


def extract_title(line: str) -> str:
    """Page title by the same rule as analyze_validation (pre-slash head)."""
    return line.split("/", 1)[0].split(":", 1)[0]


def signature(line: str) -> str:
    """Group key: failing invoke module + parent template (or error kind)."""
    if "Template nesting error" in line:
        return "Template-nesting: inflection-templates | be-conjugation"
    if "Unimplemented unsupported title" in line:
        return "Unimplemented unsupported title"
    if "#invoke('debug'" in line:
        return "invoke:debug/error | Template:error (sq-decl template)"
    module = re.search(r"#invoke\('([^']+)'", line)
    parent = re.search(r"parent \('([^']+)'", line)
    return (
        f"invoke:{module.group(1) if module else '?'}"
        f" | parent:{parent.group(1) if parent else '?'}"
    )


def iter_error_lines(consoles: Path):
    """Yield (console_name, line) for ERROR lines in gated console files.

    The sibling gate (console counts only when chunk-*.jsonl or
    chunk-*.failed exists) replicates analyze_validation.py.
    """
    for path in sorted(consoles.glob("chunk-*.console")):
        if not path.with_suffix(".jsonl").exists() and not path.with_suffix(".failed").exists():
            continue
        for line in path.read_text(errors="replace").splitlines():
            if "ERROR:" in line:
                yield path.name, line


def analyze(consoles: Path) -> dict:
    counts: Counter = Counter()
    titles: dict[str, set[str]] = {}
    groups: dict[tuple[str, str], dict] = {}
    legacy_counts: Counter = Counter()
    overlap_lines: list[dict[str, str]] = []
    consoles_seen: list[str] = []
    for path in sorted(consoles.glob("chunk-*.console")):
        if not path.with_suffix(".jsonl").exists() and not path.with_suffix(".failed").exists():
            continue
        consoles_seen.append(path.name)
    for name, line in iter_error_lines(consoles):
        bucket = classify(line)
        legacy = classify_legacy(line)
        counts[bucket] += 1
        legacy_counts[legacy] += 1
        titles.setdefault(bucket, set()).add(extract_title(line))
        key = (bucket, signature(line))
        entry = groups.setdefault(key, {"events": 0, "titles": set(), "examples": []})
        entry["events"] += 1
        entry["titles"].add(extract_title(line))
        if len(entry["examples"]) < 2:
            entry["examples"].append(f"[{name}] {line}")
        if bucket == AMBIGUOUS_OVERLAP:
            overlap_lines.append({"console": name, "legacy": legacy, "line": line})
    return {
        "consoles": consoles_seen,
        "counts": dict(sorted(counts.items())),
        "unique_titles": {k: len(v) for k, v in sorted(titles.items())},
        "groups": [
            {
                "bucket": bucket,
                "signature": sig,
                "events": entry["events"],
                "titles": sorted(entry["titles"]),
                "examples": entry["examples"],
            }
            for (bucket, sig), entry in sorted(groups.items())
        ],
        "legacy_counts": dict(sorted(legacy_counts.items())),
        "overlap_lines": overlap_lines,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--consoles", required=True, type=Path,
                        help="preserved console dir (chunk-*.console + siblings)")
    parser.add_argument("--json", required=False, type=Path, default=None,
                        help="optional path for the machine-readable report")
    args = parser.parse_args()
    if not args.consoles.is_dir():
        print(f"consoles dir missing: {args.consoles}", flush=True)
        return 2
    report = analyze(args.consoles)
    lines = [
        f"consoles included: {len(report['consoles'])}",
        "events by bucket (corrected classifier):",
    ]
    for bucket, count in sorted(report["counts"].items()):
        lines.append(
            f"  {bucket:26s} {count:5d} events on "
            f"{report['unique_titles'][bucket]} titles"
        )
    lines.append("legacy classifier buckets (for comparison):")
    for bucket, count in sorted(report["legacy_counts"].items()):
        lines.append(f"  {bucket:26s} {count:5d} events")
    lines.append("groups (bucket | signature | events | titles):")
    for group in report["groups"]:
        lines.append(
            f"  [{group['bucket']}] {group['signature']}: "
            f"{group['events']} events on {len(group['titles'])} titles"
        )
    if report["overlap_lines"]:
        lines.append("ambiguous overlaps (silent under legacy order):")
        for item in report["overlap_lines"]:
            lines.append(f"  [{item['console']}] legacy={item['legacy']}: {item['line']}")
    print("\n".join(lines))
    if args.json is not None:
        args.json.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n",
                             encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
