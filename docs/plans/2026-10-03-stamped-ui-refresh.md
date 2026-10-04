Status: Active
Scope: GridRace iOS presentation refresh to the accepted stamped scorecard direction
Owner: Codex stamped UI refresh primary controller (/root)
Started: 2026-10-03
Last updated: 2026-10-03

# Stamped UI Refresh

## Activation gate

Activation completed on 2026-10-03 under the human's rescope authorization.
The repository allows one Active plan. [Phase 4](2026-10-02-phase-4-blind-race.md)
is now Historical; its unproved A9 OS-assisted accessibility checks belong to S4.
The following is the completed docs-only activation procedure.

**Human decision 2026-10-03: rescope.** Phase 4's A9 proof moves to slice S4 of
this plan. Activation steps, in order, as one docs-only checkpoint:

1. Record the transfer in the Phase 4 plan, set it `Status: Historical` with its
   last content checkpoint (`253698a` or later), and state that A9 (including
   hardware keyboard input and haptic preference) is owned by this plan's S4.
   Phase 4 software proof stays as recorded; no completion claim beyond it.
2. Repoint every authority that names the Active Phase 4 plan to this plan or to
   Phase 4 as Historical evidence, in the same pass: `docs/NOW.md`,
   `docs/TODO.md`, `docs/DECISIONS.md` (header), `docs/game-rules.md`,
   `docs/screen-flow.md`, `docs/architecture.md`, `docs/product-spec.md`,
   `docs/privacy-data-map.md`, `docs/live-api-contract.md`. Re-run
   `rg -n "Active Phase 4|phase-4-blind-race" docs AGENTS.md` and resolve every
   hit.
3. Set this plan `Status: Active`, name the controller, refresh the snapshot, and
   capture a fresh unrelated-file baseline.
4. Commit the checkpoint before any product write.

## Goal

Ship the presentation in [`../design-direction.md`](../design-direction.md)
across Home, Daily, Live, and supporting screens, with shared leaf components
replacing duplicated tutorial/live pieces, without changing game rules,
session/state machines, storage, backend, or share text.

## Snapshot at activation (2026-10-03)

- Branch `dev/classic-mode`; starting HEAD
  `2d19d2c5b8263fe176dc77af167fe7c19f588081`. The human authorized starting from
  the latest commit after the kickoff-file commit check differed. Phase 4 is
  Historical with its software proof preserved and A9 transferred to S4.
- Empty index and clean tracked tree at kickoff. Six unrelated untracked files
  match the expected set; their path-to-SHA-256 baseline is
  `.codex/runs/stamped-ui-refresh/unrelated-baseline.json`. Never stage, reset,
  stash, overwrite, or refresh these files.
- Presentation lives in `DailyViews.swift` (1,313 lines: routing, Home,
  `LiveCreateControls`, game, stats, settings, help, attribution),
  `LiveMatchViews.swift` (1,154), `Views.swift` (800: tutorial plus shared board,
  tile, keyboard, color tokens), `AccountView.swift` (443, includes
  `PlayerAvatarView`).
- Duplicated pieces: `CountdownView`/`LiveCountdownView`,
  `RevealView`/`LiveRevealView`, `RevealRowView`/`LiveRevealRowView`,
  `OpponentStrip`/`LiveOpponentRow`, `RaceErrorBanner`/`LiveErrorBanner`.
- Explicit Xcode file references (no synchronized groups): adding or splitting
  Swift files edits `project.pbxproj`. iOS 18.0, Swift 6 strict concurrency,
  `TARGETED_DEVICE_FAMILY = "1,2"` (native iPad), no orientation lock.
- Strings asserted in tests: `LiveMatchPresentation` (`LiveMatchViewTests`).
  `DailyClassicModelTests` and `AccountTests` compare `DailyHomeStatus` and sync
  status enum values, not strings.
- Presentation strings outside view files: `DailyHomeStatus` title/action/symbol
  (`DailyClassicModel.swift`), `DailyAccountCoordinator.syncMessage`, tutorial
  error copy in `TutorialModel.swift`.

## Scope

- Foundation: color roles (light, dark, Increased Contrast), serif + mono type
  roles, round-seal tile, keyboard states, ink button styles, card surface, seal,
  notice card, keyboard-slot container, height-aware board sizing.
- File split by screen; shared leaf components (tile row, countdown numeral,
  opponent line, notice) with per-flow containers kept.
- Home program schedule; Daily game, result card, statistics.
- Live entry (Create/Join/Resume) inside the Live screen, lobby with Copy and
  Share (code text only), countdown, round, waiting card, notices, reveal,
  standings, final and incomplete results; native confirmation before every
  Discard.
- Settings, How to play, Word list credits, Account (signed out/in, import and
  conflict sheets), Practice/tutorial.
- Copy voice per the design doc table and the live state table below.

## Non-goals

- No rules, scoring, timer, session/state-machine, storage, sync, backend, API, or
  share-text change. `GameRules.Feedback.symbolName` stays as is.
- No invite links, deep links, opponent connectivity, rematch, or new modes.
- No custom fonts, new dependencies, snapshot-test library, orientation lock, or
  user-facing tile shape setting. Passport-stamp tiles stay a designated, unbuilt
  fallback.

## Invariants

- Meaning never depends on color: symbol, fill/ring/no-tile form, and accessible
  label carry feedback on board, keyboard, and mini boards.
- Claret is for marks only; anything tappable is ink.
- Pre-reveal secrecy: opponents show name, accepted count, and coarse state in
  stable roster order only; solve times appear only after reveal.
- Tutorial stays labeled as on-device practice, distinct from live races.
- `DailyClassicShare.text(for:)` output unchanged byte-for-byte.
- Live recovery gating is preserved exactly: `canRetry`,
  `canRetryRecoveryStorage`/`canDiscardRecovery`, `discardAction`,
  `showsSavedRecovery`, `canStart`, phase checks, failed Join never offering the
  old room as a retry, saved Start retrying the original round. Additions are
  limited to the decisions below.
- Views render state and send intents; no Supabase calls or evaluation in views.
- Accessibility: VoiceOver labels and focus order per `screen-flow.md`, 44pt
  targets with the approved compact-QWERTY letter-key exception (D15), Reduce
  Motion parity, Increased Contrast strengthens, Dynamic Type on
  all text roles, no truncation (round view scrolls at accessibility sizes).

## Accepted decisions

| ID | Decision |
| --- | --- |
| D1 | Direction, Home, live flow, notices, Daily, supporting screens, and copy as recorded in `design-direction.md` (accepted 2026-10-03). |
| D2 | One plan in slices. S1–S3 run in parallel after S0b, each in its own controller-created worktree (D9). |
| D3 | Signed-out entry: Home's Live row opens the Live screen, which shows "Sign in to race". Its Sign in action presents the existing Account flow as a sheet that dismisses itself when `isSignedIn` changes from false to true and `needsProfileSetup` is false (an `onChange`, so an already-signed-in account never auto-dismisses), returning to Live entry. No second Sign in with Apple control in live views. |
| D4 | Live entry is the branch `phase == .inactive && snapshot == nil` (no pending-intent exclusion). It shows a Resume row when `hasSavedMatch`, calling `resumeSavedMatch()`; Host a race (Create) and Join a race. `.storageUnavailable` keeps its own branch. Home's Live row keeps a Resume/Resolve stamp (D10). |
| D5 | Native `List`/`Form` stays for Settings and Account, restyled on paper; system sheets, alerts, and confirmation dialogs stay system-owned. |
| D6 | Cross-unit contracts land in S0b before S1–S3: `LiveMatchFlowView(isSignedIn:openAccount:)` with defaults and its AppRouting call; `AccountView` gains `conflict: DailySyncConflict?` fed from `app.conflicts.first`; `LiveCreateControls` and `PlayerAvatarView` are relocated by S0a. |
| D7 | `needsSignIn` is distinct from signed out (server auth rejected, local account still signed in, race saved): notice "Your sign-in expired" with Back to race (`leaveToHome()` without dismiss; the entry Resume row then retries the session) and Open account (same sheet; it does not auto-dismiss because sign-in state does not change). Copy warns that signing out removes the saved race from this device, because `changeAccount(to: nil)` clears live recovery. |
| D8 | Every Discard (`discardPendingCreate`, `discardPendingGuess`, `discardRecovery`) asks for native confirmation first. This is a new step, not a gating change. |
| D9 | Parallel isolation: the controller creates one worktree per S1–S3 unit from the S0b commit, a cloned simulator and derived-data path per unit, and runs one frozen package resolve per path before dispatch. Workers never mutate Git; the controller applies each returned diff to the main checkout and verifies it there. Integration order is S2, then S1, then S3, so Home's inline Live controls are removed only after the entry branch exists. Until S1 merges, S2 keeps `LiveCreateControls(live:isSignedIn:openRoute:roundCount:)` source-compatible and its existing route tests passing; the controller adjusts the old Home call during S2's merge if needed. |
| D10 | Home's Live row status reflects existing session state: `storageUnavailable` → "Saved race needs attention" with a Resolve stamp (opens Live); `hasSavedMatch` → "Saved race" with a Resume stamp (calls `resumeSavedMatch()`, opens Live); otherwise "Create or join a room". |
| D11 | Lobby: while only one player is present the host sees "Waiting for player two" with Copy and Share and no Start button; Start appears when player two joins and is disabled only for the existing in-flight, pending, expiry, and phase blockers. |
| D12 | Contrast: light ink secondary is `#6B6352` (5.0:1 on page). Absent letters at ≥3:1 follow Apple's HIG minimum for bold text of any size; tile letters (`title2`, about 22pt) and key labels must stay bold. (WCAG large text would not cover 16pt bold keys; the HIG bold rule is the accepted bar.) Empty dashed rings are decorative at default (slot geometry and the solid draft row identify the board); Increased Contrast and the High-contrast feedback setting switch to one set: absent letter `#6B6352` / dark `#A39A86`, empty rings in ink secondary, present ring 3.5pt, correct unchanged. |
| D15 | Human approved the compact standard QWERTY letter-key exception on 2026-10-03: about 32.3pt wide at SE default type, at least 48pt tall. Action controls retain at least 44×44pt targets. No overlapping targets or alternate default keyboard layout. S4 measures actual regions and confirms usability; other accessibility obligations remain. |

## Target file layout (S0a)

| File | Contents |
| --- | --- |
| `DesignSystem.swift` | Color/type roles, button styles, card surface, seal, notice card, keyboard-slot container, `PlayerAvatarView` |
| `BoardViews.swift` | Board (height-aware sizing), round-seal tile, letter keyboard and key, tile row, countdown numeral, opponent line |
| `AppRouting.swift` | `AppRoute`, `DailyAppView` navigation, Account sheet |
| `HomeView.swift` | Home |
| `DailyGameViews.swift` | Daily game, result card |
| `StatisticsView.swift` | Statistics |
| `SettingsHelpViews.swift` | Settings, How to play, Word list credits |
| `TutorialViews.swift` | Practice intro, race, reveal container |
| `LiveMatchViews.swift` | `LiveMatchFlowView`, `LiveMatchPresentation`, `LiveCreateControls`, entry, lobby, countdown, round |
| `LiveResultViews.swift` | Live reveal container, standings, final, incomplete |
| `AccountView.swift` | Account and sheets |

`Views.swift` and `DailyViews.swift` are removed once empty.

## Work units

| Unit | Role | Write boundary | Depends on | Status | Evidence |
| --- | --- | --- | --- | --- | --- |
| S0a Mechanical split | worker | all App view files, `project.pbxproj` | activation commit | Complete | 52 declaration bodies unchanged; six access changes; full iOS 214 passed/two opt-in skips; clean Debug; controller differential audit |
| S0b Foundation + contracts | worker | `DesignSystem.swift`, `BoardViews.swift`, color/type call sites in all view files, D6 stubs, `LiveMatchViewTests.swift` (token references only) | S0a commit | Complete | 214 passed/two opt-in skips; clean Debug; 56 measured contrast pairs; controller audit; D15 approved |
| S1 Daily | worker | `AppRouting.swift`, `HomeView.swift`, `DailyGameViews.swift`, `StatisticsView.swift`, `DailyHomeStatus` in `DailyClassicModel.swift` (presentation properties only), `DailyClassicModelTests.swift` | S0b commit | Complete; integrated after S2 | 220 total / 218 passed / two opt-in skips on main; SE/Pro native captures; sheet reducer/lifecycle coverage |
| S2 Live | worker | `LiveMatchViews.swift`, `LiveResultViews.swift`, `LiveMatchViewTests.swift` | S0b commit | Complete; integrated | 217 total / 215 passed / two opt-in skips on main; 45 native state fixtures; controller audit |
| S3 Supporting | worker_luna | `SettingsHelpViews.swift`, `TutorialViews.swift`, `AccountView.swift`, string literals in `TutorialModel.swift`, `syncMessage` in `DailyAccountCoordinator.swift`, string assertions in `TutorialModelTests.swift` and `AccountTests.swift` | S0b commit | Returned; bounded repair pending | `/tmp/gridrace-stamped-s3-result.json`; full suite/build green; target captures incomplete |
| S4 Verification + A9 | controller with human | plan, evidence only; fixes go to the owning unit's files under a new packet | S1–S3 integrated | Not started | — |

Serialization: `project.pbxproj` only in S0a. After S0b, the controller alone
owns `DesignSystem.swift` and `BoardViews.swift`; workers return change requests
as stop conditions. Update `screen-flow.md` at each unit's integration commit for
the surfaces that shipped.

### S0a Mechanical split

Move types into the target files and update `project.pbxproj`; delete empty
files. Allowed edits: moves and access-level changes (`private` →
`fileprivate`/internal) required by the split. No behavior, layout, or string
change. Acceptance: full suite and clean Debug build pass; diff audit shows only
moves and access levels. Separate commit.

### S0b Foundation and contracts

Replace the `race*` color extension with design-doc roles (light, dark, D12
Increased Contrast set), add type roles (`.fontDesign(.serif)` display and
tiles, `.monospaced` figures), round-seal tile and keyboard states, ink
primary/outlined button styles, card surface, seal, notice card (solid = action,
dashed = informational), keyboard-slot container, and board sizing that fits the
available height (iPhone SE: about 54pt tiles beside a 175pt slot). Share leaf
components between tutorial and live (tile row, countdown numeral, opponent line,
notice); keep separate reveal containers because tutorial reveal timing belongs
to `TutorialModel` and live reveal timing to its view task. Remove the lane-edge
bar. Land D6 stubs with defaults so every unit compiles alone. Acceptance:
measured contrast table for every token pair in light, dark, and Increased
Contrast meeting D12 (body ≥4.5:1, large text and needed graphics ≥3:1); full
suite and build pass. Screens may look transitional until S1–S3.

### S1 Daily (High: hosts the Account sheet)

Home program schedule: header icons for Statistics, Account, Settings; rows 01
Daily, 02 Live (D10 states), 03 Practice; ink Play/Continue/Result stamp (S1
rewrites `DailyHomeStatus` presentation and its tests); mono stats line; Daily
storage-unavailable state as a notice. Daily game slim header (puzzle number,
help, row dots). Result card in the keyboard slot with focus landing on the
result seal first, then answer and rows, matching `screen-flow.md`. Statistics
with the not-solved bar. Account sheet per D3/D7. Remove the Home tagline, inline
Live controls (after S2 integrates), duplicate Help and Practice rows.
Acceptance: all six rows plus keyboard or result card fit without clipping on
iPhone SE at default type; every pre-existing destination stays reachable;
regression checks for sign-out and account deletion started from the sheet,
sign-out cleanup failure (Home shows Resolve), and guest-history import while the
sheet is open.

### S2 Live (High: recovery presentation)

Implement the state table through one pure presentation mapping in
`LiveMatchPresentation` (state → notice kind, title, body, allowed actions) and
unit-test every row against session fixtures. Extend the existing native render
test to every row at default and accessibility sizes and iPhone SE width. Entry
branch (D4), signed-out and expired-sign-in notices (D3, D7), lobby (D11; code
ticket, Copy, `ShareLink` with code text only), countdown, round with own
connection indicator and single opponent line, waiting card, D8 confirmations,
reveal with each board as its own accessibility container in order answer → own
rows → opponent rows → summary, standings, final with a tied variant, incomplete.
1/3/5 segmented control falls back to a menu at accessibility sizes. The local
two-client harness is optional (it draws no views); record it as not run unless
the controller grants a backend lease.

### S3 Supporting (High: account deletion surfaces)

Settings (Hard mode explainer under its toggle; lock note only while locked;
Version row), How to play (stamped rows and example; VoiceOver keeps the full
duplicate-letter explanation), Word list credits restyle with legal text
unchanged (return the user-visible "Release review still pending" string to the
controller instead of deleting it), Account states, sync status line strings,
import and conflict sheets (side-by-side boards from D6's `conflict`), Practice
intro and tutorial copy. Acceptance includes sign-out, deletion confirmation, and
conflict resolution regression checks.

### S4 Verification and A9

Devices: iPhone SE (3rd gen), iPhone 17 Pro, iPhone 17 Pro Max in portrait and
landscape; native iPad in portrait and landscape. Settings: light and dark;
default and AX5 Dynamic Type; Bold Text; Increased Contrast and High-contrast
feedback; grayscale; Reduce Motion. Required: no clipping or overlap;
keyboard-slot cards fit at default size and scroll at accessibility sizes;
VoiceOver labels and focus order (countdown, draft/error, terminal message,
answer, rows, summary) with VoiceOver actually running; Reduce Motion with the OS
setting actually on; hardware keyboard letters, delete, and return on Daily,
live, and tutorial; haptics optional and non-semantic; 44pt action hit regions and D15 letter-key regions measured.
Source tests and screenshots do not substitute for the OS-assisted checks; the
human performs them if tooling cannot reach the simulator. This closes Phase 4 A9.

## Live state table

"Current" actions are what the code offers today and must be preserved;
"Added" lists the only new actions (from decisions above).

| State (code) | Placement | Title | Body | Current actions | Added |
| --- | --- | --- | --- | --- | --- |
| Signed out, `.inactive`, no snapshot | screen notice | Sign in to race | Live races need a player name. Daily stays open without an account. | Open Account link | Sign in sheet (D3) |
| `.needsSignIn` | screen notice | Your sign-in expired | Your race is saved on this device. Go back to the race to try again; signing out removes it. | Open Account | Back to race (D7) |
| `.storageUnavailable` | screen notice | Couldn't open your saved race | Saved race data on this device couldn't be read or cleared. | Retry if `canRetryRecoveryStorage`; Discard saved race if `canDiscardRecovery`; Open Account | Discard confirmation (D8) |
| `.inactive`, no snapshot, signed in | entry screen | Live race | Host a race / Join a race | (Home today) Resume if `hasSavedMatch`; Create, disabled while `isCommandInFlight` or `pendingIntent != nil`; Join, disabled unless the code has six characters and no command is in flight | moved here (D4) |
| `.recovering`, no snapshot | full-screen info | Connecting to your race | Hang tight. This only takes a moment. | Home (toolbar) | — |
| other phase, no snapshot (incl. failed Join/Create) | screen notice | Race unavailable | Mapped error, else "Go back and try reopening your race." | Retry if `canRetry`; Discard saved request if `discardAction`; Open Account | Back to race entry (`leaveToHome()`, D7 pattern); Discard confirmation (D8) |
| Top error, round not playing, no saved-recovery decision | banner notice | Mapped error | — | Retry if `canRetry` | — |
| Saved Start unresolved (`hasPendingStart`, non-playing round) | bottom notice | Round didn't start yet | Retry starts the same round. | Retry saved start, disabled unless `canRetry` | — |
| Saved request decision (`pendingIntent` + requestConflict/rateLimited, non-playing round) | bottom notice | Your saved request needs a decision | Mapped error | Retry saved request (disabled unless `canRetry`); Discard if `discardAction` | Discard confirmation (D8) |
| Lobby, host, one player | lobby | Waiting for player two | Share the code to invite them. | (Start disabled today) | Copy; Share; Start hidden until two players (D11) |
| Lobby, host, two players | lobby | — | — | Start race, disabled unless `canStart && phase == .ready` | — |
| Lobby, guest | lobby info | Waiting for {host} | The host starts each round. | none | — |
| Lobby expired | lobby notice | This room closed | It expired before the race started. | Home (toolbar) | — |
| Countdown | countdown | Round N of M | Starts on the server clock. Leaving the app won't pause it. | Home (toolbar) | — |
| Countdown or round after a deletion (`terminalReason`) | info line | Your opponent left GridRace | Finish this round. It's the last one in this match. | none | — |
| Round: guess decision (`pendingIntent` + requestConflict/rateLimited) | keyboard slot, action | Your guess needs a decision | Mapped error | Retry saved request (disabled unless `canRetry`); Discard | Discard confirmation (D8) |
| Round: own terminal | keyboard slot, info | Solved in N / Out of guesses / Time's up / Round forfeited | Waiting for {opponent} | Retry when `.unavailable` (disabled unless `canRetry`); progress when `.recovering` | — |
| Round: guess sending (`pendingIntent` or command in flight) | keyboard slot, info | Sending your guess | Typing is locked until it's confirmed. | none | — |
| Round: connection recovering/unavailable | keyboard slot, info/action | Reconnecting / Connection lost | Your board is saved. Typing resumes when you're back. | Retry when `.unavailable` (disabled unless `canRetry`) | — |
| Round: local deadline passed (`isInputLocked`) | keyboard slot, info | Time's up | Getting the final result for this round. | none | — |
| Round: invalid or rejected word (`retainedError`) | inline above keyboard; keyboard stays | Mapped error | — | none; draft preserved | — |
| Reveal unavailable | screen info | Reveal on its way | The full reveal hasn't arrived yet. | Home (toolbar); top banner Retry if `canRetry` | — |
| Viewing a prior reveal | caption | Round K reveal | Current match: Round N of M. | revealed-round chips | — |
| Next round, host | standings | — | — | Start round N of M, disabled unless `phase == .ready && canStart`; Home | — |
| Next round, guest | standings info | Waiting for {host} | They'll start round N of M. | Home | — |
| Final | final | Winner seal or Tied seal | Final table | Home; revealed-round chips | — |
| Match incomplete | final | Match incomplete (ink seal) | Your opponent left GridRace after round N. The rounds you played are saved; round M won't be played. | Home; revealed-round chips | — |

S2 re-verifies each row against `LiveMatchFlowView`, `LiveRoundView`,
`LiveRevealView`, `LiveLobbyView`, and `LiveMatchSession` before editing and
returns any mismatch as a stop condition.

## Risk and verification

Overall High: S0a edits the Xcode project; S1–S3 re-present recovery, sign-out,
and deletion surfaces. Independent final review is required (one fresh read-only
reviewer on the integrated packet).

| Unit | Proof |
| --- | --- |
| S0a | Clean Debug build; full suite; moves/access-level-only diff audit; `project.pbxproj` reference review |
| S0b | Full suite; Debug build; measured contrast table; D6 stubs compile with defaults |
| S1 | Full suite; SE and 17 Pro screenshots of Home states and Daily play/result/stats in light and dark; focus order on result; S1 regression checks; share text unchanged (existing tests) |
| S2 | Per-row presentation-mapping tests; extended native render test; existing live view and session tests green |
| S3 | Full suite; screenshots of each screen and sheet in light and dark; VoiceOver text for the duplicate-letter example; S3 regression checks |
| S4 | Matrix above; findings routed to owning units; final independent review |

Commands come from the runbook canon with the frozen flags
(`-disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile
-skipPackageUpdates`). Each new derived-data path gets the runbook's frozen
resolve first. Provision missing simulators before S4.

## Orchestration

The controller kickoff packet is
[`2026-10-03-stamped-ui-refresh-kickoff.md`](2026-10-03-stamped-ui-refresh-kickoff.md);
volatile run state (leases, baselines, callback results) lives in the gitignored
`.codex/runs/stamped-ui-refresh/`. Controller runs the activation checkpoint, then S0a and S0b serially (each to one
worker or locally), auditing, proving, and committing each. Under D13, new work
sessions use `create_thread`, inherit user model settings, and receive direct human
authorization for one result callback to the controller chat after releasing leases.
The controller ends dispatch turns without waiting or polling. It then creates the
D9 worktrees and dispatches S1, S2, and S3 in parallel with the runbook's compact
worker packet and a lease per unit. It integrates in order S2, S1, S3, proving
each on the main checkout and committing per unit, then runs S4 and the final
review.

## Ledgers

### Decision log

| Date | ID | Decision |
| --- | --- | --- |
| 2026-10-03 | D1–D6 | Recorded at authoring. Human chose rescope activation and delegated D3/D4 to the recommended design, authorizing app rework needed to fit it. |
| 2026-10-03 | D7–D12 | Added from the adversarial plan review (below). |
| 2026-10-03 | Activation baseline | Human authorized latest HEAD `2d19d2c` instead of the kickoff-file commit. Rescope activation transfers A9 intact to S4. |
| 2026-10-03 | D13 workflow steering | Human replaced global engineering guidance with the shared develop/design/review/verify skills and instructed `create_thread` for new work sessions with one callback to this controller. Supersedes kickoff Ponytail enforcement and subagent dispatch. Accepted product scope, ownership, isolation, and no-polling boundaries remain. |
| 2026-10-03 | D14 worker settings | Human specifies `worker` = `gpt-6.1-sol` / medium and `worker_luna` = `gpt-5.6-luna` / xhigh for future implementation chats. S1/S2 use worker; S3 uses worker_luna. Current S0b Sol/high is explicitly permitted to finish unchanged. |

### Review findings

Adversarial read-only plan review, 2026-10-03 (Claude Code `reviewer`). All
findings traced against code and accepted. Targeted closure by the same reviewer:
23 closed, H2 and H4 partial (resolved by N1 and N2 below), three new findings
N1–N3, all fixed.

| ID | Sev | Finding | Disposition |
| --- | --- | --- | --- |
| H1 | High | Entry rule excluded pending intents, stranding a saved create behind Discard-only | Fixed: D4 entry = `.inactive && snapshot == nil`; Resume row on `hasSavedMatch` |
| H2 | High | `needsSignIn` merged with signed out; auto-dismissing sheet can't fix it | Fixed: D7 and separate table rows |
| H3 | High | Undeclared cross-unit seams (sign-in state, conflict payload, model/coordinator strings, `LiveCreateControls`, tokens in tests, tutorial strings, avatar) | Fixed: D6 stubs in S0b; boundaries name every seam |
| H4 | High | Parallel units in one checkout can't prove independently; S1-before-S2 commit breaks Live | Fixed: D9 worktrees, S2 → S1 → S3 integration |
| H5 | High | State-table actions didn't match code; missing rows; no Discard confirmation | Fixed: table rebuilt from code; D8 |
| H6 | High | Packet baseline would treat this plan's own uncommitted docs as unrelated | Fixed: docs committed before packet release; packet pins HEAD |
| M1 | Med | Packet claimed review before it happened | Fixed in packet |
| M2 | Med | Seven authorities still name the Active Phase 4 plan | Fixed: activation step 2 |
| M3 | Med | A9 transfer dropped hardware input; device matrix wrong | Fixed: S4 matrix |
| M4 | Med | Light secondary ink failed 4.5:1; Increased Contrast set unspecified | Fixed: D12 |
| M5 | Med | Result card below board changes focus order; reveal boards read across | Fixed: S1/S2 acceptance |
| M6 | Med | Home lost saved-race/resolve signal | Fixed: D10 |
| M7 | Med | S2 proof didn't test view gating; harness is ceremony | Fixed: pure mapping tests; harness optional |
| M8 | Med | S1/S3 tiers understated | Fixed: High with regression checks |
| N1 | Med | Closure: D3 auto-dismiss would close the D7 sheet at once; D7 copy implied sign-out keeps the race | Fixed: dismiss on false→true transition; D7 copy and actions |
| N2 | Low | Closure: S2-first merge could break the pre-S1 Home call to `LiveCreateControls` | Fixed: source-compatible until S1 merges (D9) |
| N3 | Low | Closure: false test-assertion snapshot claim; entry disabled states; signed-out current action; reveal Home; D12 rationale | Fixed in snapshot, table, D12 |
| L1–L11 | Low | Reveal consolidation risk, LiveMatchViews over-split, private-type moves, board height sizing, duplicate countdown placement, symbol name, AX segmented control, frozen resolve per path, closeout gaps, tutorial label, S1 role | Fixed in S0a/S0b/S2/S4, layout, role table, closeout, design doc. L10 adjusted: tutorial label now distinguishes practice from live races (design doc) |

### Verification record

Activation: clean tracked tree/empty index and six expected unrelated paths
verified; byte baseline captured. Docs-only diff and local path references inspected;
`git diff --check` passed; exactly one Active plan remains. Phase 4 reference
search resolved to Historical evidence, the completed activation procedure, or the
original kickoff instructions. No product write or product test in this checkpoint.

S0a: worker result `/tmp/gridrace-stamped-s0a-result.json`; full iOS exit0,
216 executed / 214 passed / two expected opt-in integration skips / zero failures;
clean Debug exit0. Both use the assigned simulator, derived-data path and frozen
package flags. Logs/results `/tmp/gridrace-stamped-s0a-tests.log`, `.xcresult`,
and `/tmp/gridrace-stamped-s0a-clean-debug.log`. No backend lease or harness run.
Controller checked all returned hashes, all 132 protected tracked bytes, six
unrelated hashes, unchanged HEAD and empty index. Independently compared all 52
declaration bodies against activation HEAD: only the six required access changes.
Complete project diff inspected, registrations and `plutil -lint` passed;
`git diff --check` passed. Exact-source runtime proof reused without redundant
reruns. Controller audit `/tmp/gridrace-stamped-s0a-controller-audit.json`.
S0a leases released, assigned simulator Shutdown; no owned process remains.

S0b returned via its single authorized chat callback after releasing leases.
Result `/tmp/gridrace-stamped-s0b-result.json`; final full suite exit0,
216 total / 214 passed / two expected opt-in skips / zero failures, and clean
Debug exit0 with frozen flags and exact lock. Native fixtures include 44 normal/
AX5 attachments at 393pt width, not SE or OS-assisted acceptance. AX5 screen
containers remain transitional and must be repaired by S1–S3 before S4.
Controller inspected shared leaves, D6 contracts and call-site changes, verified
all 12 returned source hashes, 132 protected tracked files, six unrelated files,
unchanged HEAD/empty index, and independently recomputed all 56 contrast pairs;
all required pairs pass. Normal and AX5 playing renders inspected. No source
finding established. Audit `/tmp/gridrace-stamped-s0b-controller-audit.json`;
contrast `/tmp/gridrace-stamped-s0b-contrast.json`; contracts
`/tmp/gridrace-stamped-s0b-contracts.json`. All owned processes stopped and the
assigned simulator is Shutdown. No backend harness or OS acceptance claimed.
The human approved the compact QWERTY exception (D15); S0b acceptance is complete.
Contrast minima: body 5.0511:1, bold letters/required graphics 3.0694:1.
Exact-source suite/build proof is reused; this approval changes docs, not product bytes.

S1 callback received; complete six-file diff inspected, returned source/patch and
72 screenshot hashes checked, 138 protected tracked hashes and six unrelated
hashes match, HEAD/index unchanged. Default SE Home, Hard Mode play and light/dark
result captures inspected; no established source finding. Full suite 219 total /
217 passed / two expected opt-in skips, Pro native render test and Debug build pass.
Account sheet proof is presentation reducer plus existing lifecycle coverage;
actual sheet interaction and OS focus remain outstanding. Controller audit:
`/tmp/gridrace-stamped-s1-controller-audit.json`. No integration before S2.

S3 callback received; complete five-file diff inspected, patch hash verified,
137 protected tracked hashes and six unrelated hashes match; HEAD/index unchanged.
Full suite 216 total / 214 passed / two expected opt-in skips and Debug build pass.
Required per-screen/per-sheet light/dark captures are missing; S3 acceptance is
incomplete. Controller audit `/tmp/gridrace-stamped-s3-controller-audit.json`.
Bounded S3 correction packet addresses accepted findings C3-1–C3-4 below; it
reuses the released isolated worktree, SE clone and pre-resolved build path.

| ID | Finding | Disposition |
| --- | --- | --- |
| C3-1 | Conflict cards require 412pt including padding; default SE cannot show both at once | Repair responsive side-by-side sizing within AccountView; AX can scroll |
| C3-2 | Successive-conflict focus generation was removed; new conflict boards lack accessibility containers | Restore single-owner heading focus per conflict and board/row grouping |
| C3-3 | Guest import remains an alert despite the accepted sheet direction | Use native sheet with unchanged callbacks and owner-private history copy |
| C3-4 | Practice board gets no remaining-height proposal; required default SE fit has no proof | Repair container height reservation in TutorialViews and obtain native fit evidence |
| C3-5 | S3 target screenshots are missing | Keep verification open; capture native fixtures or actual UI before S3 acceptance |

“Release review still pending” remains in credits pending controller adjudication;
legal text is preserved. No backend harness or actual OS acceptance claimed.

S2: callback result `/tmp/gridrace-stamped-s2-result.json` and exact three-file
binary patch/source hashes checked. Controller inspected the full product source,
changed tests, all 45 default and AX5 contact captures plus critical AX bottom
controls, and verified 141 protected tracked hashes and six unrelated hashes.
Fifteen pre-existing presentation helper bodies and the reveal timing/focus task
remain equivalent to S0b. No established source blocker. The exact patch is now
on main; full suite exit0, 217 total / 215 passed / two expected opt-in integration
skips / zero failures, with frozen flags and assigned SE/build path. Evidence:
`/tmp/gridrace-stamped-s2-controller-main.log`, `.xcresult`; audit
`/tmp/gridrace-stamped-s2-controller-audit.json`. Debug build evidence:
`/tmp/gridrace-stamped-s2-controller-build.log`. Worker final live suites had 73
passes; the main full run establishes final integrated bytes. Native fixture
renders remain separate from S4 OS acceptance. Backend harness not run.
`screen-flow.md` now describes shipped S2 surfaces while retaining the current
pre-S1 Home/Account composition.

S1 applied on main after S2 `be33aa1`, with all six product/test source hashes
matching the audited worker result. Combined full suite exit0, 220 total / 218
passed / two expected opt-in skips / zero failures, using frozen flags and its
assigned SE/build path. Evidence `/tmp/gridrace-stamped-s1-controller-main.log`,
`.xcresult` and Debug build `/tmp/gridrace-stamped-s1-controller-build.log`.
Worker SE/Pro screenshot evidence is reused for unchanged S1 source; combined
Live render fixtures, Account sheet reducer, cleanup/import and share regressions
passed on main. Actual Account sheet sign-in/sign-out/deletion/import interaction
and OS accessibility are still S4 gates. `screen-flow.md` now describes the
numbered Home program, Daily keyboard/result slot, chart and Account sheet.

S2 cloned simulator deleted after integration. App-managed worktree archive was
rejected with “This worktree is protected by a pinned task or workspace.” The
controller chat is pinned, so its S1/S2 managed worktree attachments are retained
until that protection is resolved; no manual deletion or pin change is inferred.
This is an outstanding cleanup item, not completed archival.

### Commit record

Activation docs checkpoint: `cf9d48d9f7fc11ff22dcddf4e6bb088b13744885`, from
authorized starting HEAD `2d19d2c`. S0a mechanical split:
`38b6ff1ca605477a8f44a1df5e44316cec7c9c11`. S0b foundation and contracts: `908aa9b932832d286e0582537b2b3a02ec0b4c99`.
S2 Live integration: `be33aa15c14718a7d96de02e5da11abe66c1ade6`.
S1 Daily/routing integration: this commit.

## Blockers and stop conditions

- No product write before the activation checkpoint commit.
- Stop and ask if any state-table row needs actions beyond "Current" plus
  "Added", if a design element cannot fit iPhone SE at default type, or if a
  change would touch rules, session/state machines, storage, sync logic, backend,
  or share text.

## Next action

S2 and S1 are integrated and proved in order. S3's bounded correction chat is
active; audit its cumulative patch and native screen/sheet evidence, then integrate
and prove S3 before S4. Managed worktree cleanup remains blocked by this chat's
pin protection. Controller chat is `01a103c6-10bd-7a30-acc2-68334f0cd33a` on
host `local`. End dispatch turns without waiting or polling.

## Closeout checklist

- [ ] All units checkpointed and committed, with evidence in the unit table
- [ ] S4 matrix and A9 evidence recorded
- [ ] Independent final review adjudicated
- [ ] `screen-flow.md` describes the shipped presentation (updated per unit)
- [ ] Design doc status set to Implemented; AGENTS.md pointer no longer says
      "not yet implemented"
- [ ] Kickoff packet deleted in the closeout commit; `.codex/runs/stamped-ui-refresh/`
      removed
- [ ] Status set to Historical
