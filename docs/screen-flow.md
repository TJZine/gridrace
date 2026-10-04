# GridRace Screen Flow

This document describes presentation and navigation. Exact game behavior lives in
[`game-rules.md`](game-rules.md). “Tutorial” means the documented on-device
practice behavior; live racing is the server-backed two-player flow with 1, 3, or 5 rounds. “Later” means the broader
production MVP.

## Flow map

The Daily and account routes are:

```text
Home
  -> Daily Classic -> play or immutable result -> statistics/share
  -> Statistics
  -> Account -> Sign in with Apple -> profile setup -> sync/import/status
             -> profile edit, retry, sign out, or confirmed deletion
  -> Settings -> How to Play or Tutorial
```

The preserved tutorial flow is:

```text
Tutorial introduction
  -> local countdown
  -> local round
  -> local reveal and comparison
  -> replay tutorial or finish
```

Live presentation now provides these routes alongside Daily Classic:

```text
Home (inline Live controls until S1 integrates)
  -> Live entry -> Host (1/3/5 rounds) or six-character Join
                -> Account callback when signed out
  -> Create/Join -> Lobby -> Countdown -> Round -> Reveal/standings
                 -> creator Start next or final/incomplete result -> Home
  -> Resume saved race -> resolve original saved request -> current snapshot
  -> saved storage failure -> Retry or confirmed Discard
```

Live entry appears for an inactive session with no snapshot, including a saved
pending request. Resume remains available when saved data exists. Signed out,
the screen offers Sign in to race through the Account callback; expired sign-in
has its own notice with Back to race and Open account. Back to race resets the
presentation to entry without dismissing the Live route. The current Account
callback still opens the Account destination; S1 will host it as a sheet.

The match creator starts the first and later countdowns. There is no readiness
state. Once the first countdown starts, new players cannot join; an existing
roster member may reconnect.

## Screen behavior

The S0a mechanical split groups presentation by screen in `AppRouting.swift`,
`HomeView.swift`, `DailyGameViews.swift`, `StatisticsView.swift`,
`SettingsHelpViews.swift`, `TutorialViews.swift`, `LiveMatchViews.swift`, and
`LiveResultViews.swift`. Shared visual leaves live in `DesignSystem.swift` and
`BoardViews.swift`; Account remains in `AccountView.swift`. This checkpoint
preserves behavior. S0b now supplies paper/ink color roles, serif and monospaced
type, round-seal tiles, feedback keys, ink controls and shared notice/countdown/
opponent leaves. Correct uses claret fill and a check; present uses a double ring
and rotating arrows; absent uses an unfilled dimmed bold letter and minus. The
High-contrast feedback preference and Increased Contrast use the same strengthened
marks. Live layout is implemented by S2; Daily and supporting layouts remain
transitional until their units integrate.

### Daily Classic home and play

Home leads with today's Daily Classic status: unplayed, in progress, solved, or
failed. Its primary action is Play, Continue, or View result. A compact streak
summary and direct routes to statistics, settings, help, and tutorial follow without
empty destinations for future modes.

Play keeps the six-row board and keyboard primary. Invalid or incomplete words leave
the draft intact and announce a concise reason. Accepted rows reveal using GridRace's
symbol-plus-color semantics; Reduce Motion shows the same complete row immediately.
Hardware letters, delete, and return mirror the on-screen controls. Backgrounding
persists the draft and board; foregrounding rechecks the UTC puzzle day.

Completion reveals the answer, today's immutable result, share action, statistics,
and next-puzzle availability. Reopening never reapplies statistics or changes the result.

### Account and synchronization

Home always shows an account card. Signed out, it explains “Save and sync your
progress” without blocking play. Sign in uses the native Apple control; Debug builds
also expose a credential-free local Supabase test form. First sign-in loads the
owner-only profile and asks before adding existing guest history. Skipping or importing
does not delete guest files.

The account screen shows the generated avatar, 2–16 character player-name editor,
simple synced/pending/error status, retry, sign out, and confirmed deletion. A
divergent attempt explains that devices differ and offers “Use synced attempt” or
“Keep this device.” It never presents either imported attempt as verified. Network
failure leaves the local game available. If sign-out or confirmed deletion cannot
durably clear live recovery, former-account Daily/account data stays hidden and Home
replaces Create/Join/Resume with “Resolve saved live data,” which opens Live Race for
retry or discard.

### Onboarding and tutorial

Explain the promise before play: everyone solves the same answer, but opponent
letters and feedback stay private until reveal. Phase 1 then runs a real local
board against two deterministic ghosts without requiring authentication.
Clearly label this as an on-device tutorial, not a production secrecy or server
authority demonstration.

### Live entry and lobby

Live entry owns native 1/3/5-round Create selection (3 selected), a single native
six-character Join field, and Resume for saved recovery. The round selector uses
a menu at accessibility sizes. Create is disabled during an in-flight command or
pending intent; Join preserves its existing six-character/in-flight gate. Session
ownership of durable pointers and immutable request identities is unchanged.
Create durably replaces the previous selected match pointer before dispatch; a
failed save retains that pointer and blocks the request. Join retains the saved
pointer until its result is saved. An uncertain create remains resumable. A failed Join preserves its error and
saved pointer but offers no generic Retry that would reopen the old room.
Explicit Back to race and Resume select recovery instead.

Storage-unavailable, expired sign-in, failed commands, saved Start/request
decisions, and connection failures have distinct subject/title/body notices.
Solid borders denote action notices; dashed borders denote information. Controls
follow the active plan's state table and session gates. Every Discard invokes a
native confirmation dialog before removing saved local data; Cancel preserves it.
Retry saved Start uses its original session-owned target, including after
Home/Resume. No fresh intent substitutes for an unresolved request.

Lobby shows the room code in a seal, code-only Copy and Share, the two-seat roster,
this client's connection status, and creator-only Start. Start is hidden until
two players are present and retains all existing command/recovery/expiry gates.
The guest waits for the named host; ordinary creator absence waits without auto
advance. Expired rooms show a closed-room notice.
No readiness, public discovery, chat, opponent presence, or late joining is added.

The started round finishes after account deletion, then the match shows incomplete
with anonymized reveals and partial standings; unstarted rounds do not run.
Real independent-client verification of the underlying gameplay and its original
independent review are recorded in the
[Historical Phase 4 plan](plans/2026-10-02-phase-4-blind-race.md). The optional
two-client harness was not rerun for this presentation unit. OS-assisted
accessibility verification belongs to S4 of the
[Active Stamped UI Refresh plan](plans/2026-10-03-stamped-ui-refresh.md).

### Countdown and round

The countdown is a dedicated three-second state driven from an absolute start
timestamp. Backgrounding does not pause it; returning to the scene recomputes
the displayed state from current time.

Live rounds use a slim Round N of M header, timer and this client's connection
indicator, one opponent progress line, six-row board, and a reserved keyboard slot.
The slot changes to a sending, recovery, decision, deadline, or terminal waiting
notice without exposing the answer before canonical reveal. Invalid/rejected words
keep the draft and keyboard with an inline error. Default SE renders keep six rows
and the slot visible; accessibility type uses whole-screen vertical scrolling and
shared horizontal board/keyboard scrolling. Native renders do not prove actual
VoiceOver, hardware input, OS settings, or hit-region usability; S4 retains them.

The round keeps the local 5×6 board and keyboard primary. Surrounding text and
controls support Dynamic Type, while the fixed letter grid remains legible in
portrait and iPad compatibility presentation. Invalid guesses leave the draft
row available and do not advance the board.

The opponent strip shows, for each opponent:

- generated avatar and display name;
- accepted guess count;
- connected or disconnected presentation in the later MVP (deferred in this slice);
- playing, solved, failed, timed-out, or forfeited state;
- a small progress response when the accepted count increases.

Phase 1 ghosts remain connected and use only playing, solved, or failed. The live
slice shows all canonical terminal states and this client's own connection/recovery
status; it makes no claim about opponent connectivity. Preserve tutorial ghosts.

During play it never shows opponent letters or submitted words, feedback,
keyboard state, starting words, or exact solve time. An accessible summary is
equivalent to “Opponent Alex, three guesses submitted, still playing.” Reduced
Motion replaces progress movement with an immediate count/state update.

A solved/failed player waits for the canonical shared reveal; show their accepted
board and opponent count/state without exposing the answer. Invalid input preserves
the draft. A pending uncertain submission locks resubmission as a new intent and
explains recovery. Local deadline expiry locks input while fetching authoritative
state; network failure never manufactures a result. Provide explicit retry and Home.

Leaving for Home or signing out does not forfeit/cancel the match. Foreground Resume
first resolves any persisted create or guess using its original request identity,
then restores the accepted board through a snapshot. A create/join response arriving
after Home saves the resolved match pointer without restarting hidden recovery;
explicit Resume restarts subscriptions and canonical refresh. An expired lobby disables Start;
host deletion makes a guest's room unavailable, and guest deletion returns the host
to a one-seat lobby. Show those outcomes without an endless loading state.

### Reveal

In production, reveal begins only after the canonical round is revealed; one
player's early solve never exposes the answer. In Phase 1, a solved or failed
local board, or the tutorial deadline, completes the local fixture and starts
reveal. Ghost final rows appear only then. This tutorial shortcut makes no claim
about production round completion.

Presentation order is deterministic:

1. Show the answer.
2. Order boards with the viewing player first, then opponents in stable roster
   order.
3. Within each board, reveal accepted rows from top to bottom in original guess
   order, one complete five-tile row at a time.
4. Show guesses used, round placement, and the comparison summary after the rows.

Opponent rows are not sorted by result or rearranged for drama. Tile semantics
use text/symbol, border, and accessible labels in addition to an original
color-blind-safe palette.

With Reduce Motion enabled, skip staged transitions and present the answer, all
rows, and the same summary immediately in the same semantic and VoiceOver order.
Nothing is omitted, delayed behind animation, or communicated by color alone.

Live reveal uses an answer seal, then separate whole-board accessibility containers
in self/roster order, followed by summaries. Whole boards stack on narrow screens
and appear side by side when their readable rows fit. Prior-round chips select
preserved reveals without changing current commands or canonical standings.

### Results, rematch, history, and profile

Live shows round placements followed by canonical match standings using the
exact comparators in `game-rules.md`. A nonfinal reveal waits for creator Start
next; final and incomplete results offer Home and preserved prior reveals.
Standings display the supplied placement, rounds solved, efficiency points and
milliseconds without recalculating ranks. Winner and tied results use claret seals;
incomplete uses an ink seal. Incomplete standings remain partial. Rematch is
later work: it will create a new match rather than reopen or mutate the completed one.

Competitive history remains later; Daily statistics/history stay available. Phase 2/3
Profile manages display name, generated avatar,
sign out, and complete in-app deletion; blocked-player controls remain later.
Contacts, photos, chat, and visible email are outside the product.

## Accessibility flow requirements

- VoiceOver exposes each tile as letter plus meaning, such as “Letter A, correct
  position,” “Letter L, present in another position,” or “Letter E, not in the
  word.”
- Keyboard keys are buttons with meaningful labels and usable hit targets.
- Action controls have at least 44×44pt targets. The human approved a compact
  standard QWERTY exception for letter keys: about 32pt width on iPhone SE and
  at least 48pt height. S4 measures the actual regions and checks usability;
  no overlapping targets or alternate default layout is implied.
- Correct, present, and absent differ by more than color in both board and
  keyboard treatments.
- Increased Contrast and Bold Text strengthen rather than erase distinctions.
- A user-facing control can disable haptics; enabled feedback uses native APIs
  and never carries required meaning.
- Focus follows the visible state: countdown, draft/error, terminal message,
  answer, rows, then summary. The nonanimated reveal preserves this order.
