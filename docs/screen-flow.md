# GridRace Screen Flow

This document describes presentation and navigation. Exact game behavior lives
in [`game-rules.md`](game-rules.md). “Local” means Phase 1 tutorial behavior;
“future” means a later server-backed phase.

## Flow map

Phase 1 implements only:

```text
Tutorial introduction
  -> local countdown
  -> local round
  -> local reveal and comparison
  -> replay tutorial or finish
```

The production MVP flow is future work:

```text
Onboarding / Sign in with Apple
  -> Home
     -> Create -> Lobby -> Countdown -> Round -> Reveal
     -> Join   -> Lobby -> Countdown -> Round -> Reveal
                                      -> next-round countdown, when applicable
                                      -> Results -> Rematch or Home
     -> History -> completed match detail
     -> Profile -> identity, blocks, account deletion
```

The match creator starts the first and later countdowns. There is no readiness
state. Once the first countdown starts, new players cannot join; an existing
roster member may reconnect.

## Screen behavior

### Onboarding and tutorial

Explain the promise before play: everyone solves the same answer, but opponent
letters and feedback stay private until reveal. Phase 1 then runs a real local
board against two deterministic ghosts without requiring authentication.
Clearly label this as an on-device tutorial, not a production secrecy or server
authority demonstration.

### Home, create/join, and lobby

These screens are future production work. Home routes to create, join, history,
and profile. Create selects 1, 3, or 5 rounds with 3 as the default. Join accepts
a private invite link or six-character room code. Lobby shows the private roster,
invite controls, connection state, and a creator-only Start action. It does not
add readiness, public discovery, chat, or late joining.

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
- connected or disconnected presentation;
- playing, solved, failed, timed-out, or forfeited state;
- a small progress response when the accepted count increases.

Phase 1 ghosts remain connected and use only playing, solved, or failed. The
broader connection and terminal presentations belong to the future production
flow.

During play it never shows opponent letters or submitted words, feedback,
keyboard state, starting words, or exact solve time. An accessible summary is
equivalent to “Opponent Alex, three guesses submitted, still playing.” Reduced
Motion replaces progress movement with an immediate count/state update.

### Reveal

In production, reveal begins only after the canonical round is revealed; one
player's early solve never exposes the answer. In Phase 1, a solved or failed
local board, or the tutorial deadline, completes the local fixture and starts
reveal. Ghost final rows appear only then. This tutorial shortcut makes no claim
about production round completion.

Presentation order is deterministic:

1. Show the answer and round summary.
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

History and Profile are also future work. History shows completed matches allowed
by the approved retention policy. Profile manages display name, generated avatar,
blocked players, and complete in-app account deletion. Contacts, photos, chat, and
visible email are outside the product.

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
