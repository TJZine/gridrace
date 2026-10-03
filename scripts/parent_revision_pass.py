#!/usr/bin/env python3
"""One-off dump streaming pass: revision metadata for contributing parents.

Derives the needed non-five-letter parent titles from the committed
provenance file (rows with ``revision_status == "dump_parent"``) and streams
the pinned dump once, writing ``{found, missing, pages_scanned}`` JSON for
``scripts/build_accepted_guesses.py --extra-revisions``.

Regeneration (requires the pinned dump bytes; ordinary builds must NOT run
this; ``--checked-in-only`` is the portable gate and the no-flag source gate
regenerates into a temp dir for comparison):

```sh
python3 scripts/parent_revision_pass.py \
  --dump /Users/tristan/Library/Caches/GridRace/corpus-research-2026-09-08/enwiktionary-20260901-pages-articles-multistream.xml.bz2 \
  --provenance shared/word-packs/daily-classic-en-US-v1-PROVENANCE.jsonl \
  --output shared/word-packs/daily-classic-en-US-v1-parent-revisions.json
```
"""

from __future__ import annotations

import argparse
import bz2
import hashlib
import json
import xml.etree.ElementTree as ET
from pathlib import Path


def child(element: ET.Element, name: str) -> ET.Element | None:
    return next((item for item in element if item.tag.rsplit("}", 1)[-1] == name), None)


def text_of(element: ET.Element | None) -> str:
    return "" if element is None or element.text is None else element.text


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dump", required=True, type=Path)
    parser.add_argument("--provenance", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--titles-file", default=None, type=Path)
    args = parser.parse_args()

    if args.titles_file is not None:
        need = set(json.loads(args.titles_file.read_text(encoding="utf-8")))
    else:
        need = {
            json.loads(line)["parent"]
            for line in args.provenance.read_text(encoding="utf-8").splitlines()
            if json.loads(line).get("revision_status") == "dump_parent"
        }
        need.discard(None)
    print(f"need {len(need)} titles", flush=True)

    found: dict[str, dict[str, str | None]] = {}
    pages_seen = 0
    with bz2.open(args.dump, "rb") as source:
        for _, page in ET.iterparse(source, events=("end",)):
            if page.tag.rsplit("}", 1)[-1] != "page":
                continue
            pages_seen += 1
            title = text_of(child(page, "title"))
            if title in need and text_of(child(page, "ns")) == "0":
                revision = child(page, "revision")
                body = text_of(child(revision, "text") if revision is not None else None)
                found[title] = {
                    "title": title,
                    "pageId": text_of(child(page, "id")),
                    "revisionId": text_of(child(revision, "id") if revision is not None else None),
                    "timestamp": text_of(child(revision, "timestamp") if revision is not None else None),
                    "upstreamTextSha1": text_of(child(revision, "sha1") if revision is not None else None),
                    "textSha256": hashlib.sha256(body.encode()).hexdigest() if body else None,
                }
                print(f"found {len(found)}/{len(need)}: {title}", flush=True)
                if len(found) == len(need):
                    print("all found; stopping early", flush=True)
                    break
            page.clear()
            if pages_seen % 1_000_000 == 0:
                print(f"scanned {pages_seen} pages, found {len(found)}", flush=True)

    print(f"scanned {pages_seen} pages; found {len(found)}/{len(need)}")
    missing = sorted(need - set(found))
    print(f"missing {len(missing)}: {missing[:30]}")
    args.output.write_text(
        json.dumps({"found": found, "missing": missing, "pages_scanned": pages_seen}, indent=1, sort_keys=True)
        + "\n",
        encoding="utf-8",
    )
    print(f"wrote {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
