#!/usr/bin/env python3
"""Generate the pinned Daily Classic English word pack and manifest."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
SOURCE = Path("/usr/share/dict/web2")
PACK = ROOT / "shared/word-packs/daily-classic-en-US-v1.json"
MANIFEST = ROOT / "shared/word-packs/daily-classic-en-US-v1.manifest.json"
SOURCE_SHA256 = "be41ad97963bf8dabedd5871d5d691596175269d540956b0f9965a885c2bbab9"
WORD = re.compile(r"[a-z]{5}", re.ASCII)

# This order is the v1 answer schedule. Published entries must never be reordered or
# removed; a later pack may only append answers or introduce a new schedule version.
ANSWERS = """
adore ample apple arise array beach blend block bloom board brain bread brick bring
cabin candy chair charm chase cider civic clean clear climb cloud coast cocoa coral
crane dream eager earth ember faith flame flora focus frame fruit glass globe grace
grain grand grape heart honey horse house ivory jelly kneel lemon light lodge lucky
magic maple metal mirth mouse music night ocean olive paint peach pearl piano pilot
plant pride quiet radio river roast robin rough round shine shore smile solar spice
stone storm sugar table tiger toast trail train uncle vivid water whale wheat world
youth zebra abase abate abbey abbot abide abode above abuse acute admit adopt adult
after again agent agile agree ahead alarm album alert alien alike alive allow alone
along alter among angel angry ankle apart arena argue armor aroma aside asset atlas
avoid awake award aware awful bacon badge badly baker basic basin basis batch bathe
beard beast begin being below bench berry birth black blade blame blank blast blaze
bleak bleed bless blind bliss blond blood blown blues blunt blush boast bonus boost
booth bound bowel boxer brace braid brake brand brave brawl break breed bribe bride
brief broad broke brook broom brown brush build built bunch burst buyer cable cache
camel canal canoe cargo carry carve catch cater cause cedar chain chalk champ chant
cheap cheat check cheek cheer chess chest chief child chili chill choir chose chuck
chunk claim clash clasp class clerk click cliff cloak clock clone close cloth clown
coach color comic comma conch condo couch cough count court cover crack craft
crash crate crave crawl crazy creek crest crime crisp cross crowd crown crude crush
crust curry curve cycle dairy dance dealt death debit delay delta depot depth diary
digit diner dirty ditch diver dizzy dodge donor doubt dough dozen draft drain drama
drawn dress dried drill drink drive early elbow elder elect elite empty
enemy enjoy enter entry equal error essay event every exact exist extra fairy false
fancy fatal fault favor feast fence ferry field fiend fifth fifty fight final first
fixed flair flake flash flask fleet flesh flick fling float flock flood floor flour
flown fluid flush force forge forth forty forum found fresh front frost froth funny
giant given glare gleam glide gloom glory glove going goose gorge gouge grade graft
grant graph grasp grass grave gravy great green greet grief grill grind groan group
grown guard guest guide guilt habit happy harsh haste haunt haven hazel heard heavy
hedge hinge hobby hoist honor hotel hound hover human humor ideal image imply inbox
index inert inner input issue joint judge juice knife knock known label labor large
later laugh layer learn least leave ledge legal level lever lilac limit linen liver
loose lover lower loyal lunch major maker manor march marry match maybe mayor medal
media mercy merge merit merry midst might minor model money month moral motor mount
movie muddy never noble noise north novel nurse occur offer often order other ought
outer owner panel panic paper party paste patch pause peace penny phase phone photo
piece pinch pitch pizza plain plane plate plaza plead plume point porch pound power
press price prime print prize proof proud queen quick raise range rapid reach ready
realm rebel reply rider ridge rifle right rigid rival robot rocky route royal
rugby rural scale scare scarf scene scoop scope score scout screw serve shade shake
shall shape shark sharp sheep sheet shelf shell shift shirt shock shoot short shout
shown sight silly skill skirt slate sleek sleep slice slide slope small smart smoke
snack snake solid solve sound south space spare spark speak speed spell spend spent
spike spill spine spite split spoon sport spray stack staff stage stair stake stand
start state steam steel steep steer stick still stock stood store story stove strap
straw strip stuck study style swear sweep sweet swift swing sword taste teach thank
their theme there thick thief thing think third thorn three throw tight timer tired
title today token tooth topic torch total touch tower trace track trade treat trend
trial tribe trick troop truck truly trust truth twice under union unite until upper
urban usage usual vague valid value video visit voice waste watch weary weird wheel
where which while white whole woman woody worry worth would wound write wrong yeast
young
""".split()

# Answers are checked against this denylist in addition to manual review. Accepted
# guesses intentionally remain lexically broad; accepting a word does not endorse it.
BANNED_ANSWERS = frozenset(
    {
        "bitch",
        "chink",
        "cunts",
        "dykes",
        "fagot",
        "gooks",
        "kikes",
        "nigga",
        "nigger",
        "sluts",
        "spics",
        "whore",
    }
)


def canonical(value: object) -> bytes:
    return (json.dumps(value, indent=2, ensure_ascii=True) + "\n").encode()


def build() -> tuple[bytes, bytes]:
    source = SOURCE.read_bytes()
    actual_checksum = hashlib.sha256(source).hexdigest()
    if actual_checksum != SOURCE_SHA256:
        raise ValueError(
            f"unexpected {SOURCE}: {actual_checksum}; expected {SOURCE_SHA256}"
        )

    invalid_answer_format = [word for word in ANSWERS if WORD.fullmatch(word) is None]
    if invalid_answer_format:
        raise ValueError(f"invalid answer format: {invalid_answer_format}")
    accepted = sorted(
        ({
            word
            for line in source.decode("utf-8").splitlines()
            if WORD.fullmatch(word := line.strip()) is not None
        } | set(ANSWERS))
        - BANNED_ANSWERS
    )
    if len(ANSWERS) != len(set(ANSWERS)):
        raise ValueError("answer schedule contains a duplicate")
    invalid_answers = set(ANSWERS) - set(accepted)
    if invalid_answers:
        raise ValueError(f"answers absent from accepted guesses: {sorted(invalid_answers)}")
    banned_answers = set(ANSWERS) & BANNED_ANSWERS
    if banned_answers:
        raise ValueError(f"banned answers: {sorted(banned_answers)}")

    pack = {
        "formatVersion": 1,
        "id": "daily-classic-en-US-v1",
        "locale": "en-US",
        "wordLength": 5,
        "scheduleVersion": 1,
        "epochDay": 20696,
        "schedulePolicy": "Fixed answer order; never reorder or remove published v1 entries.",
        "provenance": {
            "acceptedGuessSource": "macOS /usr/share/dict/web2",
            "acceptedGuessSourceSha256": SOURCE_SHA256,
            "acceptedGuessLicense": (
                "System README identifies Webster's Second International and states "
                "that its 1934 copyright has lapsed according to the supplier."
            ),
            "acceptedGuessTransform": (
                "Unique lowercase ASCII entries exactly five letters long, plus "
                "originally curated answers, sorted with the answer denylist removed."
            ),
            "answerCuration": (
                "Original GridRace manual selection of familiar, non-proper, "
                "non-abbreviated words from the system corpus, with familiar additions."
            ),
            "commercialListUse": (
                "No commercial word-game answer or accepted-guess list was copied, "
                "scraped, or adapted."
            ),
            "reviewedOn": "2026-08-31",
        },
        "manualReview": {
            "answersFamiliar": True,
            "answersNonProper": True,
            "answersNonAbbreviated": True,
            "answersSensitiveTermsReviewed": True,
        },
        "acceptedGuesses": accepted,
        "answers": ANSWERS,
    }
    pack_bytes = canonical(pack)
    manifest = {
        "formatVersion": 1,
        "source": PACK.name,
        "packID": pack["id"],
        "packVersion": pack["formatVersion"],
        "scheduleVersion": pack["scheduleVersion"],
        "epochDay": pack["epochDay"],
        "locale": pack["locale"],
        "wordLength": pack["wordLength"],
        "answerCount": len(ANSWERS),
        "acceptedGuessCount": len(accepted),
        "sha256": hashlib.sha256(pack_bytes).hexdigest(),
    }
    return pack_bytes, canonical(manifest)


def main() -> int:
    pack, manifest = build()
    PACK.write_bytes(pack)
    MANIFEST.write_bytes(manifest)
    print(f"generated {len(ANSWERS)} answers in {PACK.name}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
