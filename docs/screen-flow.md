# GridRace Screen Flow

This document describes presentation and navigation. Exact game behavior lives in
[`game-rules.md`](game-rules.md). “Tutorial” means the documented on-device
practice behavior; live racing is the server-backed two-player flow with 1, 3, or 5 rounds. “Later” means the broader
production MVP.

## Flow map

The Daily and account routes are:

```text
Home: numbered Daily classic / Live race / Practice program
  -> Daily classic -> play or immutable result -> statistics/share
  -> Statistics (header)
  -> Account sheet (header) -> Sign in with Apple -> profile setup
                           -> sync/import/status, edit, sign out, confirmed deletion
  -> Settings (header) -> How to play or Word list credits
  -> Practice
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
Home → Live race (Open / Resume / Resolve)
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
presentation to entry without dismissing the Live route. The Account callback
presents the shared native Account sheet over Live.

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
marks. Daily, Live and supporting layouts now use the accepted stamped direction.

Default gameplay uses two columns when the available space is short and wide:
the complete six-row board on the left, slim header/opponent information and the
keyboard or notice/result slot on the right. This keeps gameplay visible without
default landscape scrolling. Compact boards use 1pt gaps while retaining 48pt
tiles; letter keys retain at least 32×48pt and actions 44pt targets. Columns stay
below navigation chrome; the Live navigation title is Live race. AX sizes retain
the readable vertical/horizontal scrolling presentation. Orientation is supported
without a lock. Software geometry proof and outstanding OS/tap acceptance are
recorded separately in the active plan.

### Daily Classic home and play

Home is a numbered program: 01 Daily classic, 02 Live race, 03 Practice.

During Daily play, an actionable error replaces the locked Hard Mode reminder
above the keyboard. Editing clears the error and restores the reminder; the
Hard Mode lock and guess validation remain in force.
Daily shows puzzle number and unplayed/in-progress/solved/failed status with a
Play, Continue, or Result stamp. Header icons open Statistics, Account, and
Settings. A monospaced played/solved/streak line follows the program; duplicate
Help/Practice rows and inline Live Create/Join controls are removed. Help remains
reachable from game headers and Settings; Practice appears once on Home.
The Live row shows Resolve for storage-unavailable recovery and opens Live;
Resume calls the existing saved-race recovery before opening Live; otherwise
Open leads to the Live entry screen. Authentication never gates Daily.
Daily storage failure shows an action notice with Retry and Open Account.

Play keeps the six-row board and keyboard primary. Invalid or incomplete words leave
the draft intact and announce a concise reason. Accepted rows reveal using GridRace's
symbol-plus-color semantics; Reduce Motion shows the same complete row immediately.
Hardware letters, delete, and return mirror the on-screen controls. Backgrounding
persists the draft and board; foregrounding rechecks the UTC puzzle day.

Daily play uses a slim puzzle/help/six-dot header above the six-row board.
The keyboard and result occupy the same reserved slot; the board receives the
space left after measuring the natural header and slot heights. At accessibility
sizes, the whole screen scrolls vertically and the shared board/keyboard scroll
horizontally. Completion shows the result seal, answer, streak context, next
puzzle time, Share and Stats. Semantic/focus order is error when present, then
seal, answer, rows and remaining controls. Reopening never reapplies statistics
or changes the immutable result or share bytes.

Statistics shows four monospaced figures and a Rows used chart for 1–6 solved
rows plus a separate outlined not-solved row. Today's bar is claret and has a
literal Today marker, including at accessibility sizes; the footer is removed.

### Account and synchronization

Account opens as a native NavigationStack sheet with Done over the current route.
Native Apple sign-in and Debug-only local test sign-in remain in the shared Account
view. A sheet opened while signed out dismisses only after a new false→true
sign-in transition, a loaded profile, completed account work and finished profile
setup. A sheet opened while already signed in (including expired authentication)
stays open; sign-out/deletion or import/conflict updates alone do not dismiss it.
Coordinator ownership of account cleanup, guest history and callbacks is unchanged.
First sign-in asks before adding guest history; skipping/importing does not delete
guest files. Sheet interaction and actual VoiceOver acceptance remain S4 gates.

The account screen uses a native grouped list on paper: generated avatar and name,
a 2–16 character Player name editor, Avatar shuffle, simple synced/pending/error
status with Retry, Sign out, and native confirmed account deletion. Idle says
Ready to sync; only a completed synchronization says Synced. At accessibility
sizes, editor actions and sync controls stack vertically and status text wraps
to its natural height. Guest-history
import opens a scrollable native sheet with Add to account and Not now; dismissing
it without a choice does not import or skip. Its copy states that results join
personal history and never count toward Live races. A divergent attempt opens a
Resolve attempt sheet with both six-row boards side by side at default type, then
Use synced attempt and Keep this device. At accessibility sizes the boards scroll
horizontally with full-size letters and symbols. Each board and row is a semantic
container; a newly presented or successive conflict focuses its heading once.
These choices never present an imported attempt as verified. Network
failure leaves the local game available. If sign-out or confirmed deletion cannot
durably clear live recovery, former-account Daily/account data stays hidden and Home
shows the Live row's “Resolve” action, which opens Live for retry or confirmed
discard.

### Onboarding and tutorial

Explain the promise before play: everyone solves the same answer, but opponent
letters and feedback stay private until reveal. Phase 1 then runs a real local
board against two deterministic ghosts without requiring authentication.
Clearly label this as an on-device tutorial, not a production secrecy or server
authority demonstration.

### Supporting screens and Practice

Settings uses native Play, Learn and About sections. Hard Mode shows Reuse every
revealed clue and its lock note only while locked. Learn opens How to play; About
opens Word list credits and shows Version. How to play uses three feedback stamp
rows and the APPLE versus GRAPE example, retaining the full duplicate-letter
explanation for VoiceOver. Example tiles scale with text; accessibility sizes
stack each explanation below its tile and let the duplicate-letter row scroll
horizontally. Credits preserve the legal text and the Release review
still pending notice.

Practice introduction identifies Alex and Sam as bots and explicitly distinguishes
local practice from server-backed Live races. Play uses the shared countdown,
six-row board, feedback keys and one compact line containing both bots' names,
accepted counts and coarse states; each bot's spoken summary retains its full
meaning. The timer sits in the slim header. Board sizing reserves the measured
status/error and keyboard heights so the error stays above the keys on SE portrait.
Accessibility sizes reflow the bot summaries and scroll the whole play screen vertically and
the board and keyboard horizontally. Reveal keeps the existing local sequence,
result summaries, replay and finish behavior.

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
