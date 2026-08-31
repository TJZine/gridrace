# Daily Classic en-US v1 sources

The accepted-guess corpus is generated from macOS `/usr/share/dict/web2`, pinned
at SHA-256
`be41ad97963bf8dabedd5871d5d691596175269d540956b0f9965a885c2bbab9`.
The adjacent system README identifies the source as Webster's Second International
and says its 1934 copyright has lapsed according to the supplier. GridRace retains
only unique lowercase ASCII entries exactly five letters long, then adds its own
curated answers and removes the answer denylist.

The ordered answer schedule is an original GridRace manual selection of familiar
ordinary English words from that corpus, with a few familiar additions. It does not
use or adapt any commercial word game's answer or accepted-guess list. Answers were
reviewed to exclude proper nouns, abbreviations, offensive terms, and unsuitable
entries. Published v1 answer positions are append-only and must never be reordered.
Puzzle #1 is fixed to UTC day 20696, 2026-08-31 at 00:00 UTC.

Regenerate with `python3 scripts/generate_daily_word_pack.py`; validate both the
development and Daily Classic packs with `python3 scripts/check_word_pack.py`.
