Status: Active
Scope: Daily Classic + tutorial UI mechanics and visual design refresh (no rules/backend change)
Owner: Primary orchestrator
Started: 2026-09-04
Last updated: 2026-09-04

# Goal

Fix the known UI/UX mechanical defects in Daily Classic and the local tutorial,
and ship one coherent, production-quality visual system — so Home, game,
keyboard, statistics, help, settings, account, and reveal feel designed (not
templated), remain fully accessible, and reuse cleanly when friends/sharing and
live Blind Race arrive.

# Current snapshot

- Daily Classic is complete and local-first; accounts/sync completed locally.
  See `docs/NOW.md`. No `Status: Active` plan existed before this file.
- Worktree is clean on `dev/classic-mode` at plan creation.
- Prior UI review (2026-09-04) found: keyboard scrolls away inside `ScrollView`;
  translucent-white card soup with 4+ opacities and 6+ radii; 8pt keyboard
  evidence glyphs; draft/empty tiles hard to distinguish; duplicated haptics
  toggles; icon-only Help/Settings with weak discoverability; non-tappable
  stats strip; sub-44pt text-button targets; no programmatic focus movement
  into errors/results/reveal; fixed large type that risks AX5 clipping; full-hue
  avatars with untested white-icon contrast; fixed-light colors with no dark
  appearance.
- Game rules, schedule, scoring, sync/conflict, RLS, and deletion behavior are
  frozen and out of scope. The only model change is an observer-only account
  error event used to focus repeated identical errors; it does not change auth,
  sync, deletion, persistence, or error-copy semantics.

# Scope

- `ios/GridRace/App/Views.swift` (tutorial, board, keyboard, tiles, reveal,
  shared color tokens).
- `ios/GridRace/App/DailyViews.swift` (home, game, statistics, settings, help).
- `ios/GridRace/App/AccountView.swift` (signed-out/in, profile editor, sync and
  error cards, avatar).
- `ios/GridRace/App/AccountModel.swift` (observer-only repeated-error event;
  no auth/session/persistence transition change).
- `ios/GridRaceTests/GameRulesTests.swift` and
  `ios/GridRaceTests/AccountTests.swift` (focused duplicate-vector,
  avatar-palette, profile-validator, and repeated-account-error proof only).
- Presentation state in views (e.g. `@AccessibilityFocusState`, `@Environment`
  adaptations) plus the named AccountModel error-event seam. No persistence,
  sync, rule, or product-transition change.
- Light + dark appearances, Dynamic Type through AX5, VoiceOver, Reduce Motion,
  Increased Contrast, Bold Text, usable targets, haptics preference.

# Non-goals

- No change to `docs/game-rules.md`, scoring, schedule, Hard Mode semantics,
  share-text contract, or word packs/vectors.
- No Supabase, migration, RLS, Edge Function, Realtime, APNs, or deletion change.
- No friends, invites, room codes, lobby, live race networking, rematch,
  history beyond Daily statistics, chat, rankings, or monetization.
- No new dependency, architecture framework, design-tool chain, snapshot-test
  library, or CI system. No branding/legal rename.
- No `Wordle` name/`-dle` language, Wordle icon/typography, or green/yellow/gray
  tile system (standing product invariant).

# Invariants and accepted decisions

- Tile/keyboard meaning never depends on color alone: keep symbol + border/
  texture + accessible label (`GameRules.Feedback.symbolName`,
  `accessibilityMeaning`). Color is supplementary.
- Branding stays original; checkered-flag motif is used sparingly (results),
  not as a generic container.
- Views never call Supabase or evaluate authoritative guesses; pure rules stay
  UI-free. Guest play never gates on account/network.
- Share text stays spoiler-safe (puzzle number, count/failure, semantic symbols
  only). Tutorial stays labeled on-device practice; no secrecy claim.
- Accessibility is a requirement: VoiceOver tile/key/state labels, keyboard as
  buttons with 44pt+ targets, focus following visible state, Reduce Motion
  complete-state parity, Increased Contrast strengthening distinctions,
  optional haptics carrying no required meaning.
- Dark appearance must be designed, not inverted by the OS.

# Design direction (interface-design: intent first)

- Intent: a morning commuter with 2 minutes, one-handed, bright sunlight or
  dark bedroom; then a weekend friend group comparing Daily grids. Must
  accomplish today's puzzle fast with zero relearning, then feel the
  race-pressure payoff. Feel: taut like a starting grid — precise, warm,
  quietly competitive. Never casino, never generic SaaS.
- Domain (5+): starting grid, lane assignment, split timer, pit board, photo
  finish, parc ferme (locked result), race control (settings/help).
- Color world (from the domain, not a template): predawn asphalt indigo,
  clay-brick coral, lagoon-teal gauge, warm paper background, carbon ink text.
  Evolve the existing indigo/coral/teal hues into adaptive tokens; do not
  introduce green/yellow.
- Signature: "lane-edge tiles" — feedback lives on a bold leading/lane edge
  plus symbol and label, not just fill. One element that could only be a race:
  opponent progress as a split-time strip showing only already-visible live
  fields (avatar, name, accepted count `n/6`, connection, coarse state) in
  stable roster order — never position, placement, gap-as-rank, exact timing,
  words, or feedback. Neutral result header used once per result.
- Rejecting defaults:
  - translucent `white.opacity(0.58–0.75)` cards → opaque adaptive surfaces
    (`racePage`, `raceCard`, `raceInset`) with one borders-only depth strategy
    on app-owned surfaces (native `Form`/`.alert` stay system-owned);
  - 6+ ad-hoc radii → 3-step scale (control 10, card 18, sheet 26; Circle for
    avatars and Capsule for bars/answer pill are the only named exceptions);
  - tiny 8pt evidence glyph → 11pt bold symbol + lane-edge treatment at full
    key contrast;
  - plain red error text → structured error banner (icon + message + optional
    retry) with single-speech announcement-or-focus (never both);
  - generic stat boxes → 2×2 timing cards (Played / Solved / Streak / Best)
    with tappable strip into Statistics.

# Work units, owners, dependencies, write boundaries

| Unit | Owner | Boundary | Depends on | Status |
| --- | --- | --- | --- | --- |
| U-00 Plan + baseline proof | Controller | this plan + `docs/TODO.md` link maintenance | — | Complete |
| U-01 Design tokens + theming | Controller (serial) | `Views.swift` `Color` extension only; no new file, no `.pbxproj` change | U-00 | Complete |
| U-02 Game surface components | Controller (Wave 1, serial) | `Views.swift` only (`BoardView`/`TileView`/`LetterKeyboardView`/`KeyboardKey`, new `RaceErrorBanner` definition, tutorial `RaceView` pinning) | U-01 | Complete |
| U-03 Home/game-application/stats/help/settings | Controller (Wave 1, serial) | `DailyViews.swift` + `GridRaceTests/GameRulesTests.swift` only (applies U-01 tokens + U-02 banner contract in `DailyGameView`, Home, statistics, settings, help) | U-01 | Complete |
| U-04 Tutorial/opponents/reveal | Controller (serial after U-02) | `Views.swift` only (intro, countdown presentation, opponent strip, reveal; consumes U-02 banner; serial after U-02) | U-01 + U-02 | Complete |
| U-05 Account + avatar | Controller (Wave 1, serial) | `AccountView.swift` + `AccountModel.swift` observer event + `GridRaceTests/AccountTests.swift` | U-01 | Complete |
| U-06 Accessibility + device sweep | Controller | serial fix-ups in owning unit's files only, one file at a time | U-02..U-05 | In progress — formal matrix open |
| R-01 Final independent review | Fresh read-only reviewer (subagent, no writes) | read-only + plan | U-06 | Complete |
| R-02 Remediation re-review | Muse xhigh implementation + fresh read-only reviewers | five Swift/test paths + plan reconciliation | R-01 | Complete |
| C-01 Closeout | Controller | plan, TODO link fix, commits | R-02 + formal U-06 matrix | In progress |

Disjoint-write rule: Wave 1 (U-02, U-03, U-05) holds strictly disjoint path
sets (`Views.swift`; `DailyViews.swift` + `GameRulesTests.swift`;
`AccountView.swift` + `AccountTests.swift`) and may run concurrently. The later
observer-only `AccountModel.swift` remediation was controller-owned and serial.
U-04
shares `Views.swift` with U-02 and runs serially after U-02 merges.
`RaceErrorBanner` is defined once in U-02 from the U-01 contract; U-03, U-04,
and U-05 consume it without redefinition. `RaceView` is owned by U-02;
`DailyGameView` pinning application is owned by U-03. Token shape (U-01)
freezes before Wave 1. No `.pbxproj` change exists in this plan; any future
request for one stops the line for controller approval and High-tier proof.

## U-01 Design tokens + theming (controller, serial)

- Define adaptive tokens in the existing `Views.swift` `Color` extension (no
  new file, no `.pbxproj` change): `racePage`, `raceCard`, `raceInset`,
  `raceInk` (primary/secondary/tertiary), `raceLine` (standard/soft/emphasis),
  `raceIndigo/raceCoral/raceTeal` with explicit light/dark values, plus
  `raceDanger`. Publish a current-container → semantic-token mapping covering
  every existing `white.opacity`/`raceIndigo.opacity` card; `rg` for those
  patterns must return zero app-owned hits after U-02..U-05.
- Freeze radius scale (control 10, card 18, sheet 26; Circle avatars and
  Capsule bars/answer pill excepted), 4pt spacing base (4/8/12/16/20/24), type
  roles (brand/number rounded black + tabular; headline/body/callout/caption
  with Dynamic Type scaling; no fixed 92/56/44pt without `.minimumScaleFactor`
  or scaled-metric equivalents).
- Depth: borders-only on app-owned surfaces; native `Form`/`.alert`/sheets
  stay system-owned and are out of the depth mandate.
- Contrast requirements: body text ≥4.5:1 and large text/icons ≥3:1 against
  their token background in both appearances; feedback fills keep white labels
  at ≥3:1 (see U-05 avatar palette rule for the same bar).
- `RaceErrorBanner` contract (implemented once in U-02): props
  `message: String`, `retry: (() -> Void)?`; single-speech behavior (focus or
  announcement, never both — owner per transition is fixed in U-06).
- Acceptance: mapping table complete with light/dark hexes; Home, game,
  reveal, and account each use only mapped tokens; zero `white.opacity` /
  `raceIndigo.opacity` card fills remain; no green/yellow/gray tile
  regression; share-text generator untouched.
- Verification: Debug + Release simulator builds; light/dark + AX5 visual
  inspection of Home, game, reveal, account with device/OS/orientation/
  content-size recorded per row.

## U-02 Game surface components (Worker A — `Views.swift` only)

- Pin keyboard: move `LetterKeyboardView` out of `ScrollView` into a
  bottom-anchored safe-area container in tutorial `RaceView` (the
  `DailyGameView` application lands in U-03 from this same pattern); scroll
  region holds board/status/result only. Preserve hardware `onKeyPress`,
  focus, haptics, and single-speech error behavior per U-06.
- Tiles: strengthen empty vs. draft (border/weight, not just opacity);
  enlarge feedback symbol treatment; implement lane-edge + symbol; keep
  `TileView` API (`letter/feedback/isDraft/emptyLabel/highContrast`).
- Keys: 11pt bold evidence treatment, contrast-safe fills for
  absent/present/correct with white labels at ≥3:1; keep 48pt min height;
  verify SE-width fit with 4pt gaps.
- Errors: define `RaceErrorBanner` once per the U-01 contract; replace
  divergent red-`Text` instances inside `Views.swift`; keep draft intact on
  reject.
- Invalid-guess motion: subtle shake/nudge, fully suppressed under Reduce
  Motion (immediate banner + haptics only, single speech).
- Mini-grid: owned by U-03 (`DailyViews.swift`); U-02 does not touch it.
- Acceptance:
  - keyboard never scrolls off on provisioned SE portrait;
  - draft vs. empty and all three feedback states distinguishable in
    grayscale + Increased Contrast + Bold Text;
  - invalid input: draft preserved, banner shown, message spoken exactly once
    (focus or announcement per U-06 map, never both);
  - no `white.opacity` card fills remain in `Views.swift`.
- Verification: unit test + simulator build; grayscale + Increased Contrast +
  Bold Text inspection; Reduce Motion on/off for error and row-appear
  animations with device/OS/orientation/content-size recorded.

## U-03 Home/game-application/stats/help/settings (Worker B — `DailyViews.swift` + `GridRaceTests/GameRulesTests.swift` only)

- Keyboard pinning (application): apply the U-02 pinned-keyboard pattern in
  `DailyGameView`; scroll region holds board/status/result only; preserve
  hardware `onKeyPress`, focus, haptics, single-speech errors.
- Home: one opaque `raceCard` daily panel; tappable statistics strip →
  statistics; explicit "How to play / Settings / Practice race" rows reusing
  one `HomeRouteLabel` (toolbar icons remain only as duplicates, never the
  sole route); brand header + `navigationTitle` de-duplication; sync/account
  line clamped to 2 lines max.
- Mini-grid: enlarge or reduce to plain filled cells; never the sole carrier
  of meaning (already `accessibilityHidden`).
- Result panel: neutral solved ("Solved") vs. failed ("Not solved" /
  immutability "Locked result") wording — no competitive "Photo finish"
  implication (Daily results are personal, imported history is never verified
  competition); single flag use; ShareLink + View statistics at 44pt+;
  `NextPuzzleLabel` visual and spoken labels match; share-text generator
  byte-for-byte unchanged (verify by diffing `DailyClassicShare` output
  before/after for solve, sixth-guess failure, and reopened immutable
  results).
- Statistics: convert nav treatment to inline title (drop in-content
  largeTitle); keep 2×2 timing cards + distribution bars; fix bar-count
  overflow (count label never clips on 24pt-min bars); keep
  `ContentUnavailable` empty state.
- Settings: keep native `Form`; document UTC reset + Reduce Motion follow;
  Hard Mode lock footer stays byte-for-byte as specified in Acceptance below.
- Help: keep 3 single-tile `FeedbackExample`s; add a fourth multi-tile
  duplicate-letter example using canonical vector `excess-guess-repeat`
  (answer `grape`, guess `apple`, feedback `[present, present, absent,
  absent, correct]` = `[1,1,0,0,2]`); spoken explanation states the two-pass
  count rule without rewording the rule itself (any new rule wording is
  stop-and-ask). Production view code renders the vector's five fixed expected
  feedback values and contains no assertion or evaluator call. A focused test
  in `GameRulesTests.swift` evaluates `grape`/`apple` and asserts the five
  feedback values; rendered tile labels are verified in the VoiceOver pass
  because the repository has no automated view-testing harness.
- Acceptance: zero icon-only dead ends; every interactive row ≥44pt; the
  Hard Mode footer remains byte-for-byte
  `Hard Mode requires every revealed clue to be reused.` before the first
  accepted guess and
  `Hard Mode is locked after the first accepted guess until tomorrow.` after
  it; `Enter any accepted five-letter word.` remains the Daily playable-state
  guidance and `Type a five-letter word from the tutorial list.` remains the
  tutorial guidance. Every other changed presentation string is recorded as
  an explicit old → new row for controller review; rule/share/sync/privacy
  copy is otherwise byte-for-byte unchanged.
- Verification: AX5 + landscape + native-iPad inspection; VoiceOver order
  Home → Play → stats → account → routes with device/OS/orientation/
  content-size recorded.

## U-04 Tutorial/opponents/reveal (Worker C — `Views.swift` only, serial after U-02)

- Single haptics source: remove intro + race `Toggle`s, link to Settings;
  keep intro privacy banner + on-device disclaimer byte-for-byte (no
  rewording; any edit is stop-and-ask).
- Countdown: presentation only. `CountdownWindow`, `TutorialModel` transitions,
  and existing leaving/replay semantics are untouched — no cancel/back, no new
  transition, no model edit. Allowed: determinate 3s progress indicator and
  the existing combined accessibility label.
- Opponent strip: restyle as split-time rows showing only allowed live fields
  (avatar, name, accepted count `n/6`, connection presentation, coarse
  playing/solved/failed state, small progress response) in stable roster
  order. Forbidden pre-reveal: position, placement, gap-as-rank, exact solve
  time, words, feedback, keyboard state. Guarantee both ghosts visible or
  peeking at 375pt and an adaptive layout at accessibility sizes (no hidden
  controls, truncated counts, or inaccessible scroll content); keep
  `OpponentProgress.accessibilityLabel` contract; keep Reduce Motion
  immediate-update path.
- Reveal: deterministic order (answer → viewer first → roster order →
  top-to-bottom rows → summary) unchanged; neutral answer capsule once;
  staged row animation with Reduce Motion full-state parity and identical
  VoiceOver order; initial focus to answer on appear per U-06 map.
- Acceptance:
  - countdown behavior (background/foreground, restart, replay) identical to
    baseline — existing injected-clock tests stay green, no new transition;
  - pre-reveal inspection shows no rank, time, word, feedback, or placement;
  - reveal order is unchanged and `TutorialModel.comparisonSummary` output is
    byte-for-byte unchanged for its singular/plural local-guess variants:
    `You used <n> guess/guesses. Alex solved in 3. Sam used 6 and failed.`
- Verification: countdown test suite green; simulator background/foreground +
  Reduce Motion reveal inspection with VoiceOver transcript per U-06.

## U-05 Account + avatar (controller — `AccountView.swift`, observer-only
`AccountModel.swift` error event, and `GridRaceTests/AccountTests.swift`)

- Keep all auth/sync semantics; presentation plus the observer-only error event
  described in Scope. Add the exact reassurance line
  `Your email is never shown to other players.` (contract-backed by
  `product-spec.md:109` and `privacy-data-map.md:28`).
- Profile editor: derive enabled state and message from the existing
  `PlayerProfile.normalizedDisplayName` validator (no second regex/ruleset);
  inline message + disabled Save until valid; keep Cancel-restore semantics.
  Cover empty, boundary lengths (1/2/16/17), leading/trailing spaces,
  doubled-space, apostrophe/hyphen, and invalid characters
  (`PlayerProfileTests.testDisplayNameNormalizationMatchesDatabaseBoundary`
  cases plus manual Save-state check per case).
- Sync/conflict cards: keep "Use synced attempt / Keep this device" copy and
  ordering; ensure 44pt targets; do not change the existing import/skip
  callbacks or the model-owned rule that neither action deletes guest files.
- Avatar: preserve seed → symbol stability (do not reorder/remove the symbol
  array). Map each existing index to an explicit background color tested at
  ≥3:1 against white; add a deterministic unit test asserting every palette
  entry passes and snapshotting the seed-to-symbol mapping before/after.
  Keep `PlayerAvatarView(seed:size:)` API.
- Sign out / Delete / Dismiss / Retry: raise to 44pt minima; keep destructive
  confirm copy.
- Acceptance: the import alert remains byte-for-byte
  `Your local results will be saved as personal history. They won't count as
  verified competitive results.`; conflict actions remain byte-for-byte
  `Use synced attempt` then `Keep this device`; no added string describes an
  imported result as `verified`, `official`, or `server-verified`; the only
  added privacy copy is exactly `Your email is never shown to other players.`;
  DEBUG local sign-in stays absent from Release; avatar mapping diff shows zero
  symbol remaps.
- Verification: signed-out/in/restoring/unavailable states inspected at AX5;
  palette unit test green; no credential or token logging introduced (secret
  scan by inspection).

## U-06 Accessibility + device sweep (controller, serial)

- State-to-focus map (covers the full required order; one speech owner per
  transition, never focus + announcement together):
  - countdown → focus countdown label (announcement off);
  - invalid/incomplete draft → focus error banner (announcement off);
  - terminal result → focus result header (result announcement off);
  - reveal answer → focus answer capsule on appear (no duplicate announce);
  - visual staged reveal → only when VoiceOver and Reduce Motion are both off;
    preserve the existing 350ms presentation cadence without speech claims;
  - VoiceOver or Reduce Motion reveal → present a stable full-state tree
    immediately, focus the answer once, and preserve manual traversal order
    answer → viewer board → stable roster boards → top-to-bottom rows →
    summary without auto-cycling focus through already-visible rows;
  - conflict choice → focus conflict heading (no duplicate announce).
  Adjust the existing `UIAccessibility.post` calls in `DailyGameView` so each
  transition speaks exactly once.
- Sweep (combined, not isolated): VoiceOver full pass (board, keyboard,
  opponents, reveal, stats, account); required combined cases —
  provisioned-SE portrait at AX5 + Bold Text + Increased Contrast, SE
  landscape, grayscale keys/tiles, dark mode, adaptive opponent layout at
  accessibility sizes; plus large phone, native iPad (exact device +
  orientation, not "compat"), landscape game-board legibility.
- Fix avatar-hue, bar-label, tile-symbol, and target-size fallout in the
  owning unit's files, one file at a time (no parallel edits to the same
  file).
- Record per-screen evidence rows: device + OS + orientation + content-size →
  input → expected → observed. Capture VoiceOver transcripts for invalid
  input, solve/fail, stable reveal, and Reduce Motion reveal; each message
  occurs once and in the required order. Record staged visual-reveal evidence
  separately because timed focus changes interrupt assistive speech.

# Dependencies and serialization points

- U-01 token + banner-contract freeze gates Wave 1 (U-02, U-03, U-05). U-04
  starts after U-02 merges (shared `Views.swift`).
- Shared-write serial points: active-plan edits, authority-doc updates,
  composition-root change (none expected). No `.pbxproj` change exists; any
  request for one stops the line.
- U-06 starts after Wave 1 + U-04 merge. R-01 and R-02 used fresh read-only
  reviewers; all accepted fixes received targeted controller inspection and a
  final independent rerun.

# Risk tier and verification matrix

- Tier: High for remediation verification because the observer-only
  `AccountModel.errorEvent` seam touches the auth model. Auth/session/sync/
  deletion control flow and strings remain unchanged; the new event only lets
  AccountView distinguish repeated identical errors.
  There is no automated screenshot/view coverage (one unit-test target only),
  so broad visual behavior relies on the explicit manual matrix below. Any
  accidental rule/sync/contract/model-transition drift escalates to High and
  stops the line.
- Required gates (runbook canon; rediscover the simulator `id=` via `-list` /
  `-showdestinations` before reuse; provision the exact SE + native-iPad
  simulators in Blockers before implementation):
  - `git status --short`, `git diff --check`, `git diff --stat`, scoped
    `git diff -- <paths>`.
  - Test (example shape; paste the rediscovered `id=` value):
    `xcodebuild -project ios/GridRace.xcodeproj -scheme GridRace -destination
    'platform=iOS Simulator,id=<UUID>' -derivedDataPath
    /tmp/GridRaceDerivedData-test test` — full suite green, recorded by test
    name (historical baseline: 74 always-on tests; count is not fixed).
  - Focused additions: avatar-palette contrast test (U-05), duplicate-vector
    feedback assertion (U-03), profile-validator boundaries, and repeated
    identical AccountModel error-event proof (U-05); manual Save-state checks
    remain in the matrix. Rendered tile labels remain in manual VoiceOver
    proof; countdown suite stays green untouched (U-04).
  - Debug build (example shape; paste the rediscovered `id=` value):
    `xcodebuild -project ios/GridRace.xcodeproj -scheme GridRace -configuration
    Debug -destination 'platform=iOS Simulator,id=<UUID>' -derivedDataPath
    /tmp/GridRaceDerivedData-build-debug clean build`.
  - Release build (example shape; paste the rediscovered `id=` value):
    `xcodebuild -project ios/GridRace.xcodeproj -scheme GridRace -configuration
    Release -destination 'platform=iOS Simulator,id=<UUID>' -derivedDataPath
    /tmp/GridRaceDerivedData-build-release clean build`.
  - Pre-stage + staged gates per runbook: inspect `git status`, read the full
    task-owned diff, `git diff --check`, stage explicit paths only, inspect
    staged diff + `git diff --cached --stat`, `git diff --cached --check`.
  - Manual evidence matrix (each row records device + OS + orientation +
    content-size): light/dark; AX5; Increased Contrast; Bold Text; Reduce
    Motion on/off; VoiceOver transcripts (invalid, solve/fail, stable reveal +
    Reduce Motion reveal) plus separate staged visual-reveal evidence;
    grayscale tile/key check; provisioned-SE portrait
    AX5+Bold+Contrast combined; SE landscape; native-iPad orientation;
    landscape board legibility.
  - `python3 scripts/check_word_pack.py` only if word surfaces were touched
    (not expected; record as not-run with reason if skipped).
- Unavailable gates: physical device, CI. Record explicitly with substitute
  evidence and confidence; name who must complete remaining proof.

# Decision log

| ID | Decision | Rationale |
| --- | --- | --- |
| DEC-UI-01 | Borders-only depth, 3 radii, 4pt base | Smallest system killing card-soup; matches dense game tool |
| DEC-UI-02 | Evolve indigo/coral/teal, no green/yellow | Preserves original-identity invariant, keeps non-color encoding |
| DEC-UI-03 | Lane-edge + symbol signature | Non-color meaning + ownable race motif in one stroke |
| DEC-UI-04 | Pinned keyboard, scrolling board | Core Wordle-loop mechanics; matches user expectation |
| DEC-UI-05 | Fixed: extend the `Views.swift` `Color` extension; no new file, no `.pbxproj` change | Keeps the plan Medium; any new-file request re-escalates to High |
| DEC-UI-06 | Copy changes are presentation-only; rule/share semantics frozen | Prevents accidental contract drift; wording flags stop the line |
| DEC-UI-07 | Wave 1 disjoint by file (`Views`/`DailyViews`/`AccountView`); U-04 serial after U-02; banner defined once in U-02 | Fixes overlapping worker boundaries (UI-RT-01) |
| DEC-UI-08 | No countdown cancel/back; countdown presentation only, no model edit | Removes hidden state-transition scope (UI-RT-03) |
| DEC-UI-09 | No pre-reveal position/placement/gap-as-rank/timing; stable roster order only | Preserves live-visibility boundary (UI-RT-04) |
| DEC-UI-10 | One speech owner per transition + full state-to-focus map | Prevents duplicate VoiceOver speech (UI-RT-05) |
| DEC-UI-11 | Neutral solved/failed wording; share text byte-for-byte unchanged | Daily results are personal, never verified competition (UI-RT-11) |
| DEC-UI-12 | Duplicate-letter help is vector `excess-guess-repeat` as a 4th multi-tile example | Makes the requirement decision-complete and testable (UI-RT-12) |
| DEC-UI-13 | Avatar seed→symbol mapping frozen; per-index tested palette + unit test | Preserves persisted identities at ≥3:1 (UI-RT-13) |
| DEC-UI-14 | Profile UI derives from `PlayerProfile.normalizedDisplayName`; no second ruleset | Single validator, tested edge cases (UI-RT-14) |
| DEC-UI-15 | VoiceOver reveal uses a stable full-state tree with answer-first manual traversal; staged 350ms visuals run only when VoiceOver and Reduce Motion are off | Timed programmatic focus interrupts speech and cannot be made language/speech-rate safe with fixed delays |

# Review-finding ledger (Codex adversarial reviews, 2026-09-04)

Coverage audit of the 14 post-implementation findings: 10 were explicit plan
requirements missed during implementation (#1–4, #6, #8–11, #13); 2 were
implicit/underspecified acceptance gaps (#5 account-error focus, #12 privacy
placement); 1 was newly discovered (#7 explicit percent-unit rendering); and
1 was a tracking inconsistency (#14 premature U-06 completion).

| ID | severity | location | claim | evidence | disposition | action | verification |
| --- | --- | --- | --- | --- | --- | --- | --- |
| UI-RT-01 | High | Work units / serialization | Worker boundaries overlapped on `Views.swift` and `DailyViews.swift`; `RaceView` owner unnamed | Plan lines 107-118 vs runbook disjoint-file rule | accepted | Repartitioned strictly by file; Wave 1 disjoint, U-04 serial after U-02; banner defined once in U-02, `RaceView` owned by U-02 | Confirm no concurrent packets share a path; every shared type has one owner |
| UI-RT-02 | High | U-01 / risk tier | Optional `Theme.swift` made the plan conditionally High via `.pbxproj` | Plan line 106 vs runbook project/config = High; PBX file/source entries | accepted | Fixed: extend `Views.swift` extension, no new file, no `.pbxproj` change | Net diff excludes `.pbxproj` or re-escalates with project proof |
| UI-RT-03 | High | U-04 countdown | Cancel/back added a hidden state transition | `replay()` clears window/board (`TutorialModel.swift:190-199`) vs "presentation-only" | accepted | Removed cancel/back; countdown presentation only, no model edit | Countdown suite green; behavior identical to baseline |
| UI-RT-04 | High | Design direction / opponents | Pre-reveal "position" crossed the visibility boundary | `game-rules.md:222-239`, `screen-flow.md:104-119` allow count/connection/state only | accepted | Removed position/placement/gap-as-rank/timing; stable roster order | Pre-reveal inspection proves no rank/time/words/feedback |
| UI-RT-05 | High | U-06 focus | Focus map omitted states and risked double speech | Required order `screen-flow.md:158-170`; existing posts `DailyViews.swift:377-390` | accepted | Full state-to-focus map, one speech owner per transition, staged-row rules | VoiceOver transcripts ×4, each message once in order |
| UI-RT-06 | Medium | Risk/verdict baseline | False screenshot-coverage claim; no named focused tests | One unit-test target, no snapshot lib in `.pbxproj:135-144` | accepted | Corrected to no automated view coverage; named avatar/vector/validator tests | Run named tests individually + full suite by name |
| UI-RT-07 | Medium | Command gates | Test destination syntax wrong (`<UUID>` not `id=`); staged gates missing | Runbook canon lines 142-147; commit gates 338-345 | accepted | Fixed `id=<UUID>` shape + full pre-stage/staged gates; 74 = historical baseline | Copy-paste every command; retain exit/output |
| UI-RT-08 | Medium | Device proof | No instantiated SE; "iPad-compat" wrong (native `1,2` per `.pbxproj:192`) | Live `-showdestinations` had no SE | accepted | Provision exact SE + native-iPad sims pre-implementation (see Blockers) | `-showdestinations` shows each named sim; rows carry device/OS/orientation/size |
| UI-RT-09 | Medium | Layout acceptance | Settings/devices listed separately; hardest combos untested | SE checks vs AX5 checks in different sections; 375pt opponent rule | accepted | Required combined cases incl. SE portrait AX5+Bold+Contrast, landscape, grayscale, dark | Capture each combined state; no clip/overlap/hidden content |
| UI-RT-10 | Medium | Design system | Table-vs-cards contradiction; "one system" subjective, no contrast bar | Direction vs U-03; no measured criteria | accepted | Chose 2×2 cards; token mapping with light/dark hexes + contrast bars; Circle/Capsule exceptions; borders-only scoped to app surfaces | `rg` zero ad-hoc fills; measured contrast; screen-vs-map compare |
| UI-RT-11 | Medium | U-03 result copy | "Photo finish!" implies unsupported competition | Daily is local/personal (`product-spec.md:19-26,75-78`) | accepted | Neutral solved/failed wording; share text byte-for-byte check | Diff share output for solve/fail/reopened results |
| UI-RT-12 | Medium | U-03 Help | Duplicate example not decision-complete; single-tile component insufficient | `FeedbackExample` one tile (`DailyViews.swift:674-689`); rule needs 5-letter relation | accepted | Fixed vector `excess-guess-repeat` (`grape`/`apple`/`[1,1,0,0,2]`) as 4th multi-tile example; wording stop-and-ask | Unit test asserts evaluator feedback; manual VoiceOver pass checks rendered labels |
| UI-RT-13 | Medium | U-05 avatar | Hue-dropping remaps persisted seed→symbol identities; ~2.4–2.7:1 current | Shared index (`AccountView.swift:289-303`), persisted seed (`AccountSession.swift:8-20`) | accepted | Frozen mapping + per-index ≥3:1 palette + deterministic unit test + mapping snapshot | Palette test green; zero symbol remaps in diff |
| UI-RT-14 | Medium | U-05 validation | View could duplicate the name rules | Authoritative `normalizedDisplayName` (`AccountSession.swift:27-35`), used in `AccountModel.swift:120-125` | accepted | UI derives from existing validator; edge-case acceptance incl. `AccountTests.swift:21-29` | Manual Save-state check per case |
| UI-RT-15 | Medium | TODO / closeout | `TODO.md:5` links a paused plan as "today's" active plan | Runbook link-maintenance rule; this plan is the only `Status: Active` | accepted | Fix TODO active-plan link without touching backlog candidates (see C-01) | `rg '^Status:'` one Active + TODO links that file |
| UI-RT-16 | Low | Acceptance language | Subjective criteria ("one system", "unchanged in meaning") unadjudicable | Cited plan phrases; prior-review baseline unlinked | accepted | Replaced with state/input/expected-output rows; frozen strings byte-for-byte | Independent reviewer can mark pass/fail from evidence alone |
| RR-01 | High | U-06 reveal focus | Revised map preserved traversal order but did not expose an accessible row/summary sequence | Plan U-06 vs `screen-flow.md:169-170` | accepted, later superseded by DEC-UI-15 | Stable VoiceOver full-state traversal; separate sighted visual staging | VoiceOver transcript must prove answer→rows→summary without duplicate/interrupted speech |
| RR-02 | Medium | Test ownership/testability | Promised tests had no owned test-file paths; rendered-label assertion lacked a view harness | U-03/U-05 boundaries vs focused-test list; one unit-test target only | accepted | U-03 owns `GameRulesTests.swift`; U-05 owns `AccountTests.swift`; evaluator assertions stay in tests and rendered labels stay in manual VoiceOver proof | Worker packets have disjoint app+test paths; focused tests and transcripts recorded |
| RR-03 | Medium | Build commands | Debug/Release gates were not copy-pasteable exact command shapes | Risk/verification section | accepted | Added complete Debug and Release example commands with configuration, destination, and derived-data path | Rediscovered IDs substituted and both commands exit zero |
| RR-04 | Medium | Acceptance language | Subjective copy criteria remained after UI-RT-16 | U-03/U-04/U-05 acceptance | accepted | Frozen strings are byte-for-byte; other changed copy requires explicit old → new rows | Controller compares exact outputs and rejects unlisted semantic changes |
| RR-05 | Medium | Tracking/checkpoint | Untracked plan was omitted from ordinary Git diff checks; evidence/next action were stale | Verification record, commit record, next action | accepted | Record no-index + TODO checks, then stage explicit docs paths, run cached gates, and create the documentation checkpoint before implementation | Verification record + commit record contain exact results; handoff reports commit hash |
| R01-F1 | Medium | `Views.swift` RaceView error focus + `DailyViews.swift` DailyGameView error focus | Repeat/identical-error submit may not refocus the banner: focus set only on appear/same-value assignment, which coalesces and never moves focus | Diff hunks: RaceView banner `.accessibilityFocused($errorFocused)` + `.onAppear`; DailyViews `.onChange` same-value set; traced against `TutorialModel.submitGuess`/`DailyClassicModel.typeLetter` error-nil semantics | accepted | Per-submit focus generation (`errorGeneration`/`errorFocus`, `noteSubmit` on both submit paths incl. hardware Return; generation bump in `onChange` for non-submit errors); `KeyboardView.onSubmitAttempt` hook | `swiftc -parse` clean on all touched files; targeted diff inspection of the changed seam; full Xcode focus proof pending unsandboxed run (see Verification record) |
| R01-F2 | Low | `DailyViews.swift` DuplicateLetterExample | Parallel guess/feedback values can drift or index unsafely | Original generic string/array implementation | accepted, superseded by R02 | One fixed collection of `(letter, feedback)` literal pairs; no assertion/evaluator | Parse-clean; canonical vector test green |
| R01-F3 | Low | `DailyViews.swift` DailyGameView error focus + `AccountView.swift` conflict focus | Focus target never cleared when the error/conflict clears, leaving a stale target so the next set is a same-value no-op | Diff hunks `.onChange` without nil-reset branches | accepted | Nil-reset on clear in DailyGameView (superseded by generation pattern) and assign (`conflictFocused = !isNil`) in AccountView | Parse-clean; inspection; full proof pending unsandboxed run |
| R01-N1 | — | Reviewer assumptions (no issue) | Tile/keyboard defaults, reveal partitioning, and frozen domain/share models | Direct controller inspection | rejected (no issue) | Defaults and global row partition confirmed; `TutorialModel`, `DailyClassicModel`, `AccountSession`, `GameRules`, and `DailyClassic` remain byte-identical; later observer-only `AccountModel.errorEvent` is recorded separately | Verification record |
| R02-F1 | High | Reveal focus and row semantics | Initial/final focus ordering and row labels dropped/interrupted tile speech | Full net-diff review against U-06 and screen-flow | accepted/fixed | Stable VoiceOver full-state tree, answer-first manual order, synthesized letter + feedback row labels | Final independent Views review clean; manual transcript remains U-06 gate |
| R02-F2 | Medium | Contrast and Daily presentation | Dark Increased Contrast strokes, missing `%`/seconds, distribution overflow/zero bars, incomplete duplicate rule | Token/AX/copy inspection | accepted/fixed | Adaptive primary strokes; explicit percent/seconds; external bar counts and zero fill; full two-pass copy | Full suite/builds green; final Daily review clean |
| R02-F3 | Medium | Error/conflict focus ownership | Daily duplicate/terminal focus collisions, silent/repeated account errors, and consecutive conflict focus | State-transition tracing | accepted/fixed | One focus owner per transition; model error event for identical retries; conflict-count generation | Repeated-error regression test + final reviewers clean; manual transcript remains |
| R02-F4 | Medium | Account accessibility | Privacy copy disappeared while editing; 44pt targets not guaranteed; validator boundaries incomplete | U-05 acceptance vs rendered branches/tests | accepted/fixed | One shared reassurance in all signed-in states; label-owned 44pt frames; explicit boundary tests | Account focused tests green; final account review clean |
| R02-F5 | Low | Help implementation | Generic arrays/production assertion contradicted fixed-literal plan | U-03 and Ponytail review | accepted/fixed | Single fixed paired literal collection; evaluator stays in tests | Parse + canonical vector test green |
| R02-F6 | Medium | Tracking | U-06 was marked complete while formal matrix remained unperformed | Status table vs verification/closeout | accepted/fixed | U-06 restored to In progress until the formal matrix is recorded | Active plan retained |
| R03-F1 | High | VoiceOver reveal cadence | 350ms focus changes and fixed 1s delay interrupted speech | Fresh remediation review | accepted; plan corrected | DEC-UI-15 stable VoiceOver traversal replaces animated auto-focus | Three independent reviewers found code clean after correction |
| R03-F2 | Low | Account error invariant | Repeated `errorMessage`/`errorEvent` pairings could drift; exact retry path lacked proof | Ponytail + final integration review | accepted/fixed | Central `presentError(_:)` plus repeated same-message profile-load test | Focused test and full suite green |

# Copy-change ledger (old → new; frozen rule/share/sync/privacy copy otherwise byte-for-byte)

| Location | Old | New | Notes |
| --- | --- | --- | --- |
| Daily result title (solved) | `Finish line!` | `Solved` | Neutral wording per DEC-UI-11; single flag use kept |
| Daily result title (failed) | `Race complete` | `Not solved` | Neutral wording per DEC-UI-11 |
| Daily result caption | (none) | `Locked result.` | Immutability wording; failed icon `flag.fill` → `lock.fill` |
| Statistics cards | `Solve %` / `Current streak` / `Best streak` | `Solved` / `Streak` / `Best`; solved value renders as `<n>%` | 2×2 timing-card naming; percent unit remains explicit visually and to VoiceOver |
| Statistics heading | In-content `Your Daily Race` (largeTitle) | (removed; nav `Statistics` retained) | Inline-title treatment |
| Home routes | `Statistics` row | `How to play` + `Settings` rows | Statistics reached via tappable strip; toolbar icons now duplicates only |
| Home nav title | `Home` | (removed; brand header retained) | Brand/nav de-duplication |
| Opponent count | `N / 6 guesses` | `n/6` + `Connected`/`Disconnected` | Split-time rows; `accessibilityLabel` contract unchanged |
| Help | (3 examples) | + `Same letter twice` / `In APPLE against GRAPE, exact matches use up answer copies first, so E is exact. Leftover copies are then claimed left to right: A and the first P are present while an unused copy remains, and the second P is absent because GRAPE has no P copy left.` | 4th multi-tile explanation of canonical `excess-guess-repeat`; exact-match-first/count-consumption rule made explicit |
| Tutorial intro | `Haptics` toggle (intro + race) | `Haptics and contrast live in Settings` link (intro only) | Single haptics source; Settings owns the toggle |
| Account profile | (none) | `Your email is never shown to other players.` | Exact required reassurance line, signed-in profile only |
| Result header speech | `UIAccessibility.post` announcement | Focused header label (`Solved in N guesses…` / `Daily puzzle failed…` + answer) | Single-speech via focus; same words, spoken once |
| Reveal rows | Board container label only | Per-row player/row + every letter/feedback label; stable VoiceOver answer→rows→summary traversal | Timed visual staging is separate from assistive speech per DEC-UI-15 |

# Verification record

| Surface | Exact command or inspection | Result |
| --- | --- | --- |
| Starting state | `git status --short --branch`; `rg -l '^Status: Active$' docs/plans` | Clean `dev/classic-mode`; no active plan before creation |
| Plan creation | Read runbook, plan format, NOW, prior review | Done 2026-09-04 |
| Adversarial adjudication | Full reads: plan, runbook, AGENTS.md, product-spec, game-rules, screen-flow, architecture, NOW, TODO, DECISIONS, `Views`/`DailyViews`/`AccountView`, `AccountSession`, `AccountTests:21-29`, `game-rules-v1.json`, `.pbxproj` targets/families | All 16 Codex findings reproduced/traced; all accepted into ledger with plan fixes above |
| Re-review adjudication | Read full revised plan and current two-file worktree; traced focus, test ownership, command, copy, and checkpoint findings | RR-01..RR-05 accepted and incorporated; no implementation started |
| Untracked-plan whitespace | `git diff --no-index --check /dev/null docs/plans/2026-09-04-ui-refresh.md` | Clean |
| Tracked docs whitespace | `git diff --check -- docs/TODO.md` | Clean |
| Active-plan uniqueness | `rg -l '^Status: Active$' docs/plans` | Exactly `docs/plans/2026-09-04-ui-refresh.md` |
| TODO link | Inspect `docs/TODO.md` active-plan link; backlog lines unchanged | Links this plan; backlog unchanged |
| Independent checkpoint audit | Fresh read-only subagent inspected RR-01..RR-05 closure, ownership, commands, accessibility, copy, and product boundaries | No remaining content blocker; proceed to controller-owned staged checks and documentation commit |
| Implementation scope | `git status --short`; scoped net diff `9685472..b2ba2b6` | Views/DailyViews/AccountView, observer-only AccountModel event, and AccountTests remediation; no `.pbxproj`, persistence, sync, rule, vector, or contract file touched |
| Frozen contracts | `rg` frozen-string counts; `git diff --quiet 9685472 --` on `DailyClassic`, `TutorialModel`, `DailyClassicModel`, `AccountSession`, `GameRules` | Share/rules/countdown/domain/session behavior byte-identical; AccountModel control flow and error strings unchanged apart from the presentation event seam |
| Opacity migration | `rg 'white\.opacity\|raceIndigo\.opacity\|raceCoral\.opacity\|foregroundStyle\(\.red\)'` on the three view files | Zero hits in all three files |
| Syntax | `swiftc -parse` on all touched Swift files after each Muse remediation pass | `PARSE_OK`; final Xcode compilation also green |
| Vector proof (real code) | Compile `ios/GridRace/App/GameRules.swift` + harness calling `GameRules.evaluate(answer: "grape", guess: "apple")` | `[1, 1, 0, 0, 2]` = canonical `excess-guess-repeat` feedback; `HARNESS_PASS` |
| Avatar proof (independent oracle) | Python cross-check of `AvatarSwatch` literals + `avatarSymbols` vs `AccountTests` expectations | 8/8 swatches ≥3:1 vs white (min 5.37); all 5 seed-index expectations match; symbol snapshot identical |
| R-01 final review | Fresh read-only subagent (no writes), full diff packet | 3 findings (1 medium, 2 low), all accepted and fixed; 1 no-issue assumption rejected with direct controller evidence |
| R-01 fix inspection | Targeted diff inspection of the changed seam + `swiftc -parse` + `git diff --check` | Clean at that checkpoint; later full R-02/R-03 cycles found and closed additional gaps |
| R-02/R-03 remediation review | Muse Code xhigh implementation passes plus independent tutorial, Daily, account, and integration reviewers; final controller net-diff audit | All documented code findings closed. Reviewers independently validated stable VoiceOver order, one speech owner, account repeated errors/targets, Daily units/layout/help, frozen contracts, and Ponytail minimality. Formal device/VoiceOver observation remains separate |
| Final profile/error proof | `AccountModelTests.testRepeatedProfileLoadFailureEmitsErrorEventAgain`; profile/avatar boundary suites | Repeated identical profile-load error increments `errorEvent`; focused Account tests green |
| iOS tests (full suite, post-c539dcb) | `xcodebuild -project ios/GridRace.xcodeproj -scheme GridRace -destination 'platform=iOS Simulator,id=3B9C2E52-7815-4056-8966-BBA6532D23DA' -derivedDataPath /tmp/GridRaceDerivedData-test test` | exit 0, TEST SUCCEEDED; 78 tests executed, 1 skipped (existing local-Supabase integration test, credentials not configured), 0 failures; xcresult `/tmp/GridRaceDerivedData-test/Logs/Test/Test-GridRace-2026.09.04_11-22-34--0400.xcresult` |
| Debug build (clean, post-c539dcb) | `xcodebuild -project ios/GridRace.xcodeproj -scheme GridRace -configuration Debug -destination 'platform=iOS Simulator,id=3B9C2E52-7815-4056-8966-BBA6532D23DA' -derivedDataPath /tmp/GridRaceDerivedData-build-debug clean build` | exit 0, BUILD SUCCEEDED |
| Release build (clean, post-c539dcb) | `xcodebuild -project ios/GridRace.xcodeproj -scheme GridRace -configuration Release -destination 'platform=iOS Simulator,id=3B9C2E52-7815-4056-8966-BBA6532D23DA' -derivedDataPath /tmp/GridRaceDerivedData-build-release clean build` | exit 0, BUILD SUCCEEDED |
| iOS tests (final post-b2ba2b6) | `xcodebuild -project ios/GridRace.xcodeproj -scheme GridRace -destination 'platform=iOS Simulator,id=3B9C2E52-7815-4056-8966-BBA6532D23DA' -derivedDataPath /tmp/GridRaceDerivedData-ui-final-test test -quiet`; summary via `xcresulttool` | Passed: 79 tests, 1 existing local-Supabase credential-dependent skip, 0 failures; total 80; xcresult `/tmp/GridRaceDerivedData-ui-final-test/Logs/Test/Test-GridRace-2026.09.04_12-13-57--0400.xcresult` |
| Debug build (final post-b2ba2b6) | `xcodebuild -project ios/GridRace.xcodeproj -scheme GridRace -configuration Debug -destination 'platform=iOS Simulator,id=3B9C2E52-7815-4056-8966-BBA6532D23DA' -derivedDataPath /tmp/GridRaceDerivedData-ui-final-debug clean build -quiet` | exit 0, clean BUILD SUCCEEDED |
| Release build (final post-b2ba2b6) | `xcodebuild -project ios/GridRace.xcodeproj -scheme GridRace -configuration Release -destination 'platform=iOS Simulator,id=55637EFA-7E16-4A37-9D64-7B5DE9C8FD8C' -derivedDataPath /tmp/GridRaceDerivedData-ui-final-release clean build -quiet` | exit 0, clean BUILD SUCCEEDED on native iPad simulator |
| Manual evidence matrix (formal) | Device/Simulator visual + VoiceOver inspection per Next action | NOT PERFORMED as a formal matrix. Rows (VoiceOver transcripts for invalid, solve/fail, stable reveal, and Reduce Motion reveal; separate staged visual reveal; grayscale; confirmed Bold Text combined case; SE landscape/full scrolling/target audit; iPad landscape; account/stats/help/settings passes) remain genuinely unperformed; sole remaining blocker. Partial smoke below is not matrix evidence |
| Partial simulator smoke (post-293b897, SE portrait) | Provisioned iPhone SE (3rd generation), iOS 26.5, `id=3B9C2E52-7815-4056-8966-BBA6532D23DA`, portrait. Home rendered in standard light appearance. Then, with content_size `accessibility-extra-extra-extra-large`, increase_contrast enabled, and appearance dark (each confirmed via simctl), Home rendered with the header and Daily card visible | PARTIAL smoke only. Not a matrix pass: no scrolling/target audit, no landscape, no VoiceOver transcript, no solve/fail or reveal flow |
| Partial simulator smoke (post-293b897, SE Bold Text caveat) | `BoldTextEnabled` simulator preference was written | NOT independently confirmed — the combined Bold Text case is NOT claimed as passed and remains in the open matrix |
| Partial simulator smoke (post-293b897, native iPad portrait) | Native iPad (A16), iOS 26.5, `id=55637EFA-7E16-4A37-9D64-7B5DE9C8FD8C`, portrait, standard light. Home, tutorial intro, countdown, and active tutorial race visually inspected through the Simulator. Accessibility state exposed explicit Home routes, the countdown label, both opponents with only name/count/coarse state/connection, the board, guidance, and the keyboard. The active-race screenshot showed both opponents and the keyboard visibly pinned at the bottom | PARTIAL smoke only. Not a matrix pass: no iPad landscape, no solve/fail or reveal flow, no VoiceOver transcript, no account/stats/help/settings full pass |
| Word pack gate | `python3 scripts/check_word_pack.py` — word surfaces untouched | NOT RUN with reason recorded (no word-pack/vector/source change) |

# Commit record

| Commit | Purpose | Status |
| --- | --- | --- |
| 9685472 | `docs: finalize UI refresh implementation plan` | Complete documentation checkpoint before implementation |
| 0e4a749 | `feat(tutorial): pin keyboard, lane-edge tiles, split-time opponents, reveal focus` | U-01/U-02/U-04/U-06/R-01 implementation in `Views.swift` |
| e38b235 | `feat(daily): refresh home, game, statistics, help, and settings` | U-03/U-06/R-01 implementation in `DailyViews.swift` + `GameRulesTests.swift` |
| 7d574fb | `feat(account): refresh account presentation and avatar palette` | U-05/U-06/R-01 implementation in `AccountView.swift` + `AccountTests.swift` |
| c539dcb | `docs(plan): record UI refresh implementation, review, and verification` | Implementation + R-01 + verification record; plan stayed Active pending Xcode gates |
| 293b897 | `docs(plan): record successful iOS verification` | Post-c539dcb test + Debug/Release verification record; plan stays Active pending manual visual/VoiceOver matrix |
| 0121f09 | `docs(plan): record partial simulator smoke evidence` | Post-293b897 PARTIAL simulator smoke only (SE portrait standard-light + AX-large/contrast/dark Home; unconfirmed Bold Text preference; iPad portrait Home/intro/countdown/active-race inspection); plan stays Active pending the formal matrix |
| b2ba2b6 | `fix(ui): close accessibility review gaps` | Muse xhigh remediation + independent re-review: all static code findings closed; observer-only AccountModel event covered by regression test |
| 36a6816 | `feat(docs): add review context documentation` | Concurrently created/pushed generated `.codex/cache` files; non-product cache commit, corrected without rewriting history |
| daa9042 | `chore(repo): untrack generated review cache` | Removed generated cache from tracking per review-context-loader policy; recoverable from 36a6816 |
| this commit | `docs(plan): record UI remediation and re-review` | Plan reconciliation, final automated evidence, and DEC-UI-15; stays Active pending formal manual matrix |

# Blockers

- Pre-implementation simulator provisioning: CLEARED 2026-09-04 by controller.
  Provisioned exact destinations (from `-showdestinations`):
  - `iPhone SE (3rd generation) on iOS 26.5 with id=3B9C2E52-7815-4056-8966-BBA6532D23DA`
  - `native iPad (A16) on iOS 26.5 with id=55637EFA-7E16-4A37-9D64-7B5DE9C8FD8C`
  Recorded here before product implementation; U-06 evidence rows must carry
  these device + OS values with orientation + content-size per row
  (UI-RT-08/09).
- External Apple-provider/device proof remains out of scope (per NOW.md).
- Post-b2ba2b6 Xcode verification: CLEARED. Final suite passed 79 tests with
  one existing credential-dependent integration skip and zero failures; clean
  Debug SE and Release native-iPad builds exited 0 (see Verification record).
  Sole remaining blocker: the formal manual visual and VoiceOver matrix is
  genuinely unperformed (see Next action).
- Post-293b897 partial simulator smoke: RECORDED, not a matrix pass (see
  Verification record). SE portrait standard-light Home plus AX-large /
  contrast / dark Home with header and Daily card visible; iPad portrait
  Home, intro, countdown, and active tutorial race inspected with both
  opponents and pinned keyboard visible. `BoldTextEnabled` was written but
  not independently confirmed, so the combined Bold Text case is not
  claimed. Does not clear the formal-matrix blocker.

# Stop and ask (extends runbook; adjudicated additions marked *)

- Any wording change that could alter a game rule, share contract, sync/conflict
  meaning, privacy claim, or MVP scope.
- Any proposal to weaken non-color encoding, RLS/isolation, secret handling,
  idempotency, VoiceOver/Motion/Contrast support, or deletion behavior.
- Any new dependency, file requiring `.pbxproj` surgery the controller did not
  approve, overlapping writes, or failed Medium-gate that cannot resolve in scope.
- Any discovery that a "presentation-only" change needs model/persistence/sync
  edits — return to controller before widening the boundary.
- *Any pre-reveal label/ordering implying rank, placement, timing, or hidden
  progress; any new tutorial transition (incl. countdown cancel) even via an
  existing model method (UI-RT-03/04).
- *Any `.pbxproj` edit or unexecutable device/accessibility gate — changes risk
  or leaves an owned gap (UI-RT-02/08).
- *Any focus change causing dual speech via focus + `UIAccessibility.post`
  (UI-RT-05).
- *Any future avatar seed→symbol remap or rewrite of the tutorial disclaimer,
  reveal summary, Hard Mode footer, or the now-frozen duplicate-letter
  explanation (UI-RT-12/13).

# Next action

Implementation and R-01/R-02/R-03 code adjudication are complete at
`b2ba2b6`. Final verification is green: 79 tests passed, one existing
credential-dependent integration test skipped, zero failed; clean Debug SE
and Release native-iPad builds succeeded. Plan stays Active because U-06's
formal manual visual and VoiceOver matrix is still genuinely unperformed —
this is the sole remaining next action and blocker.
Post-293b897 partial simulator smoke is recorded above but counts as PARTIAL
evidence only. Complete the remaining formal matrix observations (VoiceOver
transcripts for invalid, solve/fail, stable reveal, and Reduce Motion reveal;
separate staged visual reveal; grayscale; confirmed Bold Text combined case;
SE landscape and full scrolling/target audit; iPad landscape; account/stats/
help/settings full passes), recording
device + OS + orientation + content-size per row. Only when the matrix is
filled may the plan be set Historical with the closeout commit hash. Do not
push.

# Closeout checklist

- [x] All implementation/remediation units accepted with file-scoped diffs inspected; U-06 remains open only for formal observation.
- [x] Final iOS tests + Debug/Release builds green post-b2ba2b6 (79 passed, 1 skipped, 0 failures; both clean builds succeeded; see Verification record).
- [ ] Formal manual visual and VoiceOver matrix rows filled — NOT PERFORMED (post-293b897 partial simulator smoke recorded as PARTIAL evidence only); sole remaining blocker and next action.
- [x] All documented code-review findings adjudicated and closed across the plan red-team, R-01, and Muse remediation re-reviews; final tutorial/Daily/account/integration reviewers found no remaining static code defect.
- [x] `TODO.md` active-plan link points here; backlog candidates untouched; no stale references.
- [ ] Status set Historical with closeout commit hash in handoff; no push — stays Active until the manual matrix above is filled.
