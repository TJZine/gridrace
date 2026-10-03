# GridRace Design Direction

Status: Accepted direction, not implemented. The shipped app still uses the
2026-09-04 indigo/coral/teal tokens in `ios/GridRace/App/Views.swift`. Until an
implementation plan lands, [`screen-flow.md`](screen-flow.md) describes current
behavior; this file describes the target presentation.

Accepted by the human on 2026-10-03 after a simulator audit and rendered direction
comparisons. It supersedes the 2026-09-04 refresh's visual direction (lane-edge
tiles, indigo/coral/teal fills); that plan's accessibility and secrecy invariants
still apply.

## Why the refresh

The audit found problems the token tweak could not fix:

- Absent (the most frequent result) was the most saturated fill, so the board and
  keyboard were dominated by the least useful information.
- Indigo was simultaneously primary action, draft-row border, correct feedback,
  Enter/Delete keys, progress, and toggles; correct tiles read as buttons.
- The lane-edge bar was identical on every state and carried no meaning.
- Home behaved like a form (Daily banner plus inline Live Create/Join), with
  duplicate routes to Help and Practice and no clear Statistics entry.
- The tutorial race clipped the sixth board row under the keyboard on an
  iPhone 17 Pro because opponent cards took about 150pt.

## Direction: stamped scorecard

Intent: a printed race program on warm paper. Daily is a calm ritual; feedback
lands like a rubber stamp on a scorecard. Precise, warm, quietly competitive.

Every surface must be elegant, clean, and functional while keeping this style.
Two working rules follow:

- Facts are data, not captions. Show a count as a bar, a state as a seal, a time
  as a mono figure; do not explain it in a footer.
- State a rule where the decision happens, not as an ambient disclaimer. The
  "personal history, never ranked" rule lives on the guest-history prompt; the
  privacy note lives beside Sign in with Apple; Hard mode's lock appears only
  when it is locked.

### Color roles

Starting values; measure every pair during implementation.

| Role | Light | Dark | Notes |
| --- | --- | --- | --- |
| Page | `#F2ECDF` | `#171513` | warm paper / night paper |
| Card | `#FAF6EC` | `#211E1A` | |
| Ink | `#1B1A17` | `#EDE5D3` | primary text, primary action fill |
| Ink secondary | `#6B6352` | `#9C937F` | 5.0:1 on light page |
| Line | `#D8CFBC` | `#3A352D` | hairlines, empty-tile dashed ring |
| Correct fill | `#7A1F2B` | `#B8495A` | claret; label `#F7F0E2` / white |
| Present ring | `#7A1F2B` | `#E08592` | double ring, no fill |
| Absent letter | `#8F8670` | about `#7A7262` | letter on paper, no tile fill; ≥3:1 (Apple HIG bold-text minimum; letters stay bold) |

Increased Contrast and the High-contrast feedback setting share one set: absent
letter `#6B6352` / dark `#A39A86`, empty rings in ink secondary, present ring
3.5pt, correct unchanged. Empty dashed rings are decorative at default.

Rules:

- Claret is for marks only: tile/key feedback and non-interactive ceremonial
  stamps (room-code ticket, countdown numeral, finished/winner seals). Anything
  tappable, including stamp-styled actions like Play/Continue/Resume, is ink.
- Absent recedes: no fill, dimmed letter, minus symbol. It is not a gray tile.
- No green/yellow/gray tile system (standing original-identity invariant).
- Dark mode is a designed ink set, not an inversion.

### Typography

- Display, headings, and tile/key letters: serif (New York via
  `.fontDesign(.serif)`).
- Numbers, counts, puzzle numbers, small labels: monospaced (SF Mono via
  `.fontDesign(.monospaced)` / `.monospacedDigit()`).
- Wordmark: tracked serif caps `GRIDRACE`.
- All system fonts; no bundled font files. Text roles keep Dynamic Type.

### Tiles and keyboard

- Shape: round seal. Draft row: solid ink ring on card. Empty: dashed line ring.
- Correct: claret fill + check. Present: claret double ring + the existing rotating-arrows symbol
  (`GameRules.Feedback.symbolName` is unchanged).
  Absent: dimmed letter + minus, no tile.
- Keyboard keys mirror tile states (absent keys dim rather than fill).
- No lane-edge bar.
- Fallback shape, designated but not built: passport stamp (sharp rectangle with
  an inner rule). Add only if small-device or accessibility testing shows round
  tiles hurt legibility; trigger from Increased Contrast or a setting.
- Meaning never depends on color: symbol, ring/fill form, and accessibility label
  all carry it.

### Structure

- Home is a program schedule: numbered event rows (01 Daily classic, 02 Live
  race, 03 Practice), one line each with a mono status line. Today's action is a
  small stamp (Play / Continue / Result), not a banner. The Live row shows
  "Saved race" with Resume, or "Saved race needs attention" with Resolve, when
  applicable. Stats sit in a single mono footer line.
- Header icons route to Statistics, Account, and Settings. Help lives in Settings
  and the game header; Practice lives on Home only.
- Live Create (1/3/5 rounds) and Join move to the Live race screen, off Home.
- Gameplay screens are a slim header, the board, and the keyboard. Opponent
  progress is one compact line (name and accepted count in stable roster order) so
  all six rows fit above the keyboard on every supported device.

### Live race flow

Accepted 2026-10-03 from stamped mockups:

- Signed out, the Live race screen shows a "Sign in to race" notice whose Sign in
  action opens the existing Account flow as a sheet and returns to Live entry
  once signed in.
- Live race screen: optional saved-race Resume row on top, then "Host a race"
  (native 1/3/5 segmented control, 3 selected, Create room) and "Join a race"
  (one native six-character code field styled as stamp cells, Join).
- Lobby: room code as a claret double-ring ticket with Copy and Share. Share
  sends only the code text through the system share sheet; invite links and deep
  links stay later work. Two-seat numbered entry list, own connection status,
  while alone the host sees "Waiting for player two" with Copy and Share and no
  Start; Start appears once player two joins. Guest waiting line.
- Countdown: "Round N of M", one large claret stamped numeral with three marks.
- Live round: slim header with round label and mono timer; one opponent line
  ("Alex · 3/6 · playing"). Opponent connectivity stays out of this slice; only
  own connection status appears, as a small header indicator.
- After finishing: the keyboard area becomes a waiting card with an own-result
  seal (for example "Solved in 3") and "Waiting for Alex".
- Reveal: stamped answer row, then the viewer's board and the opponent's board
  side by side in reveal order, round place and rows used, solve times.
  Fill/ring/no-tile form keeps mini boards meaningful without glyphs. Each board
  is its own accessibility container; reading order stays answer → own rows →
  opponent rows → summary.
- Standings: mono classification table (position, player, solved, points, time),
  a one-line explanation of the ordering, revealed-round chips, host
  "Start round N of M", guest waiting line.
- Final: winner seal (a tied variant when places tie), final table, all reveal
  chips, Home.

### Notices (race control)

One pattern for live errors, recovery, expiry, and incomplete matches:

- Card on card surface: solid 1.5pt ink border when the player must act, dashed
  1pt ink border when it is informational and resolves by itself.
- Mono caption naming the subject (Account, Guess, Time, Room), serif title in
  plain language, one mono body line saying what is safe and what happens next.
- Actions are ink (filled primary, outlined secondary). Destructive actions such as
  Discard confirm through a native dialog with system destructive styling, never
  claret.
- In-round notices occupy the keyboard slot (about 175pt), so the board never
  moves; screen-level states center the card and keep Home reachable.
- Fit: at default text size a notice fits the keyboard slot on iPhone SE (to-scale
  check 2026-10-03). Keep body copy to two lines. At accessibility text sizes the
  card may grow, buttons stack, and the round view scrolls rather than truncating.
- Each state keeps its existing allowed actions (for example, a failed Join never
  offers the old room); the implementation plan carries a state → title, body,
  actions table.
- Match incomplete uses an ink seal (not claret) and shows no winner; anonymized
  players keep the server-provided label.

### Daily result and statistics

- The finished result replaces the keyboard slot, like the live waiting card and
  notices: own-result seal (claret "Solved in 3"; ink "Not solved" with "The
  answer was TRAIL"), a small lock mark, streak and next-puzzle countdown, Share
  (ink) and Stats (outlined). VoiceOver focus lands on the result seal first,
  then the answer and rows.
- Share text stays byte-for-byte unchanged (`DailyClassicShare`); only the sheet
  around it is restyled.
- Statistics: four mono figures (Played, Solved, Streak, Best) under an ink rule,
  then "Rows used" bars 1–6 plus a "—" not-solved bar (outlined). Today's bar is
  claret. No footer.
- Home Daily row moves through ink stamps Play → Continue → Result; after
  finishing its status line carries the result and next-puzzle countdown.

### Supporting screens

- Settings: native grouped list on paper. Play (Haptics, High-contrast feedback,
  Hard mode with "Reuse every revealed clue" under the toggle and "Locked until
  tomorrow's puzzle" only while locked), Learn (How to play), About (Word list
  credits, Version). Practice and the reset/Reduce Motion footer leave Settings.
- How to play: "Six guesses to find the word"; three stamp rows (right letter,
  right spot / in the word, wrong spot / not in the word); the APPLE vs GRAPE
  stamped example with one visible line while VoiceOver keeps the full two-pass
  explanation; footer fact "One puzzle a day, worldwide · new at 00:00 UTC".
- Word list credits: legal content unchanged, restyled as a colophon.
- Account signed out: "Keep your streak on every device", Sign in with Apple, and
  "Your email is never shown to other players." beside it. Debug local sign-in
  stays Debug-only.
- Account signed in: avatar, name, one-line sync status (Synced / Pending /
  Couldn't sync · Retry), Player name, Avatar shuffle, Sign out, Delete account
  (system destructive). Guest-history import and attempt conflict appear as sheets
  only when they apply; the conflict sheet shows both boards side by side.
- Practice intro: "Race two bots", "Alex and Sam are practice bots chasing the
  same word. You'll only see their progress until the reveal.", Start practice,
  and the required on-device label "Practice runs on this device. Live races use
  the server."

### Copy voice

Plain words, sentence case, short sentences. Say what happened, what is safe, and
what happens next. No system vocabulary (server snapshot, canonical, local,
bundled, request). Accepted replacements:

| Where | Current | Accepted |
| --- | --- | --- |
| Home tagline | One grid. One day. Make every row count. | Today's program · date |
| Home live row | Private two-player race · 1, 3, or 5 private server rounds | Live race · Create or join a room |
| Home live footnote | Create and Join open Account first… | removed |
| Home practice row | Practice race · Revisit the local tutorial | Practice · Race two bots |
| Account card | Save and sync your progress | Keep your streak on every device |
| Daily prompt | Enter any accepted five-letter word. | removed (errors still announce) |
| Settings footer | Daily Classic resets worldwide at 00:00 UTC… | removed (fact moves to Help and countdown) |
| Hard mode note | Hard Mode is locked after the first accepted guess until tomorrow. | Locked until tomorrow's puzzle (only when locked) |
| Help title | Reach the finish in six | Six guesses to find the word |
| Help tiles | The checkmark means R is exactly where it belongs. (etc.) | Right letter, right spot · In the word, wrong spot · Not in the word |
| Help duplicates | In APPLE against GRAPE, exact matches use up… | Answer GRAPE has one P, so only the first P is marked. (full text kept for VoiceOver) |
| Guest import | Your local results will be saved as personal history. They won't count as verified competitive results. | They join your personal history. Live races never count them. |
| Tutorial intro | This is an on-device practice race. Its answer and ghost moves are bundled… | Practice runs on this device. Live races use the server. |
| Tutorial header | Local tutorial · Clue-free opponent progress | Practice |
| Tutorial start | Start local race | Start practice |
| Live recovering | Recovering live match · Waiting for a canonical server snapshot. | Connecting to your race · Hang tight. This only takes a moment. (In round: Reconnecting · Your board is saved. Typing resumes when you're back.) |
| Live typing hint | Enter a five-letter word. The server validates every live guess. | removed |
| Live waiting | Your accepted board is locked. Waiting for the canonical shared reveal. | Solved in 3 · Waiting for Alex |
| Live timer end | The local timer ended. Only the server can finalize and reveal this round. | Time's up · Getting the final result for this round. |
| Live pending guess | New submission is locked until the saved request is resolved. | Sending your guess · Typing is locked until it's confirmed. (Needs a decision: Retry / Discard with confirmation) |
| Live countdown | The server clock controls the start. Backgrounding does not pause it. | Starts on the server clock. Leaving the app won't pause it. |
| Lobby | Start becomes available when the second player joins. | Waiting for player two (Start appears when they join) |
| Live deletion, in round | A player account was deleted. Finish this round; the match cannot continue afterward. | Your opponent left GridRace. Finish this round. It's the last one in this match. |
| Live deletion, results | A player account was deleted. Unstarted rounds cannot continue… | Your opponent left GridRace after round 2. The rounds you played are saved; round 3 won't be played. |

Remaining strings follow the same voice; the implementation plan carries the full
live state → title, body, actions table.

### Unchanged boundaries

Pre-reveal secrecy (no opponent letters, feedback, rank, or timing), tutorial
labeled as on-device practice, spoiler-safe share text, VoiceOver tile/key labels,
44pt targets, focus order, Reduce Motion parity, and Increased Contrast
strengthening all carry over unchanged from `screen-flow.md` and `game-rules.md`.

## Implementation

All surfaces are designed (2026-10-03). Code structure, slicing, and verification
live in [`plans/2026-10-03-stamped-ui-refresh.md`](plans/2026-10-03-stamped-ui-refresh.md),
now Active after the human-approved Phase 4 rescope. S4 owns the transferred
OS-assisted VoiceOver, Reduce Motion, hardware keyboard, haptic preference,
and hit-region proof, which runs once on the refreshed UI.
