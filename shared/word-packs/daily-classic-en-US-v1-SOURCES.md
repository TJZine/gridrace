# Daily Classic en-US v1 sources

## Accepted guesses (current)

The accepted-guess corpus is the sorted unique lowercase ASCII five-letter
union of two inputs:

1. Frozen GridRace baseline: `baseline-accepted-frozen.txt` (8,508 entries,
   sorted-LF SHA-256
   `f045112edcf1fb2889b58a947f0e4323323247c0a8190ed885fb734bfcd11853`).
   Every baseline spelling is preserved verbatim.
2. Eligible English Wiktionary spellings (release `enwiktionary-20260901`):
   standalone eligible entries with five-letter titles, plus explicit forms on
   eligible parent records admitted only via an exact head-template-argument
   match, a reciprocal own-page `alt_of`/`form_of` pointer to the parent, or a
   literal occurrence in the parent's `Alternative forms` subsection
   (section-local, never whole-section incidental text). A relationship
   sense counts only when its target affirmatively carries an ordinary
   lexical sense on an eligible record
   (`eligibility(record) == "eligible"`); targets are classified
   source-wide over the pinned extraction plus the bounded
   targeted-coverage extraction below, and unclassified, excluded-only,
   missing, ineligible-record, or targetless relationship senses support
   nothing (fail-closed). Every relationship target absent from the
   99-chunk JSONL but needed by a candidate five-letter standalone/form
   record must be present in the targeted-coverage title lists, or the
   build refuses. Form-level
   misspelling/abbreviation/acronym/initialism tags and metadata pseudo-forms
   are excluded; expansion-only template-computed forms stay excluded.

Pinned inputs:

- Wiktionary dump `enwiktionary-20260901-pages-articles-multistream.xml.bz2`,
  1,937,351,957 bytes, SHA-256
  `0b7f554b1884e52e1c06de74cecab5e370c6b9f765711cedb0759f6d14c5e719`
  (`https://dumps.wikimedia.org/enwiktionary/20260901/`).
- Wiktextract `ccec6f120efedd84f57fe0f1631e89408e9cb62a` (v1.99.7) and
  Wikitextprocessor `4deed5191c9e4cb61ee1a4c822e3f6686ae8541b` (v0.4.96).
- Extraction JSONL: 99 chunks, 125,730 records
  (`validation/run-fresh-db-fresh-env-2` in the
  `gridrace-corpus-validation-addendum-2026-09-08` bundle).
- Five-letter revision index
  `wiktionary-five-letter-revision-provenance.jsonl`, SHA-256
  `b140a40bf5d0e327d99d1ef032719b83319387a67b35defd7736e2f6264ab70d`.
- Relationship-target coverage: bounded extraction over every target title
  absent from the 99-chunk JSONL — 7 chunks, 12,880 records covering 7,471
  titles (`validation/run-target-coverage` in the
  `gridrace-corpus-validation-addendum-2026-09-08` bundle; consumed via
  `--target-json`).
- Parent revisions for contributing non-five-letter pages come from one dump
  streaming pass over the pinned dump for those titles only (539 titles; see
  maintenance below). A revision that is truly unavailable is recorded as
  null in `daily-classic-en-US-v1-PROVENANCE.jsonl` -- never invented.

Per-word evidence (one row per Wiktionary-supplied spelling: normalized
spelling, source case, evidence page/title and revision, record POS/sense
index or head-template name, admission rule) is committed in
`daily-classic-en-US-v1-PROVENANCE.jsonl` with its hash manifest in
`daily-classic-en-US-v1-PROVENANCE.manifest.json`. Baseline-only spellings
are intentionally absent from provenance; they map to the frozen baseline
artifact above. No 12dicts, OEWN, commercial-game list, generated
morphology, or LLM judgment feeds this pack.

## Historical baseline note (not an active source)

The frozen baseline was originally derived from macOS `/usr/share/dict/web2`
(pinned at SHA-256
`be41ad97963bf8dabedd5871d5d691596175269d540956b0f9965a885c2bbab9`;
the adjacent system README identifies Webster's Second International and says
its 1934 copyright has lapsed according to the supplier) plus originally
curated answers minus the answer denylist. web2 is retained here only as
provenance history for baseline-only spellings. It is NOT re-read by the
current maintenance transform.

## Answers (unchanged)

The ordered answer schedule is an original GridRace manual selection of
familiar ordinary English words, with a few familiar additions. It does not
use or adapt any commercial word game's answer or accepted-guess list.
Answers were reviewed to exclude proper nouns, abbreviations, offensive
terms, and unsuitable entries. Published v1 answer positions are
append-only and must never be reordered. Puzzle #1 is fixed to UTC day
20696, 2026-08-31 at 00:00 UTC. Ordered-answer projection (725 entries)
SHA-256 `31330cbe412018d0ea94991c321d032def17def40e725fcadc90363b11cebda9`.

## Maintenance

Deterministic rebuild from pinned intermediates (run twice; both output and
evidence hashes must be identical):

```sh
python3 scripts/build_accepted_guesses.py
python3 scripts/build_accepted_guesses.py  # identical output expected
```

Verify the checked-in evidence chain on any machine (no Wiktionary reads):

```sh
python3 scripts/check_word_pack.py --checked-in-only
```

Verify source regeneration where the pinned intermediates are present (this
machine). The source gate is fail-closed: builder, execution, and comparison
failures are errors, and absent intermediates report UNAVAILABLE with a
nonzero exit (never a pass). `--probe-intermediates` only reports which
intermediates exist:

```sh
python3 scripts/check_word_pack.py
python3 scripts/check_word_pack.py --probe-intermediates  # informational only
```

Refresh sequence (the provenance manifest is builder-owned attestation and
cannot be fabricated by the checker): after any intentional transform or
metadata change, run the builder first (rewrites pack, provenance, and the
provenance manifest), then refresh the checker-owned pack manifests, then
re-run both gates:

```sh
python3 scripts/build_accepted_guesses.py
python3 scripts/check_word_pack.py --write-manifest
python3 scripts/check_word_pack.py --checked-in-only
python3 scripts/check_word_pack.py
```

The non-five-letter parent-revision sidecar is committed as
`daily-classic-en-US-v1-parent-revisions.json` (539 titles in the committed
sidecar, consumed via `--extra-revisions`). Regenerate it with one streaming
pass over the pinned dump (ordinary builds must NOT run this):

```sh
python3 scripts/parent_revision_pass.py \
  --dump <cache>/enwiktionary-20260901-pages-articles-multistream.xml.bz2 \
  --provenance shared/word-packs/daily-classic-en-US-v1-PROVENANCE.jsonl \
  --output shared/word-packs/daily-classic-en-US-v1-parent-revisions.json
```

(`<cache>` is the durable large-input cache holding the pinned dump bytes;
all other `--build` inputs are likewise overridable flags defaulting to the
original research paths.)

The historical web2 generator was retired after its answer denylist was moved
into the current checker owner, `scripts/check_word_pack.py`. Git history
preserves the pre-Wiktionary implementation and provenance; it is not a
maintenance or CI entrypoint. Ordinary app builds and CI must not download or
extract Wiktionary.

## Release gates (not clearance)

Wiktionary data-terms attribution for the app surface, unresolved baseline
provenance beyond the web2 system README, and App Store/distribution review
remain owner release gates. This file records sources and transform only.
