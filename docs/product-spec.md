# GridRace Product Specification

GridRace is a temporary codename for a private, synchronous word race. This
document defines the product scope. [`game-rules.md`](game-rules.md) owns exact
rules, [`screen-flow.md`](screen-flow.md) owns navigation and reveal presentation,
and [`architecture.md`](architecture.md) owns system boundaries.

## Product promise

Blind Race lets a small invited group solve the same five-letter answer at the
same time without leaking anyone else's clues during play. Opponent progress
creates pressure; the shared reveal creates the social payoff.

The visual identity must be original. GridRace must not use “Wordle” as its name
or inspiration, a `-dle` derivative, that product's icon or typography, or a
near-identical green/yellow/gray tile system. Tile meaning never depends on
color alone.

## Blind Race MVP

The production MVP includes:

- private matches for 2–8 players;
- one, three, or five rounds, with three selected by default;
- one server-selected five-letter answer per round and at most six accepted
  guesses per player;
- a server-controlled three-second countdown and 180-second round deadline;
- private invite links and six-character room codes;
- a roster that closes when the first countdown begins, while allowing existing
  participants to reconnect;
- live identity, connectivity, accepted-guess count, coarse state, and a small
  progress animation without live opponent clues;
- shared round reveal, round and match placement, results, and rematch;
- Sign in with Apple, generated avatars, profile editing, report/block, and
  complete in-app account deletion before beta exit.

The MVP excludes public matchmaking, chat, contacts upload, photo upload,
friends, public rankings, monetization, custom words, asynchronous play,
spectators, generalized modes, and a game-plugin or generalized rules engine.
Opponent guesses, feedback, keyboard state, starting words, and exact solve time
remain private until reveal.

## Current behavior and phase order

Phase 0 establishes the product, rule, architecture, privacy, flow, word-pack,
and cross-runtime evaluator authorities. It adds no playable or networked
product.

Phase 1 now provides a native SwiftUI onboarding
tutorial with one deterministic local answer, two deterministic ghost
opponents, an accessible board and keyboard, an absolute-time countdown, a
private progress strip, and a minimal reveal. Its answer and ghost data live on
the device, so it demonstrates interaction only. It does not claim production
answer secrecy, server authority, authentication, multiplayer, persistence, or
network recovery.

Phase 2 establishes the local authoritative backend foundation: Supabase Auth and
profiles, private words and round secrets, grants and RLS, transactional commands,
deterministic development-word seeding, account deletion, and database/Edge tests.

Phase 3 is the first networked vertical slice: exactly two authenticated players,
one round, a server-selected answer, server-validated guesses, clue-free progress,
reconnect from canonical snapshots, deadline finalization, and shared reveal. It
must prove answer isolation, RLS denial, idempotent submission, server time, and
state convergence before broader match flow is added.

Later production phases expand the proved slice to the complete Blind Race MVP:
2–8 players, 1/3/5 rounds, invite links and room codes, full results and rematch,
history, notifications where useful, report/block moderation, broader retention, and
production identity/deletion hardening. Those are planned product responsibilities,
not Phase 3 behavior.

## Screen responsibilities

| Screen | Responsibility | Current phase scope |
| --- | --- | --- |
| Onboarding/tutorial | Explain Blind Race privacy, teach input and feedback, and let the player complete a local race before authentication. | Implemented locally |
| Home | Start create/join, reach the profile, sign out, and delete the account. | Phase 3 forces two players and one round |
| Create/join | Create the fixed live slice or enter a manual six-character room code. | Phase 3; broader configuration and links are later |
| Lobby | Show the private roster; only the creator starts, with no readiness state. | Phase 3 |
| Round | Show countdown, local board/keyboard, deadline, and clue-free opponent progress. | Phase 1 local tutorial and Phase 3 server-backed slice |
| Reveal | Disclose the answer and boards in deterministic row order, with a complete nonanimated path. | Phase 1 prototype and Phase 3 shared reveal |
| Results | Show exact round/match placement and summary. | Local comparison only |
| Rematch | Create a new private match from the prior group without mutating the completed result. | Future |
| History | Show the signed-in player's completed matches under the eventual retention policy. | Future |
| Profile | Manage display name, generated avatar, blocks, and account deletion. Email is never a public profile field. | Phase 2/3 identity and deletion; blocks later |

## Beta exit criteria

The production beta exits only when:

- the complete MVP flow works for 2–8 players and all supported round counts;
- server-owned answers, validation, feedback, timestamps, scoring, deadlines,
  and transitions are proved, including negative RLS and pre-reveal secrecy tests;
- retried commands are idempotent and clients recover from disconnect, dropped or
  reordered events, foregrounding, and deadline passage through canonical snapshots;
- Swift and TypeScript pass the same checked-in rule vectors and production word
  provenance and accepted-word policy are approved;
- VoiceOver, Dynamic Type, Reduce Motion, Increased Contrast, Bold Text, non-color
  tile meaning, usable targets, and optional haptics are verified on supported
  devices;
- private invites, Sign in with Apple, report/block, and complete in-app account
  deletion work end to end;
- privacy retention and deletion decisions are approved, secrets are separated by
  environment, and production logs contain neither raw answers nor raw guesses;
- current product, architecture, privacy, and operational documentation matches
  the released behavior.
