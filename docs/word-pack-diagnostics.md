# Word-pack extraction diagnostics: classifier fix + impact assessment

Status: complete, documented-only. No production transform change required.
No re-extraction performed; no rerun warranted (re-verified below).

## 1. Method

- Input: preserved run-2 consoles
  `/Users/tristan/Software/gridrace-corpus-validation-addendum-2026-09-08/validation/run-fresh-db-fresh-env-2`
  (`chunk-*.console` with the `analyze_validation.py` sibling gate: a console
  counts only when `chunk-*.jsonl` or `chunk-*.failed` exists).
- Tool: new `scripts/check_extraction_diagnostics.py` (`--consoles <dir>`).
  It imports nothing but the standard library and never touches the dump,
  SQLite, JSONL, or cache at import or at runtime.
- Scope: regroup the frozen 38 potential-membership + 32 unresolved events
  with the corrected classifier; inspect only relevant source structure
  (fresh-SQLite `SELECT body` for cited titles only, preserved chunk JSONL
  emission for cited titles only, `.errors`/`.pages.json` for the 3 isolated
  failures, `corrected-run-2` outputs for membership cross-checks).
- Invariants held: failed parsing is never treated as invalid-vocabulary
  evidence; every accepted record still needs an affirmative evidence path.

## 2. Corrected rule (overlap-silent ordering fix)

Legacy `analyze_validation.py::classify_error` checked the non-membership
substring list first, so any line matching both lists was silently filed as
`non_membership_field` (harmless) purely by check order.

The corrected `classify()` computes both flag sets independently and maps a
double match to a non-silent `ambiguous_overlap` bucket. Deterministic:
boolean combination only, no set-order dependence; all aggregates emitted
in sorted order (two runs from the same inputs are byte-identical).

The only 2 overlaps among 9,022 ERROR lines (both previously silent):

1. `inflection/English/noun: ERROR: LUA error in #invoke('translations',
   'show', 'interwiki=tpos') parent ('Template:t+', ...) at ['inflection',
   'Template:t+', '#invoke', '#invoke']`
   — matches `translation` (failing module) and `inflection` (page title,
   not a field). Legacy: `non_membership_field`. Corrected: `ambiguous_overlap`.
2. `point of inflection/English/noun: ERROR: LUA error in
   #invoke('translations', 'show', 'interwiki=tpos') parent
   ('Template:t+', ...) at ['point of inflection', ...]`
   — same double match (`translation` + title word `inflection`).
   Legacy: `non_membership_field`. Corrected: `ambiguous_overlap`.

## 3. Regrouped counts

| Bucket (corrected) | Events | Titles | Legacy |
|---|---|---|---|
| `ambiguous_overlap` (new, non-silent) | 2 | 2 | 0 (both sat inside legacy non-membership) |
| `non_membership_field` | 8,950 | 4,748 | 8,952 / 4,750 |
| `potential_membership_field` | 38 | 17 | 38 / 17 (unchanged) |
| `unresolved_context` | 32 | 28 | 32 / 28 (unchanged) |
| Total ERROR lines | 9,022 | — | 9,022 (conserved) |

Title arithmetic checks: 4,748 + 2 = 4,750 legacy non-membership titles.

## 4. Grouped signatures and per-group impact verdicts

Question answered per group: can this signature add or remove a 5-letter
word under the tightened explicit-forms rule (standalone eligible
five-letter title, or five-letter form with an explicit head-template /
alt-section / reciprocal path)? Verdict in every group: **no**.

### 4a. Potential-membership groups (38 events, 17 titles)

| # | Signature | Ev / Titles | Can it add/remove a 5-letter word? |
|---|---|---|---|
| P1 | `alternative forms → Template:alter` | 14 / 10 | No — §4a-P1 |
| P2 | `en-headword → Template:en-noun` | 8 / 4 | No — §4a-P2 |
| P3 | `en-headword → Template:en-proper noun` | 4 / 2 | No — §4a-P3 |
| P4 | `en-headword → Template:en-head` | 4 / 2 | No — §4a-P4 |
| P5 | `en-headword → Template:en-intj` | 2 / 1 | No — §4a-P5 |
| P6 | `form of/templates → Template:alternative form of` | 4 / 3 | No — §4a-P6 |
| P7 | `form of/templates → Template:alternative spelling of` | 1 / 1 | No — §4a-P7 |
| P8 | Template-nesting: inflection-templates, be-conjugation | 1 / 1 | No — §4a-P8 |

§4a-P1 (`alter`, titles `-a-`, `-ation`, `-ness`, `Arvanitika`,
`Gǃkúnǁʼhòmdímà`, `Tsuu T'ina`, `Tsúut'ínà`, `omertà`, `pietà`, `voilà`).
Examples: (a) `pietà` names `pieta` via `{{alter|en|pieta}}`, but `pieta`
is already an eligible standalone entry (noun record emitted,
`wiktionary-standalone-corrected.txt` ✓), so nothing is added or lost.
(b) `voilà` names `voila` (standalone ✓) plus `wallah`/`whalah`
(6 letters each — shape-excluded). (c) `-ness`/`-ation` are suffix-POS
parents (excluded) whose alters are Braille symbols (non-letters).
(d) `Arvanitika` is a proper-noun parent (excluded). No 5-letter impact.

§4a-P2 (`en-noun` headword, titles `Tsúut'ínà`, `ménage à moi`, `omertà`,
`pietà`). Examples: (a) `pietà` noun record emitted (chunk-053) with
`{{en-noun}}` + `===Alternative forms=== * {{alter|en|pieta}}` in the raw
English section — language, POS, and relationship survive in source, and
`pieta` stands alone as eligible. (b) `ménage à moi` is multiword
(shape-excluded); its head args are display chunks, not five-letter args.
(c) `Tsúut'ínà`/`omertà` titles are non-ASCII (shape-excluded). No impact.

§4a-P3 (`en-proper noun` headword, titles `Gǃkúnǁʼhòmdímà`, `Tsúut'ínà`).
Both parents are proper-noun POS (policy-excluded) with non-ASCII titles
(shape-excluded); records emitted but correctly excluded. No impact.

§4a-P4 (`en-head` on phrases, 2 titles: `first is the worst, second is the
best, third is the one with the hairy chest`; `one for the money, two for
the show, three to make ready, and four to go`). Phrase POS is excluded
and both titles are multiword; records emitted with multiword alternative
forms only. No 5-letter impact.

§4a-P5 (`en-intj` on `voilà`, 2 events). The `voilà` title is non-ASCII;
its English section shows `{{en-intj}}` plus `===Alternative forms===`
listing `voila` (eligible standalone, emitted ✓), `wallah`, `whalah`
(6 letters). The error did not block the surviving `voila` record. No impact.

§4a-P6 (`alternative form of`, titles `Tsúut'ínà`, `pieta`, `wallah`).
Positive control: `pieta`'s noun record (chunk-053) carries an
`error-lua-exec` sense tag from this exact template failure yet was still
emitted and stands as eligible standalone — the error did not falsely
reject it, and its English section retains
`# {{alternative form of|en|pietà}}` under `{{en-noun}}`. `wallah` is
6 letters; `Tsúut'ínà` is non-ASCII. No impact.

§4a-P7 (`alternative spelling of`, title `voila`, 1 event). `voila`'s
interjection record (chunk-066) was emitted with `{{en-intj}}` and
`# {{alternative spelling of|en|voilà}}` in source, and `voila` is in
standalone-corrected. Error tagged, membership intact. No impact.

§4a-P8 (be conjugation nesting, 1 event). `be` is 2 letters; its verb
record (24 senses, chunk-026) was emitted. Full inflection tables were
never ingested by the explicit rule, so a nesting failure inside the
conjugation section is outside the membership path by construction. No impact.

### 4b. Ambiguous-overlap group (2 events, 2 titles)

| # | Signature | Ev / Titles | Can it add/remove a 5-letter word? |
|---|---|---|---|
| A1 | `translations → Template:t+` (title-word collision) | 2 / 2 | No — §4b-A1 |

§4b-A1 (titles `inflection`, `point of inflection`). Both errors are in
the translations module (`Template:t+`, Korean equivalents) — a
non-membership field; the membership-substring hit comes only from the
page title. Examples: (a) `inflection` is a 10-letter eligible noun whose
record (7 senses, chunk-043) was emitted — shape-excluded, error
irrelevant to membership. (b) `point of inflection` is a multiword noun
(record emitted, chunk-053) — shape-excluded. Factually harmless, now
non-silently bucketed: the fix changes accounting visibility, not the
verdict. No 5-letter impact.

### 4c. Unresolved groups (32 events, 28 titles)

| # | Signature | Ev / Titles | Can it add/remove a 5-letter word? |
|---|---|---|---|
| U1 | `script utilities → Template:lang` (inside quote/etymology templates) | 16 / 15 | No — §4c-U1 |
| U2 | `zh/link → Template:zh-l` (etymology romanization links) | 7 / 6 | No — §4c-U2 |
| U3 | `zh/templates → Template:zh-m` (etymology mentions) | 3 / 3 | No — §4c-U3 |
| U4 | `place → Template:place` (display template) | 1 / 1 | No — §4c-U4 |
| U5 | `ja-link → Template:ja-r` (reading aids) | 2 / 2 | No — §4c-U5 |
| U6 | Unimplemented unsupported title (pseudo-page) | 2 / 1 | No — §4c-U6 |
| U7 | `debug/error → Template:error` (Albanian declension template) | 1 / 1 | No — §4c-U7 |

§4c-U1 (`lang_t`, 15 titles: `Baofeng`, `Ciaotou`, `Fongshan`, `Gaoyou`,
`Kunming`, `Lu`, `Luchu`, `Matou`, `Matsu`, `O`, `Pishan`, `Qidu`,
`Yuehu`, `artery`, `futhorc`). The five-letter members (`Luchu`,
`Matou`, `Matsu`) are all proper-noun parents (policy-excluded) whose
records were still emitted (`Luchu` ×4, `Matou` ×1, `Matsu` ×2 in
chunks 012–013); the independent lowercase nouns `matsu` (Japanese pine,
chunk-047) and `chang` stand on their own eligible records. Examples:
(a) `artery` is a 6-letter eligible noun (2 senses emitted, chunk-025) —
shape-excluded; the failure sits in a `quote-journal` trans-journal
field. (b) `futhorc` is a 7-letter noun (emitted, chunk-038) —
shape-excluded; the failure is an undetermined-language rune span in
etymology. (c) `Matsu`'s proper-noun records emitted alongside a clean
`alt-of` record; the failure is quotation text. No impact.

§4c-U2 (`zh-l`, titles `Chang`, `Chong`, `Jinzhu`, `Shamo`, `Suiyuan`,
`Xi`). The five-letter members (`Chang`, `Chong`, `Shamo`) are proper-noun
parents (excluded) with records emitted (`Chang` ×7, chunk-003); the
failures are Wade-Giles/Pinyin link templates in etymology. Lowercase
`chang` (harp, noun, chunk-030) is an independent eligible standalone.
No impact.

§4c-U3 (`zh-m`, titles `Diong`, `Teoh`, `Tiong`). All proper-noun parents
(excluded); records emitted (chunks 005/020/021). No impact.

§4c-U4 (`place`, title `Matsu`, 1 event). Display-template failure
carrying a Britannica `<ref>`; both `Matsu` records (one with clean
senses) emitted. No impact.

§4c-U5 (`ja-r`, titles `Nintendo`, `tortoise shell bracket`). `Nintendo`
is proper-noun (excluded; noun record with plural emitted regardless);
`tortoise shell bracket` is multiword (shape-excluded; record emitted,
chunk-064). Failures are Japanese reading aids in etymology. No impact.

§4c-U6 (unsupported-title pseudo-page, 2 events, 0 records). Not a
lexical entry; nothing to emit or exclude. No impact.

§4c-U7 (`Template:error` via Albanian `sq-decl` template, title `ai`,
1 event). `ai` is 2 letters; both noun and contraction records emitted
(chunk-024). The failure is a foreign-paradigm template, not English
membership evidence. No impact.

### 4d. Re-verified boundary conditions (prior verdict confirmed, not assumed)

- 10 selected five-letter pages with no JSON (`Daaga`, `Opera`, `PEPAP`,
  `achen`, `adact`, `drokk`, `exohm`, `greit`, `likam`, `queem`): 0 records
  each, and every body carries the source `{{no entry|en...}}` marker
  (marker-only or followed by non-English entries). Expected source
  structure, not a parser omission. Cannot add words.
- 3 isolated assertion failures (`Commonwealth of England, Scotland and
  Ireland`; `Green, White and Gold`; `devil to pay, and no pitch hot`):
  each has a single-title `.failed` file (`returncode=1`), 0 records, and
  successful split halves rerun (`.jsonl.tmp` siblings present). One is an
  excluded proper-noun parent; the eligible noun (`Green, White and Gold`)
  and the phrase carry only multiword display heads — their head-template
  arguments are multiword strings, so no complete five-letter
  head-template argument exists to satisfy the explicit rule. Cannot yield
  a 5-letter word. Both validation extractions agree byte-identically
  (125,730 records, record-multiset SHA-256
  `9e7f7d1308cf13418d5bb1bc37d0ac092081458e367ce3e10df100403054f427`),
  confirming no truncation or duplication from the splits.

## 5. Demonstrated systematic fixes: none

Evidence: every one of the 16 signature groups above disposes to an
explicit, policy-grounded exclusion (shape, POS, or already-standalone
representation) or to records demonstrably emitted (chunk-*.jsonl
citations per group). The positive controls are `pieta` and `voila`:
five-letter eligible standalone entries whose error-tagged senses still
emitted and whose source sections retain language, POS, and relationship.
No group shows an eligible five-letter spelling missing from
`wiktionary-standalone-corrected.txt` /
`wiktionary-explicit-form-additions.txt` for an error-related reason.

Required production-transform change: **none**. The ordering defect lived
in diagnostics accounting, which the transform does not consume; the
eligibility/shape/explicit-evidence rules that dispose each group are
unchanged and correct. The fix is contained in the new script's
`ambiguous_overlap` accounting. Do not edit the extractor or the
transform on the basis of these diagnostics.

## 6. Residual false-rejection / coverage uncertainty

- The 32 unresolved events remain a known extraction limitation: Lua
  failures inside quotation, CJK-link/mention, place-display,
  unsupported-title, and foreign-paradigm modules. They are not
  invalid-vocabulary evidence.
- Bounded residual risk: a failure inside one of those modules could in
  principle hide evidence for an otherwise-eligible spelling on the same
  page. Observed behavior cuts against a systematic gap — error-tagged
  records still emit (`error-lua-exec` tags travel with the record rather
  than dropping it), all five-letter titles in these buckets dispose to
  excluded parents or already-standalone forms, and both validation runs
  converge on identical record multisets. Targeted re-extraction is
  justified only if a future demonstrated eligibility-relevant gap
  appears; it is not warranted by this assessment.
- Coverage boundary: the 10 `{{no entry|en}}` marker pages and the 3
  assertion-failure pages are bounded above (§4d) and contribute no
  silent coverage hole beyond what is stated there.

## 7. Commands run (exact)

```sh
cd /Users/tristan/Software/gridrace && PYTHONDONTWRITEBYTECODE=1 python3 scripts/check_extraction_diagnostics.py --consoles /Users/tristan/Software/gridrace-corpus-validation-addendum-2026-09-08/validation/run-fresh-db-fresh-env-2
```

- Runtime: 0.22 s real (0.14 s user, 0.03 s sys), exit 0.
- Result: 102 consoles included; 9,022 ERROR lines →
  `ambiguous_overlap` 2/2 titles, `non_membership_field` 8,950/4,748,
  `potential_membership_field` 38/17, `unresolved_context` 32/28;
  legacy comparison 8,952/38/32 reproduced exactly.
- Determinism: two consecutive runs byte-identical stdout; `--json`
  report schema `{consoles, counts, unique_titles, groups, legacy_counts,
  overlap_lines}` verified.
- Supporting probes (read-only): SQLite `SELECT body` for cited titles
  only against the fresh 5 GB import; cited-title emission scans of the
  preserved chunk JSONL; `.failed`/`.pages.json` reads for the 3 isolated
  pages; membership cross-checks against `corrected-run-2/*.txt` and the
  frozen baseline. No dump re-import, no re-extraction, no writes outside
  the two new files (`PYTHONDONTWRITEBYTECODE=1` used throughout).
- CI does not run `scripts/check_extraction_diagnostics.py`: its inputs
  are cache-resident preserved consoles, not repository fixtures. It is a
  documented-only audit tool.
