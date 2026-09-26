#!/usr/bin/env python3
"""Build the finalized Daily Classic accepted-guess set from pinned inputs.

Source policy (tightened explicit-forms route):
- Baseline: every spelling in ``baseline-accepted-frozen.txt`` (8508 entries,
  sorted-LF SHA-256 ``f045112e...``) is preserved verbatim. Baseline-only
  spellings map to that frozen artifact; no Wiktionary provenance is invented
  for them, and they do not appear in the per-word PROVENANCE.jsonl.
- Expansion: English Wiktionary only (release enwiktionary-20260901). No
  12dicts, no OEWN, no allow/deny lists, no generated morphology, no LLM
  judgments. Failed parsing is never treated as invalid-vocabulary evidence;
  every addition needs one affirmative evidence path below.
- Parent eligibility is record-level: English record, lexical POS (proper-name,
  abbreviation/initialism-only, nonlexical-POS, and misspelling-only records
  excluded; ``contraction`` POS stays eligible), with at least one
  non-misspelling sense. Classification happens before case normalization;
  output is sorted unique lowercase ASCII five-letter spellings with LF ends.

Tightened form rule: a five-letter ``forms`` value on an eligible parent
record is admitted ONLY when the parent record itself has relationship-level
eligibility (below) and the value passes metadata/semantic exclusions and one
of three explicit-evidence paths (priority order for provenance):
  1. ``explicit_arg`` -- the value matches a captured head-template argument
     exactly (same ``explicit_template_tokens`` extraction as the reviewed
     analysis: full-string five-letter match after optional ``[[ ]]``/``< >``
     wrappers);
  2. ``explicit_altsection`` -- the value occurs literally (case-sensitive
     TOKEN match) inside an ``Alternative forms``/``Alternative spellings``
     subsection of the parent's own English section. Whole-section incidental
     mentions do NOT qualify;
  3. ``explicit_reciprocal`` -- some English record whose title lowercases to
     the form has a non-misspelling sense whose ``alt_of``/``form_of`` points
     at the parent title exactly. The pointer target is the parent by
     construction, so the reciprocal target check reduces to the parent
     independence check.
Form exclusions: metadata pseudo-forms (``canonical``, ``class``,
``hiragana``, ``romanization``, ``table-tags``) stay excluded, and forms
tagged ``misspelling``/``abbreviation``/``acronym``/``initialism`` are
excluded at the form level even when the parent record is eligible.
Expansion-only template-computed forms stay excluded for this iteration.

Relationship-level eligibility (standalone and explicit parents alike): a
five-letter headword record qualifies ONLY if it carries at least one
independent eligible ordinary sense. A non-relationship sense always counts
as independent. A ``form_of``/``alt_of`` relationship sense
(``form-of``/``alt-of`` tags or ``form_of``/``alt_of`` fields) counts as
independent ONLY if at least one of its targets affirmatively has an
eligible ordinary lexical sense. Targets are classified source-wide over
the pinned 125,730-record JSONL extraction PLUS the bounded
targeted-coverage extraction (``--target-json``) over every absent target
title, keyed on the exact (pre-normalization) title with each record
classified before case normalization; output stays lowercase:
- excluded: titles with English records where EVERY record is
  abbreviation/initialism-only or proper-name-only under the same
  record-level policy above (``eligibility()`` outcomes
  ``abbreviation_initialism`` / ``proper_name``);
- supported: titles with at least one eligible English record
  (``eligibility(record) == "eligible"``) carrying an ordinary sense (a
  valid non-misspelling NON-relationship sense), minus the excluded set, so
  the two sets are disjoint by construction. Ordinary senses on
  proper-name-only, abbreviation/initialism-only, nonlexical-POS,
  misspelling-only, or otherwise ineligible records confer no support.
  Pointer-only titles never support, closing depth-2 absence leaks through
  pointer chains.
A target with no English records anywhere (206 such coverage titles under
the pinned inputs; each run reports the live count), a target whose records are all
misspelling-only/nonlexical/ineligible, or any otherwise unresolvable
target is in NEITHER set: it is non-evidence and cannot support acceptance,
so the sponsoring form needs another qualifying path or it drops. This is
fail-closed by design: absence of evidence is never affirmative evidence.
A relationship-tagged sense listing no explicit alt_of/form_of target at
all fails closed (it qualifies nothing). Aggregate invariant: every
relationship target absent from the pinned 99-chunk JSONL but needed by a
candidate five-letter standalone/form record must be present in the
targeted-coverage title lists; otherwise the run refuses (STOP condition).
Words with
any independent eligible ordinary sense are preserved (targets with an
ordinary sense alongside initialism/proper-name senses keep supporting);
the standalone winner (and every explicit sponsoring parent) is the
deterministic minimum over qualifying records only.

Provenance: one PROVENANCE.jsonl row per Wiktionary-supplied normalized
spelling (standalone winners first, else the winning explicit path above).
Every row carries a compact deterministic record locator
(``chunk-*.jsonl:LINE``, 1-based JSONL line number in sorted-chunk
streaming order) identifying the exact extracted record behind the row --
the standalone winner, or the sponsoring parent record for explicit rows --
plus rule-specific relationship evidence: standalone rows cite the
qualifying ``sense_index``; ``explicit_arg`` rows cite the head-template
name and its top-level argument key (``head_arg``, sorted-first on
collision); ``explicit_altsection`` rows cite the matched subsection heading
(``alt_section``) and the parent's first qualifying ``sense_index`` (the
admission itself is section-local, not sense-specific); ``explicit_reciprocal``
rows cite the pointer record locator/sense (``pointer_locator``,
``pointer_sense``) and the pointer target title (``pointer_target``, the
parent by construction). Page+POS alone is ambiguous when several extracted
records share them; locator plus sense/template refs close that gap. Rows
stay compact single-line JSON with a uniform key set (null where a field
does not apply to the rule).
Five-letter evidence pages reuse ``wiktionary-five-letter-revision-
provenance.jsonl``; contributing non-five-letter parents come from a single
dump streaming pass over the pinned dump for those titles only. The result
is committed as ``shared/word-packs/daily-classic-en-US-v1-parent-
revisions.json`` and consumed via ``--extra-revisions`` (see SOURCES.md for
the exact regeneration command). A revision that is truly unavailable is
recorded as null with status ``unavailable`` -- never invented. (The fresh
SQLite page cache carries titles/bodies only, so there is no DB page_id to
fall back to.)

Maintenance (deterministic; run twice and compare hashes):
  python3 scripts/build_accepted_guesses.py
  python3 scripts/build_accepted_guesses.py  # identical output expected
  python3 scripts/check_word_pack.py --checked-in-only
  python3 scripts/check_word_pack.py  # source gate: temp-dir regen + compare
  python3 scripts/check_word_pack.py --write-manifest  # refresh pack manifest
To regenerate ``--extra-revisions``, see the dump-pass command in SOURCES.md.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sqlite3
import sys
from collections import defaultdict
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
PACKS = REPO / "shared/word-packs"

WORD = re.compile(r"[A-Za-z]{5}\Z", re.ASCII)
TOKEN = re.compile(r"(?<![A-Za-z])[A-Za-z]{5}(?![A-Za-z])")
EXCLUDED_POS = {
    "abbrev", "affix", "character", "circumfix", "combining_form",
    "infix", "interfix", "name", "phrase", "prefix", "prep_phrase",
    "adv_phrase", "proverb", "punct", "romanization", "root", "suffix",
    "syllable", "symbol", "unknown",
}
ABBREVIATION_TAGS = {"abbreviation", "acronym", "initialism"}
FORM_METADATA_TAGS = {"canonical", "class", "hiragana", "romanization", "table-tags"}
FORM_SEM_TAGS = {"misspelling", "abbreviation", "acronym", "initialism"}

BASELINE_SHA256 = "f045112edcf1fb2889b58a947f0e4323323247c0a8190ed885fb734bfcd11853"
ANSWERS_SHA256 = "31330cbe412018d0ea94991c321d032def17def40e725fcadc90363b11cebda9"
DUMP_SHA256 = "0b7f554b1884e52e1c06de74cecab5e370c6b9f765711cedb0759f6d14c5e719"
WIKTEXTRACT_COMMIT = "ccec6f120efedd84f57fe0f1631e89408e9cb62a"
WIKITEXTPROCESSOR_COMMIT = "4deed5191c9e4cb61ee1a4c822e3f6686ae8541b"
FIVE_LETTER_INDEX_SHA256 = "b140a40bf5d0e327d99d1ef032719b83319387a67b35defd7736e2f6264ab70d"

ADDENDUM = Path("/Users/tristan/Software/gridrace-corpus-validation-addendum-2026-09-08")
CACHE = Path("/Users/tristan/Library/Caches/GridRace/corpus-research-2026-09-08")
REVIEW = Path("/Users/tristan/Software/gridrace-corpus-validation-addendum-review-2026-09-08")

RULE_PRIORITY = {"standalone": -1, "explicit_arg": 0, "explicit_altsection": 1, "explicit_reciprocal": 2}


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def valid_senses(record: dict) -> list[dict]:
    return [s for s in record.get("senses", []) if "misspelling" not in s.get("tags", [])]


def eligibility(record: dict) -> str:
    if record.get("lang_code") != "en":
        return "non_english"
    pos = record.get("pos", "unknown")
    senses = valid_senses(record)
    if pos == "name":
        return "proper_name"
    record_tags = set(record.get("tags", []) or [])
    if pos == "abbrev" or (pos != "contraction" and (
        record_tags & ABBREVIATION_TAGS
        or (senses and all(set(s.get("tags", [])) & ABBREVIATION_TAGS for s in senses))
    )):
        return "abbreviation_initialism"
    if pos in EXCLUDED_POS:
        return "other_nonlexical_pos"
    if not senses:
        return "misspelling_only" if record.get("senses") else "no_valid_sense"
    return "eligible"


RELATIONSHIP_TAGS = {"form-of", "alt-of"}
# Record-level outcomes that exclude a form_of/alt_of TARGET from supporting
# a new spelling on its own. Only the two vocabulary-policy exclusions count;
# any other outcome (eligible, nonlexical POS, misspelling-only, or no pinned
# record at all) leaves the target non-excluded.
EXCLUDED_TARGET_OUTCOMES = {"abbreviation_initialism", "proper_name"}


def is_relationship_sense(sense: dict) -> bool:
    """True when a sense is (at least partly) a form_of/alt_of pointer."""
    tags = set(sense.get("tags", []) or [])
    if tags & RELATIONSHIP_TAGS:
        return True
    return bool(sense.get("alt_of") or sense.get("form_of"))


def build_target_exclusion(records: list[tuple[str, int, dict]]) -> set[str]:
    """Exact titles whose English records are all abbreviation/proper-only.

    Keyed on the exact pre-normalization title; each record is classified by
    ``eligibility()`` before case normalization. Titles with no pinned
    English record are absent from the returned set (not excluded).
    """
    by_word: dict[str, list[dict]] = defaultdict(list)
    for _, _, record in records:
        if record.get("lang_code") != "en":
            continue
        by_word[record.get("word", "")].append(record)
    return {
        word
        for word, group in by_word.items()
        if all(eligibility(item) in EXCLUDED_TARGET_OUTCOMES for item in group)
    }


def build_target_support(pool: list[tuple[str, int, dict]]) -> set[str]:
    """Exact titles with at least one eligible record carrying an ordinary sense.

    Only a valid (non-misspelling) NON-relationship sense on a record with
    ``eligibility(record) == "eligible"`` confers support: a title whose
    ordinary senses all sit on proper-name-only, abbreviation/initialism-only,
    nonlexical-POS, misspelling-only, or otherwise ineligible records has no
    eligible ordinary lexical sense of its own, so it cannot lend support.
    A title whose senses are all form_of/alt_of pointers likewise never
    supports (this also closes any depth-2 absence leak through pointer
    chains). Callers subtract the excluded set so support and exclusion stay
    disjoint; titles with no English records anywhere are in neither.
    """
    support: set[str] = set()
    for _, _, record in pool:
        if record.get("lang_code") != "en":
            continue
        if eligibility(record) != "eligible":
            continue
        word = record.get("word", "")
        if word in support:
            continue
        for sense in record.get("senses", []):
            if "misspelling" in (sense.get("tags") or []):
                continue
            if not is_relationship_sense(sense):
                support.add(word)
                break
    return support


def sense_qualifies(
    sense: dict, excluded_targets: set[str], supported_targets: set[str]
) -> bool:
    """True for ordinary senses and relationship senses at supported targets.

    Fail-closed: a form_of/alt_of sense qualifies ONLY if at least one listed
    target is affirmatively supported. Unclassified, missing, excluded-only,
    or otherwise unresolvable targets support nothing, and a
    relationship-tagged sense listing no explicit alt_of/form_of target at
    all fails closed (it cannot be assessed, so it qualifies nothing).
    """
    if not is_relationship_sense(sense):
        return True
    targets = sense_targets(sense)
    if not targets:
        return False
    return any(target in supported_targets for target in targets)


def first_qualifying_sense(
    record: dict, excluded_targets: set[str], supported_targets: set[str]
) -> int | None:
    """Index (into the record's own senses list) of the first qualifying sense."""
    for index, sense in enumerate(record.get("senses", [])):
        if "misspelling" in (sense.get("tags") or []):
            continue
        if sense_qualifies(sense, excluded_targets, supported_targets):
            return index
    return None


def explicit_template_tokens(record: dict) -> set[str]:
    values: list[str] = []

    def visit(value: object) -> None:
        if isinstance(value, str):
            values.append(value)
        elif isinstance(value, dict):
            for child in value.values():
                visit(child)
        elif isinstance(value, list):
            for child in value:
                visit(child)

    for template in record.get("head_templates", []):
        visit(template.get("args", {}))
    tokens = set()
    for value in values:
        cleaned = value.strip()
        match = re.fullmatch(r"(?:\[\[)?([A-Za-z]{5})(?:\]\])?(?:<[^>]+>)*", cleaned)
        if match:
            tokens.add(match.group(1))
    return tokens


def head_template_matches(record: dict, value: str) -> list[tuple[str, str]]:
    """Sorted (template name, top-level arg key) pairs carrying value exactly."""
    pairs = set()
    for template in record.get("head_templates", []):
        args = template.get("args", {})
        items = args.items() if isinstance(args, dict) else [("", args)]
        for key, node in items:
            seen: list[str] = []

            def visit(item: object) -> None:
                if isinstance(item, str):
                    seen.append(item)
                elif isinstance(item, dict):
                    for child in item.values():
                        visit(child)
                elif isinstance(item, list):
                    for child in item:
                        visit(child)

            visit(node)
            for raw in seen:
                match = re.fullmatch(r"(?:\[\[)?([A-Za-z]{5})(?:\]\])?(?:<[^>]+>)*", raw.strip())
                if match and match.group(1) == value:
                    pairs.add((template.get("name", ""), str(key)))
                    break
    return sorted(pair for pair in pairs if pair[0])


def head_templates_for_value(record: dict, value: str) -> list[str]:
    """Names of head templates with a captured argument exactly equal to value."""
    return sorted({name for name, _ in head_template_matches(record, value)})


def english_section(body: str) -> str:
    match = re.search(r"(?m)^==English==\s*$", body)
    if not match:
        return ""
    rest = body[match.end():]
    end = re.search(r"(?m)^==[^=].*?==\s*$", rest)
    return rest[:end.start()] if end else rest


ALT_HEADING = re.compile(
    r"(?m)^(={2,6})\s*(alternative forms|alternative spellings)\s*\1\s*$", re.IGNORECASE
)
ANY_HEADING = re.compile(r"(?m)^(={2,6})\s*[^=\n]+\s*\1\s*$")


def altsection_evidence(body: str) -> dict[str, str]:
    """Five-letter literals in Alternative-forms subsections (section-local).

    Maps each literal to its matched subsection heading text (``Alternative
    forms`` or ``Alternative spellings`` as written); on collision the
    lexicographically smallest heading wins so the mapping is deterministic.
    """
    section = english_section(body)
    if not section:
        return {}
    found: dict[str, set[str]] = defaultdict(set)
    for match in ALT_HEADING.finditer(section):
        level = len(match.group(1))
        heading = match.group(2).strip()
        start = match.end()
        end = len(section)
        for other in ANY_HEADING.finditer(section[match.end():]):
            if len(other.group(1)) <= level:
                end = match.end() + other.start()
                break
        for token in TOKEN.findall(section[start:end]):
            found[token].add(heading)
    return {token: sorted(headings)[0] for token, headings in found.items()}


def altsection_tokens(body: str) -> set[str]:
    """Five-letter literals inside Alternative-forms subsections (section-local)."""
    return set(altsection_evidence(body))


def sense_targets(sense: dict) -> list[str]:
    targets: list[str] = []
    for key in ("alt_of", "form_of"):
        value = sense.get(key)
        if not value:
            continue
        entries = [value] if isinstance(value, dict) else value
        if isinstance(entries, str):
            entries = [entries]
        for entry in entries or []:
            if isinstance(entry, dict) and entry.get("word"):
                targets.append(entry["word"])
            elif isinstance(entry, str) and entry:
                targets.append(entry)
    return targets


def load_revision_index(path: Path) -> dict[str, dict]:
    index = {}
    for line in path.open(encoding="utf-8"):
        line = line.strip()
        if line:
            row = json.loads(line)
            index[row["title"]] = row
    return index


def run(args: argparse.Namespace) -> dict:
    baseline_raw = Path(args.baseline).read_bytes()
    baseline = baseline_raw.decode("ascii").splitlines()
    actual_baseline_sha = sha256_bytes(baseline_raw)
    if actual_baseline_sha != BASELINE_SHA256:
        raise ValueError(
            f"baseline drift: {actual_baseline_sha} != frozen {BASELINE_SHA256}; "
            "refusing to overwrite (STOP condition)"
        )
    baseline_set = set(baseline)
    if len(baseline_set) != len(baseline) or any(WORD.fullmatch(w) is None or w != w.lower() for w in baseline):
        raise ValueError("frozen baseline is not sorted unique lowercase ASCII-5")

    chunk_paths = sorted(Path(args.wiktionary_json).glob("chunk-*.jsonl"))
    if len(chunk_paths) != 99:
        raise ValueError(f"expected 99 JSONL chunks, found {len(chunk_paths)}")
    records: list[tuple[str, int, dict]] = []
    for chunk in chunk_paths:
        with chunk.open(encoding="utf-8") as handle:
            for lineno, line in enumerate(handle):
                if line.strip():
                    records.append((chunk.name, lineno, json.loads(line)))

    target_paths = sorted(Path(args.target_json).glob("target-*.jsonl"))
    if not target_paths:
        raise ValueError(f"target coverage empty: {args.target_json}")
    target_records: list[tuple[str, int, dict]] = []
    for chunk in target_paths:
        with chunk.open(encoding="utf-8") as handle:
            for lineno, line in enumerate(handle):
                if line.strip():
                    target_records.append((chunk.name, lineno, json.loads(line)))
    target_pool = records + target_records
    target_titles = set()
    for pages_path in sorted(Path(args.target_json).glob("target-*.pages.json")):
        target_titles.update(json.loads(pages_path.read_text(encoding="utf-8")))

    # Aggregate coverage invariant (fail-closed, no word-specific exceptions):
    # every relationship target that is absent from the pinned 99-chunk JSONL
    # but needed by a candidate five-letter standalone/form record must have
    # been attempted by the bounded targeted-coverage extraction (present in
    # its title lists). A needed absent target with no coverage attempt means
    # the support classification above cannot see its records, so the run
    # refuses rather than treating the absence as non-evidence silently.
    main_english_titles = {
        record.get("word", "") for _, _, record in records
        if record.get("lang_code") == "en"
    }
    candidate_needed_targets: set[str] = set()
    for _, _, record in records:
        if eligibility(record) != "eligible":
            continue
        head = record.get("word", "") or ""
        has_five_letter_head = WORD.fullmatch(head) is not None
        has_five_letter_form = any(
            WORD.fullmatch(form.get("form", "") or "") is not None
            for form in record.get("forms", []) or []
        )
        if not (has_five_letter_head or has_five_letter_form):
            continue
        for sense in record.get("senses", []):
            if "misspelling" in (sense.get("tags") or []):
                continue
            candidate_needed_targets.update(sense_targets(sense))
    absent_needed = sorted(
        target for target in candidate_needed_targets
        if target not in main_english_titles
    )
    uncovered_needed = [
        target for target in absent_needed if target not in target_titles
    ]
    if uncovered_needed:
        sample = ", ".join(uncovered_needed[:5])
        raise ValueError(
            f"target coverage incomplete: {len(uncovered_needed)} absent "
            "relationship targets needed by candidate five-letter "
            "standalone/form records are missing from the targeted-coverage "
            f"title lists (e.g. {sample}); refusing to treat absence as "
            "non-evidence (STOP condition)"
        )

    # Relationship-level eligibility: exact-title target exclusion/support
    # over the pinned JSONL plus the bounded targeted-coverage extraction,
    # plus a record lookup by chunk locator for parent checks and pointer
    # postings (main-chunk records only; coverage records classify targets).
    target_excluded = build_target_exclusion(target_pool)
    target_supported = build_target_support(target_pool) - target_excluded
    referenced_targets: set[str] = set()
    for _, _, record in records:
        if record.get("lang_code") != "en":
            continue
        for sense in record.get("senses", []):
            if "misspelling" in (sense.get("tags") or []):
                continue
            referenced_targets.update(sense_targets(sense))
    unresolved_targets = sorted(referenced_targets - target_supported - target_excluded)
    rec_by_loc = {(chunk, lineno): record for chunk, lineno, record in records}
    pointer_index: dict[str, list[tuple[str, int, int, str]]] = defaultdict(list)
    for chunk_name, lineno, record in records:
        if record.get("lang_code") != "en":
            continue
        pointer_index[(record.get("word") or "").lower()].extend(
            (chunk_name, lineno, sense_index, target)
            for sense_index, sense in enumerate(record.get("senses", []))
            if "misspelling" not in (sense.get("tags") or [])
            for target in sense_targets(sense)
        )
    for postings in pointer_index.values():
        postings.sort()

    # Pass 1: reciprocal map (own-page word lower -> exact parent targets).
    reciprocal: dict[str, set[str]] = defaultdict(set)
    for _, _, record in records:
        if record.get("lang_code") != "en":
            continue
        key = (record.get("word") or "").lower()
        for sense in record.get("senses", []):
            if "misspelling" in (sense.get("tags") or []):
                continue
            for target in sense_targets(sense):
                reciprocal[key].add(target)

    database = sqlite3.connect(f"file:{args.database}?immutable=1", uri=True)
    body_cache: dict[str, str] = {}

    def body_for(title: str) -> str:
        if title not in body_cache:
            row = database.execute(
                "SELECT body FROM pages WHERE namespace_id=0 AND title=?", (title,)
            ).fetchone()
            body_cache[title] = row[0] if row else ""
        return body_cache[title]

    alt_cache: dict[str, dict[str, str]] = {}

    def alt_for(title: str) -> dict[str, str]:
        if title not in alt_cache:
            alt_cache[title] = altsection_evidence(body_for(title))
        return alt_cache[title]

    # Pass 2: standalone winners + explicit-form evidences (one SQLite SELECT pass).
    standalone: dict[str, dict] = {}
    evidences: dict[str, list[tuple]] = defaultdict(list)
    sem_excluded = 0
    dropped_standalone_records = 0
    for chunk_name, lineno, record in records:
        if eligibility(record) != "eligible":
            continue
        head = record.get("word", "")
        pos = record.get("pos", "unknown")
        if WORD.fullmatch(head or ""):
            norm = head.lower()
            sense_index = first_qualifying_sense(record, target_excluded, target_supported)
            if sense_index is None:
                dropped_standalone_records += 1
            else:
                candidate = {
                    "source_case": head, "pos": pos, "sense_index": sense_index,
                    "chunk": chunk_name, "lineno": lineno,
                    "locator": f"{chunk_name}:{lineno + 1}",
                }
                prev = standalone.get(norm)
                if prev is None or (head, pos, chunk_name, lineno) < (
                    prev["source_case"], prev["pos"], prev["chunk"], prev["lineno"]
                ):
                    standalone[norm] = candidate
        forms = []
        for form in record.get("forms", []):
            value = form.get("form", "") or ""
            tags = set(form.get("tags") or [])
            if not WORD.fullmatch(value):
                continue
            if tags & FORM_METADATA_TAGS:
                continue
            if tags & FORM_SEM_TAGS:
                sem_excluded += 1
                continue
            forms.append(value)
        if not forms:
            continue
        arg_tokens = explicit_template_tokens(record)
        alt_map = alt_for(head)
        for value in forms:
            norm = value.lower()
            if value in arg_tokens:
                names = head_templates_for_value(record, value)
                evidences[norm].append(
                    (0, "explicit_arg", head, value, pos, names[0] if names else "", chunk_name, lineno)
                )
            if value in alt_map:
                evidences[norm].append(
                    (1, "explicit_altsection", head, value, pos, alt_map[value], chunk_name, lineno)
                )
            if head in reciprocal.get(norm, ()):
                evidences[norm].append(
                    (2, "explicit_reciprocal", head, value, pos, "", chunk_name, lineno)
                )
    database.close()

    index = load_revision_index(Path(args.revision_index))
    extra: dict = {}
    if args.extra_revisions and Path(args.extra_revisions).exists():
        extra = json.loads(Path(args.extra_revisions).read_text(encoding="utf-8")).get("found", {})

    def revision_for(page: str) -> tuple[dict, str]:
        if page in index:
            row = index[page]
            return (
                {"page_id": row.get("pageId"), "revision_id": row.get("revisionId"),
                 "timestamp": row.get("timestamp")},
                "five_letter_index",
            )
        if page in extra:
            row = extra[page]
            return (
                {"page_id": row.get("pageId") or None, "revision_id": row.get("revisionId") or None,
                 "timestamp": row.get("timestamp") or None},
                "dump_parent",
            )
        return ({"page_id": None, "revision_id": None, "timestamp": None}, "unavailable")

    provenance_rows = []
    dropped_explicit_norms = 0
    explicit_only_sponsored = 0
    for norm in sorted(set(standalone) | set(evidences)):
        if norm in standalone:
            winner = standalone[norm]
            rev, status = revision_for(winner["source_case"])
            provenance_rows.append({
                "normalized": norm,
                "source_case": winner["source_case"],
                "page": winner["source_case"],
                "parent": None,
                "rule": "standalone",
                "pos": winner["pos"],
                "sense_index": winner["sense_index"],
                "head_template": None,
                "head_arg": None,
                "alt_section": None,
                "pointer_locator": None,
                "pointer_sense": None,
                "pointer_target": None,
                "locator": winner["locator"],
                "page_id": rev["page_id"],
                "revision_id": rev["revision_id"],
                "timestamp": rev["timestamp"],
                "revision_status": status,
            })
            continue
        sponsored = [
            item for item in sorted(set(evidences[norm]))
            if first_qualifying_sense(rec_by_loc[(item[6], item[7])], target_excluded, target_supported) is not None
        ]
        if not sponsored:
            dropped_explicit_norms += 1
            continue
        explicit_only_sponsored += 1
        _, rule, parent, source_case, pos, detail, chunk_name, lineno = sponsored[0]
        parent_record = rec_by_loc[(chunk_name, lineno)]
        rev, status = revision_for(parent)
        row = {
            "normalized": norm,
            "source_case": source_case,
            "page": parent,
            "parent": parent,
            "rule": rule,
            "pos": pos,
            "sense_index": None,
            "head_template": None,
            "head_arg": None,
            "alt_section": None,
            "pointer_locator": None,
            "pointer_sense": None,
            "pointer_target": None,
            "locator": f"{chunk_name}:{lineno + 1}",
            "page_id": rev["page_id"],
            "revision_id": rev["revision_id"],
            "timestamp": rev["timestamp"],
            "revision_status": status,
        }
        if rule == "explicit_arg":
            pairs = head_template_matches(parent_record, source_case)
            name, key = pairs[0] if pairs else (detail or None, None)
            row["head_template"] = name
            row["head_arg"] = key
        elif rule == "explicit_altsection":
            row["alt_section"] = detail
            row["sense_index"] = first_qualifying_sense(parent_record, target_excluded, target_supported)
        elif rule == "explicit_reciprocal":
            postings = [p for p in pointer_index.get(norm, []) if p[3] == parent]
            child_chunk, child_lineno, child_sense, _ = postings[0]
            row["pointer_locator"] = f"{child_chunk}:{child_lineno + 1}"
            row["pointer_sense"] = child_sense
            row["pointer_target"] = parent
        provenance_rows.append(row)

    wiktionary = {row["normalized"] for row in provenance_rows}
    final = sorted(baseline_set | wiktionary)
    if set(final) != baseline_set | wiktionary or len(final) != len(set(final)):
        raise ValueError("final set failed uniqueness check")
    if not baseline_set <= set(final):
        raise ValueError("baseline is not a subset of the final set")

    pack_path = Path(args.pack)
    pack = json.loads(pack_path.read_text(encoding="utf-8"))
    ordered_answers = list(pack["answers"])
    answers_projection = "".join(f"{w}\n" for w in ordered_answers).encode("ascii")
    if sha256_bytes(answers_projection) != ANSWERS_SHA256:
        raise ValueError("ordered answers drifted; refusing to overwrite (STOP condition)")
    for key in ("formatVersion", "id", "scheduleVersion", "epochDay", "manualReview"):
        if key not in pack:
            raise ValueError(f"pack lost protected field {key}")
    pack["acceptedGuesses"] = final
    pack["provenance"] = {
        "acceptedGuessSource": (
            "English Wiktionary release enwiktionary-20260901 union frozen GridRace baseline"
        ),
        "acceptedGuessBaseline": (
            "Frozen baseline 8508 entries, sorted-LF SHA-256 "
            "f045112edcf1fb2889b58a947f0e4323323247c0a8190ed885fb734bfcd11853; "
            "historical source macOS /usr/share/dict/web2 retained as a compatibility "
            "subset (see SOURCES.md); baseline-only spellings carry no Wiktionary provenance."
        ),
        "wiktionaryRelease": "enwiktionary-20260901",
        "wiktionaryDumpUri": (
            "https://dumps.wikimedia.org/enwiktionary/20260901/"
            "enwiktionary-20260901-pages-articles-multistream.xml.bz2"
        ),
        "wiktionaryDumpSha256": DUMP_SHA256,
        "wiktextractCommit": WIKTEXTRACT_COMMIT,
        "wikitextprocessorCommit": WIKITEXTPROCESSOR_COMMIT,
        "fiveLetterRevisionIndexSha256": FIVE_LETTER_INDEX_SHA256,
        "acceptedGuessTransform": (
            "scripts/build_accepted_guesses.py: sorted unique lowercase ASCII five-letter "
            "union of the frozen baseline and tightened Wiktionary evidence. Standalone: "
            "eligible English entries with five-letter titles carrying at least one "
            "independent sense (a form_of/alt_of sense counts only when a target "
            "affirmatively carries an ordinary lexical sense on an eligible "
            "record; unclassified, excluded-only, missing, ineligible-record, "
            "or targetless relationship senses support nothing; targets "
            "classified from the pinned JSONL plus the bounded "
            "targeted-coverage extraction before case normalization, with an "
            "aggregate invariant that every absent target needed by candidate "
            "five-letter standalone/form records is covered). Forms on "
            "independently-sensed eligible parents "
            "only via exact head-template-argument match, reciprocal own-page "
            "alt_of/form_of pointer to the parent, or literal occurrence in the parent's "
            "Alternative-forms subsection (section-local). Form-level "
            "misspelling/abbreviation/acronym/initialism and metadata pseudo-forms "
            "excluded; expansion-only template-computed forms excluded. Per-word evidence "
            "with deterministic record locators in "
            "daily-classic-en-US-v1-PROVENANCE.jsonl."
        ),
        "answerCuration": pack["provenance"].get("answerCuration", ""),
        "commercialListUse": pack["provenance"].get("commercialListUse", ""),
        "reviewedOn": pack["provenance"].get("reviewedOn", ""),
        "expandedOn": "2026-09-15",
    }
    pack_bytes = (json.dumps(pack, indent=2, ensure_ascii=True) + "\n").encode("utf-8")
    pack_path.write_bytes(pack_bytes)

    prov_path = Path(args.provenance)
    prov_bytes = "".join(
        json.dumps(row, sort_keys=True, separators=(",", ":")) + "\n" for row in provenance_rows
    ).encode("utf-8")
    prov_path.write_bytes(prov_bytes)

    manifest = {
        "formatVersion": 1,
        "provenanceFile": prov_path.name,
        "provenanceCount": len(provenance_rows),
        "provenanceSha256": sha256_bytes(prov_bytes),
        "packFile": pack_path.name,
        "packSha256": sha256_bytes(pack_bytes),
        "acceptedGuessCount": len(final),
        "baselineCount": len(baseline_set),
        "baselineSha256": BASELINE_SHA256,
        "wiktionaryCount": len(wiktionary),
        "wiktionaryTransform": "tightened explicit forms + relationship eligibility (standalone|explicit_arg|explicit_altsection|explicit_reciprocal)",
        "inputs": {
            "excludedRelationshipTargets": len(target_excluded),
            "supportedRelationshipTargets": len(target_supported),
            "referencedRelationshipTargets": len(referenced_targets),
            "unresolvedRelationshipTargets": len(unresolved_targets),
            "candidateNeededRelationshipTargets": len(candidate_needed_targets),
            "absentNeededRelationshipTargets": len(absent_needed),
            "uncoveredNeededRelationshipTargets": len(uncovered_needed),
            "targetJsonRecords": len(target_records),
            "targetJsonChunks": len(target_paths),
            "targetJsonTitles": len(target_titles),
            "wiktionaryJsonRecords": len(records),
            "wiktionaryJsonChunks": len(chunk_paths),
            "dumpSha256": DUMP_SHA256,
            "wiktextractCommit": WIKTEXTRACT_COMMIT,
            "wikitextprocessorCommit": WIKITEXTPROCESSOR_COMMIT,
            "fiveLetterRevisionIndexSha256": FIVE_LETTER_INDEX_SHA256,
            "parentRevisionsSha256": sha256_bytes(Path(args.extra_revisions).read_bytes())
            if args.extra_revisions and Path(args.extra_revisions).exists()
            else None,
        },
    }
    manifest_path = Path(args.provenance_manifest)
    manifest_path.write_bytes((json.dumps(manifest, indent=2, sort_keys=True) + "\n").encode("utf-8"))

    report: dict = {
        "records": len(records),
        "chunks": len(chunk_paths),
        "standalone_unique": len(standalone),
        "explicit_norms": len(evidences),
        "wiktionary_unique": len(wiktionary),
        "baseline": len(baseline_set),
        "final": len(final),
        "additions_over_baseline": len(set(final) - baseline_set),
        "sem_excluded_form_occurrences": sem_excluded,
        "relationship_eligibility": {
            "excluded_targets": len(target_excluded),
            "supported_targets": len(target_supported),
            "referenced_targets": len(referenced_targets),
            "unresolved_targets": len(unresolved_targets),
            "unresolved_targets_sorted": unresolved_targets,
            "candidate_needed_targets": len(candidate_needed_targets),
            "absent_needed_targets": len(absent_needed),
            "uncovered_needed_targets": len(uncovered_needed),
            "standalone_records_without_independent_sense": dropped_standalone_records,
            "explicit_norms_without_sponsoring_parent": dropped_explicit_norms,
            "norms_explicit_only_sponsored": explicit_only_sponsored,
        },
        "rules": {r: sum(1 for row in provenance_rows if row["rule"] == r)
                  for r in ("standalone", "explicit_arg", "explicit_altsection", "explicit_reciprocal")},
        "revision_status": {s: sum(1 for row in provenance_rows if row["revision_status"] == s)
                            for s in ("five_letter_index", "dump_parent", "unavailable")},
        "final_sha256": sha256_bytes(("".join(f"{w}\n" for w in final)).encode("ascii")),
        "provenance_sha256": manifest["provenanceSha256"],
        "pack_sha256": manifest["packSha256"],
    }
    prior_path = Path(args.prior_explicit)
    if prior_path.exists():
        prior_add = set(prior_path.read_text(encoding="ascii").split())
        explicit_norms = {r["normalized"] for r in provenance_rows if r["rule"] != "standalone"}
        report["prior_explicit_context"] = {
            "prior_count": len(prior_add),
            "kept": len(explicit_norms & prior_add),
            "dropped": sorted(prior_add - explicit_norms),
        }
    return report


def pinned_defaults() -> dict[str, str]:
    """Pinned intermediate defaults shared with check_word_pack's source gate.

    Returns the external (non-committed) input paths so the gate resolves
    them from this module instead of mirroring string fragments. All paths
    are overridable via the matching --flags below.
    """
    return {
        "wiktionary_json": str(ADDENDUM / "validation/run-fresh-db-fresh-env-2"),
        "database": str(CACHE / "enwiktionary-20260901-fresh.sqlite"),
        "revision_index": str(
            ADDENDUM / "source-records/wiktionary-five-letter-revision-provenance.jsonl"
        ),
        "target_json": str(ADDENDUM / "validation/run-target-coverage"),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    defaults = pinned_defaults()
    parser.add_argument("--baseline", default=str(PACKS / "baseline-accepted-frozen.txt"))
    parser.add_argument("--wiktionary-json", default=defaults["wiktionary_json"])
    parser.add_argument("--database", default=defaults["database"])
    parser.add_argument("--revision-index", default=defaults["revision_index"])
    parser.add_argument(
        "--extra-revisions",
        default=str(PACKS / "daily-classic-en-US-v1-parent-revisions.json"),
    )
    parser.add_argument("--pack", default=str(PACKS / "daily-classic-en-US-v1.json"))
    parser.add_argument("--provenance", default=str(PACKS / "daily-classic-en-US-v1-PROVENANCE.jsonl"))
    parser.add_argument("--provenance-manifest", default=str(PACKS / "daily-classic-en-US-v1-PROVENANCE.manifest.json"))
    parser.add_argument("--prior-explicit", default=str(REVIEW / "validation/corrected-run-2/wiktionary-explicit-form-additions.txt"))
    parser.add_argument("--target-json", default=defaults["target_json"])
    args = parser.parse_args()
    try:
        report = run(args)
    except (OSError, ValueError) as error:
        print(f"build failed: {error}", file=sys.stderr)
        return 1
    print(json.dumps(report, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
