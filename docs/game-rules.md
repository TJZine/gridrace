# GridRace Game Rules

## Daily Classic

Daily Classic publishes one puzzle at 00:00 UTC. Schedule version 1 starts with
puzzle #1 on UTC day 20696 (2026-08-31); an answer's array position is its permanent
puzzle assignment. Published entries may only be appended, never reordered, removed,
or selected modulo the current array count.

The player has six accepted guesses. Format and dictionary rejection do not consume
a row. Feedback uses the same two-pass duplicate-letter evaluator defined below, and
keyboard evidence keeps the strongest observed state: correct, then present, then
absent. A correct sixth guess solves; an incorrect sixth guess fails.

Optional Hard Mode locks when the first guess is accepted. Every later guess must
keep correct letters in place, move present letters away from their revealed wrong
positions, and include at least the highest duplicate count previously proved by
correct or present evidence.

Progress includes the puzzle and schedule identity, draft, accepted words, feedback,
timestamps, Hard Mode choice, and completion. Completion is immutable. One structured
result per puzzle updates statistics idempotently. Solved consecutive puzzle days
extend a streak; a failed or missed puzzle day breaks the current streak. Shares show
only puzzle number, guess count or failure marker, and semantic feedback symbols—never
the answer or guessed letters.

This is the authority for Blind Race rules and cross-runtime behavior. Production
state is server-owned. Phase 1 executes the same pure rules against local tutorial
fixtures; Phase 2 establishes the backend authority; Phase 3 proves it with exactly
two players and one round.

## Match and round contract

- A private match has 2–8 rostered players and exactly 1, 3, or 5 rounds. The
  default selection is 3.
- Every round uses one five-letter answer and permits each player at most six
  accepted guesses.
- The match creator starts the first countdown when 2–8 players are rostered and
  starts each later countdown after the preceding reveal. There is no readiness
  state and reveal never advances automatically.
- The first countdown locks the roster. New players cannot join afterward, but a
  rostered identity may reconnect.
- Every countdown lasts three seconds. The round begins at the absolute server
  timestamp `startsAt` and ends 180 seconds later at `endsAt`.
- A submission is time-eligible only while
  `startsAt <= serverNow && serverNow < endsAt`. Equality with `endsAt` times out.
  `serverNow` is the database transaction's timestamp, never a device timestamp
  or the time at which the client began sending.
- The server chooses and protects each answer. An answer cannot repeat within one
  match.
- A round reveals when every rostered player is terminal or the deadline passes.
  One player's early solve never reveals the answer.

Private invite links and six-character room codes locate matches. They grant no
authority by themselves; the production backend still authenticates and
authorizes every read and command. Public matchmaking is not part of Blind Race.

## Production state machines and owners

### Match

```text
lobby -> inProgress -> completed
```

| Transition or action | Guard and effect | Named production owner |
| --- | --- | --- |
| Create `lobby` | Authenticated create command writes configuration and creator. | Edge Function validates the caller and input; transactional PostgreSQL behavior creates canonical state. |
| Join roster | Match is `lobby`, invitation is valid, and capacity remains. | Authenticated Edge Function command plus PostgreSQL constraints/RLS. |
| `lobby -> inProgress` | Creator starts; 2–8 players are rostered. Roster locks and round 1 enters `countdown` atomically. | Transactional PostgreSQL command behind the Edge Function. |
| Start later round | Prior round is `revealed`, another configured round is pending, and the caller is the creator. | Transactional PostgreSQL command. |
| `inProgress -> completed` | The final configured round becomes `revealed`; match totals and placements finalize atomically. | PostgreSQL round finalizer. |

There is no production cancellation, readiness, or automatic next-round state in
this contract. A lobby remains a lobby until the creator starts it. A nonfinal
reveal remains available until the creator starts the next countdown.

### Round

```text
pending -> countdown -> playing -> revealed
```

| Transition | Guard and effect | Named production owner |
| --- | --- | --- |
| `pending -> countdown` | Authorized creator command selects a nonrepeating private answer and records absolute `startsAt` and `endsAt`. | Transactional PostgreSQL command; private answer storage has no client grant. |
| `countdown -> playing` | Effective server time reaches `startsAt`; countdown never pauses for a client lifecycle event. | Canonical PostgreSQL snapshot interpretation of server timestamps. |
| `playing -> revealed` | All round players are terminal, or `serverNow >= endsAt`; active players become `timedOut`, scoring and placement finalize, and reveal data becomes readable atomically. | Idempotent PostgreSQL finalizer, reached from command paths and the later Cron safety path. |

Supabase Realtime only signals that clients should refresh. Canonical snapshots
own recovery on entry, reconnect, foregrounding, timeout, inconsistency, and an
uncertain command result. APNs delivers notifications only and owns no transition.

### Round player

```text
playing -> solved
        -> failed
        -> timedOut
        -> forfeited
```

- `solved`: an accepted guess is correct.
- `failed`: the sixth accepted guess is incorrect.
- `timedOut`: the round deadline passes while the player is still playing.
- `forfeited`: the player sends an explicit authenticated forfeit while playing.

These terminal states do not transition into one another. Connection is an
orthogonal advisory state: disconnecting never forfeits, changes placement, or
prevents a rostered player from recovering through a snapshot.

| Player transition | Named production owner |
| --- | --- |
| `playing -> solved` | The transactional PostgreSQL guess command evaluates and accepts the correct guess atomically behind an authenticated Edge Function. |
| `playing -> failed` | The same transactional PostgreSQL guess command accepts the sixth incorrect guess and marks failure atomically. |
| `playing -> timedOut` | The idempotent PostgreSQL round finalizer marks remaining players timed out, whether reached from a command path or Cron safety invocation. |
| `playing -> forfeited` | An authenticated Edge Function invokes a transactional PostgreSQL forfeit command for the caller's own active player record. |

At `startsAt`, each rostered player is playing. A submission during countdown,
at or after the deadline, or after the player becomes terminal is rejected
without consuming a row. The same transaction that observes an elapsed deadline
finalizes timeout before it can accept a guess.

## Input normalization and validation

Apply these steps in order to the submitted string:

1. If any scalar is outside ASCII, reject with `nonAscii` and produce no
   normalized guess.
2. Map ASCII `A`–`Z` to `a`–`z`. Do not trim whitespace or apply locale-sensitive
   or Unicode normalization.
3. If the normalized value is not exactly five ASCII characters, reject with
   `invalidLength`.
4. If any character is outside `a`–`z`, reject with `invalidCharacter`.
5. If the word is absent from the accepted-guess list, reject with `notAccepted`.

An invalid submission produces no feedback, does not consume an accepted row,
does not update the keyboard, and leaves player state unchanged. For Phase 1,
the accepted-guess list intentionally equals the 100 development answers in
[`development-en-US-v1.json`](../shared/word-packs/development-en-US-v1.json).
That small tutorial list is not the production dictionary policy.

For a valid submission, evaluate and append the row before deciding terminal
state. A correct guess always produces `solved`, including the sixth guess. Only
an incorrect sixth accepted guess produces `failed`.

## Feedback evaluation

Feedback values are:

| Value | Meaning |
| --- | --- |
| `0` | absent |
| `1` | present in another position |
| `2` | correct position |

Evaluate a normalized guess against the answer with the standard two-pass
frequency algorithm:

1. Initialize all five results to absent and count every answer letter.
2. First pass, left to right: mark exact-position matches correct and decrement
   the matching remaining count.
3. Second pass, left to right over non-correct positions: mark a letter present
   only when its remaining count is positive, then decrement that count.

For every letter, the number of correct plus present results can never exceed
that letter's count in the answer. Evaluation is pure: it has no UI, network,
clock, persistence, scoring, or state-transition responsibility.

## Board and keyboard behavior

The local board has five columns and six rows. It owns one editable draft,
accepted rows in submission order, and playing, solved, failed, or externally
timed-out locking. Accepted feedback cannot be edited. Invalid input keeps the
same draft row and accepted count.

Keyboard knowledge aggregates only accepted local rows. Strength is monotonic:
correct outranks present, present outranks absent, and repeated observations
never downgrade a letter. Board and keyboard treatments expose symbol, border,
or texture plus accessible text; color is supplementary.

## Ranking and scoring

### Round placement

Sort by these keys in order:

1. solved players before unsolved players;
2. fewer accepted guesses;
3. for solved players only, lower server-measured solve duration.

Solve duration is the authoritative timestamp of the accepted correct guess
minus `startsAt`; countdown time is excluded. Compare stored durations exactly,
without client display rounding. For unsolved players the third key is equal,
so players with the same accepted count tie regardless of whether they failed,
timed out, or forfeited. The literal comparator means fewer guesses ranks higher
among unsolved players too.

### Match placement

Sort by these keys in order:

1. more rounds solved;
2. more total efficiency points;
3. lower total server-measured solve duration across solved rounds.

Efficiency points are:

| Accepted guess that solves | Points |
| --- | --- |
| 1 | 6 |
| 2 | 5 |
| 3 | 4 |
| 4 | 3 |
| 5 | 2 |
| 6 | 1 |
| No solve | 0 |

Both rankings use competition placement. Exact comparator ties share a place
and leave the corresponding gap: `1, 1, 3`, not `1, 1, 2`.

## Live visibility and reveal

| Live opponent information | Hidden until reveal |
| --- | --- |
| Generated avatar and display name | Letters and submitted words |
| Accepted guess count | Correct/present/absent feedback |
| Connected/disconnected presentation | Keyboard state |
| Playing, solved, failed, timed-out, or forfeited state | Starting words |
| Small accepted-progress response | Exact solve time |

Production clients never receive the answer or opponent clue data before the
round is `revealed`. Logs and analytics never contain raw answers or guesses.

At reveal, show the answer, then order boards with the viewing player first and
remaining players in stable roster order. Reveal each board's accepted rows from
top to bottom in original guess order, one complete row at a time, then show
guesses used and comparison. Reduced Motion skips staging and exposes the same
complete state immediately in the same semantic order.

## Shared vector contract

Swift and TypeScript decode and execute the same checked-in file directly:
[`game-rules-v1.json`](../shared/test-vectors/game-rules-v1.json). No runtime owns
a checked-in copy, and no separate JSON Schema exists.

Its typed shape is:

```text
{
  formatVersion: 1,
  acceptedWordPackID: "development-en-US-v1",
  feedbackEncoding: { absent: 0, present: 1, correct: 2 },
  cases: [{
    id: string,
    covers: string[],
    answer: string,
    input: string,
    acceptedGuessesBefore: integer 0...5,
    expected: {
      normalizedGuess: string | null,
      validationError: null | "nonAscii" | "invalidLength" |
        "invalidCharacter" | "notAccepted",
      feedback: [integer, integer, integer, integer, integer] | null,
      acceptedGuessCount: integer 0...6,
      roundState: "playing" | "solved" | "failed"
    }
  }]
}
```

For `nonAscii`, `normalizedGuess` is null. For later validation errors it is the
ASCII-lowercased value. Rejected cases have null feedback, retain
`acceptedGuessesBefore`, and remain playing. Accepted cases increment the count
once and return five encoded feedback values.

Typed decoders must reject an unsupported version or pack ID, changed feedback
encoding, duplicate or empty case IDs, invalid field types, out-of-range counts,
invalid expected enums, malformed five-value feedback, or malformed lowercase
five-letter answers. The runners load the referenced word pack and reject a
vector answer absent from it. Extra object fields may be ignored for compatible
additions; required fields may not be defaulted.

The canonical cases cover all-correct, all-absent, repeated answer letters,
guess repeats exceeding answer frequency, exact matches consuming duplicates,
multiple duplicate interactions, uppercase normalization, invalid length,
non-ASCII input, a word outside the accepted pack, incorrect sixth-guess
failure, and a solve on the final guess.
