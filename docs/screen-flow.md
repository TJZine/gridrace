# GridRace Screen Flow

This document describes presentation and navigation. Exact game behavior lives in
[`game-rules.md`](game-rules.md). “Tutorial” means Phase 1 local behavior; “live
slice” means the Phase 3 server-backed two-player/one-round flow; “later” means the
broader production MVP.

## Flow map

The current app flow is:

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

The active Phase 3 plan adds these routes alongside Daily Classic:

```text
Home (Daily remains primary)
  -> Live create/join -> existing account flow if signed out
     -> Create -> Lobby -> Countdown -> Round -> Reveal -> Home
     -> Join   -> Lobby -> Countdown -> Round -> Reveal -> Home
  -> Resume saved live match -> canonical snapshot -> current live state
  -> Account -> identity, sign out, account deletion
```

The match creator starts the first and later countdowns. There is no readiness
state. Once the first countdown starts, new players cannot join; an existing
roster member may reconnect.

## Screen behavior

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
failure leaves the local game available.

### Onboarding and tutorial

Explain the promise before play: everyone solves the same answer, but opponent
letters and feedback stay private until reveal. Phase 1 then runs a real local
board against two deterministic ghosts without requiring authentication.
Clearly label this as an on-device tutorial, not a production secrecy or server
authority demonstration.

### Home, create/join, and lobby

Phase 3 adds fixed Create, manual-code Join and Resume alongside the existing Daily,
tutorial and Account routes; authentication never gates Daily.
Create always makes exactly two seats and one round; configuration and invite links
remain later. Lobby shows the private roster, room code, this client's connection/
recovery status,
and creator-only Start. It does not add readiness, public discovery, chat, or late
joining.

### Countdown and round

The countdown is a dedicated three-second state driven from an absolute start
timestamp. Backgrounding does not pause it; returning to the scene recomputes
the displayed state from current time.

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
restores the accepted board through a snapshot. An expired lobby disables Start;
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

### Results, rematch, history, and profile

Full results are future work and show round placements followed by match
placement using the exact comparators in `game-rules.md`. If another configured
round remains, reveal stays available until the creator starts its countdown.
After the final reveal, Results offers Rematch or Home. Rematch creates a new
match; it does not reopen or mutate the completed one.

Competitive history remains later; Daily statistics/history stay available. Phase 2/3
Profile manages display name, generated avatar,
sign out, and complete in-app deletion; blocked-player controls remain later.
Contacts, photos, chat, and visible email are outside the product.

## Accessibility flow requirements

- VoiceOver exposes each tile as letter plus meaning, such as “Letter A, correct
  position,” “Letter L, present in another position,” or “Letter E, not in the
  word.”
- Keyboard keys are buttons with meaningful labels and usable hit targets.
- Correct, present, and absent differ by more than color in both board and
  keyboard treatments.
- Increased Contrast and Bold Text strengthen rather than erase distinctions.
- A user-facing control can disable haptics; enabled feedback uses native APIs
  and never carries required meaning.
- Focus follows the visible state: countdown, draft/error, terminal message,
  answer, rows, then summary. The nonanimated reveal preserves this order.
