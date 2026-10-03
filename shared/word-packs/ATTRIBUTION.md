# GridRace Daily Classic en-US v1 — corpus notice

This file is the shipped corpus notice summarized by the in-app
Settings → Word list attribution screen. It records sources and terms
only. It is not a legal-clearance determination, and it does not
relicense any GridRace code.

## Wiktionary snapshot

Accepted guesses include spellings derived from the English Wiktionary
release `enwiktionary-20260901`:

- Dump file:
  `enwiktionary-20260901-pages-articles-multistream.xml.bz2`
- Size: 1,937,351,957 bytes
- SHA-256:
  `0b7f554b1884e52e1c06de74cecab5e370c6b9f765711cedb0759f6d14c5e719`
- Index: <https://dumps.wikimedia.org/enwiktionary/20260901/>

Extraction tool pins: Wiktextract `ccec6f120efedd84f57fe0f1631e89408e9cb62a`
(v1.99.7) and Wikitextprocessor `4deed5191c9e4cb61ee1a4c822e3f6686ae8541b`
(v0.4.96). Extraction JSONL: 99 chunks, 125,730 records.

## Transformation summary

The accepted-guess corpus (25,545 entries) is the sorted unique
lowercase ASCII five-letter union of:

1. The frozen GridRace baseline `baseline-accepted-frozen.txt`
   (8,508 entries; every baseline spelling preserved verbatim).
2. Eligible English Wiktionary spellings: standalone eligible entries,
   plus explicit forms on eligible parent records admitted only via an
   exact head-template-argument match, a reciprocal own-page
   `alt_of`/`form_of` pointer to the parent, or a literal occurrence in
   the parent's `Alternative forms` subsection. A relationship
   (`form_of`/`alt_of`) sense counts only when its target affirmatively
   carries an ordinary lexical sense on an eligible record (targets
   classified source-wide over the pinned extraction plus a bounded
   targeted-coverage extraction); unclassified, excluded-only, missing,
   ineligible-record, or targetless relationship senses support nothing
   (fail-closed). Form-level misspelling/abbreviation/acronym/initialism
   tags and metadata pseudo-forms are excluded; expansion-only
   template-computed forms stay excluded.

Per-word evidence for every Wiktionary-supplied spelling is committed in
`daily-classic-en-US-v1-PROVENANCE.jsonl` (24,089 rows: standalone
22,960, explicit head-template-argument 87, explicit Alternative-forms
1,015, explicit reciprocal 27; baseline-only spellings map to the frozen
baseline artifact, not to Wiktionary).
Full source/transform detail lives in
`daily-classic-en-US-v1-SOURCES.md`.

## Applicable Wiktionary data terms

The Wiktionary-derived portion of the accepted-guess corpus is used
under the data terms stated for Wiktionary entry texts: dual-licensed to
the public under the Creative Commons Attribution-ShareAlike 4.0
International License (CC BY-SA 4.0) and the GNU Free Documentation
License (GFDL, Version 1.1 or later).

- License deed: <https://creativecommons.org/licenses/by-sa/4.0/>
- Wiktionary copyright terms:
  <https://en.wiktionary.org/wiki/Wiktionary:Copyrights>

CC BY-SA reuse entails licensing adapted material under the same, a
similar, or a compatible license, and attributing the work in the manner
specified by the author or licensor (without implying endorsement).
GFDL reuse entails licensing under GFDL, acknowledging article
authorship, and providing access to a transparent copy (fulfilled for
entries by a conspicuous link back to the article on wiktionary.org).
These terms apply to the Wiktionary-derived portion; they do not
relicense unrelated GridRace code, and the ordered Daily Classic
answers below are not Wiktionary-derived.

## Extraction-software license (separate from data terms)

Wiktextract — the extraction tool used to read the Wiktionary dump — is
separately licensed software: MIT License, Copyright (c) 2018-2020 Tatu
Ylonen. That MIT license covers the tool, not the Wiktionary dictionary
data, which remains under the CC BY-SA 4.0 / GFDL data terms above.

## Baseline-provenance note

Baseline-only spellings trace historically to macOS
`/usr/share/dict/web2` (Webster's Second International lineage; the
adjacent system README states "The 1934 copyright has lapsed, according
to the supplier"). web2 is provenance history only: it is not re-read by
the current maintenance transform. Provenance beyond that supplier
statement is unresolved and sits in the release gates below.

## Answers

The ordered Daily Classic answer schedule (725 entries) is original
GridRace manual curation of familiar ordinary English words. It does not
use or adapt any commercial word game's answer or accepted-guess list.

## Non-sources

No 12dicts, Open English WordNet (OEWN), commercial-game list, generated
morphology, or LLM judgment feeds this pack.

## Release gates (not clearance)

The following remain owner release gates. This notice does not clear
them:

1. Attribution review — confirm this notice and the in-app attribution
   screen satisfy the CC BY-SA 4.0 / GFDL obligations for the intended
   distribution.
2. Baseline provenance — resolve provenance beyond the web2 system
   README supplier statement.
3. App Store / distribution review — complete store and distribution
   review before any public release.

## String and link sources

- Snapshot identifiers, dump SHA-256, byte size, tool pins, baseline
  count/hash, transform rules, answers statement, non-sources, and gate
  list: preserved repository record
  `shared/word-packs/daily-classic-en-US-v1-SOURCES.md` (web2 README
  wording confirmed against the local `/usr/share/dict/README` text).
- Wiktextract MIT software license and "Certain files under tests/ are
  under Wiktionary license (CC-BY-SA or GFDL at your choice)" pointer to
  `https://en.wiktionary.org/wiki/Wiktionary:Copyrights`: preserved
  pinned Wiktextract bundle LICENSE and README (commit `ccec6f1`).
- CC BY-SA **4.0 International** version string, GFDL 1.1-or-later
  version, license deed link, and reuse-obligation wording: single
  targeted official check of
  `https://en.wiktionary.org/wiki/Wiktionary:Copyrights` (the exact page
  the preserved Wiktextract LICENSE points to).
