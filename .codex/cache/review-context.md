# GridRace review context

Source: inline reconnaissance from five stable repository authorities.
Cache status: Created.

## Stack and runtime

- Observed: Native Swift 6 / SwiftUI / Observation iOS app, deployment target iOS 18.
- Observed: Local Daily Classic plus deterministic local tutorial; optional Supabase-backed account sync exists behind non-view boundaries.

## Architecture and ownership

- Observed: SwiftUI views render state and send intents; models own state, tasks, and cancellation; pure rules remain UI-free.
- Observed: Supabase/server owns production answers, validation, feedback, timestamps, scoring, and transitions.
- Observed: Realtime is a refresh signal; canonical snapshots own recovery.

## Contracts and high-risk areas

- Observed: Never expose opponent words, feedback, keyboard state, starting words, or exact solve time before reveal.
- Observed: Tile meaning cannot depend on color alone; accessibility, Reduce Motion, Increased Contrast, Bold Text, and usable targets are requirements.
- Observed: Daily share text, game rules, account isolation, deletion, idempotency, RLS, and secret handling are protected contracts.
- Inferred: This UI-only review should focus on presentation-state correctness, focus/speech ownership, layout adaptability, and accidental model/contract drift.

## Verification canon

- Observed: Use scoped Git diffs and whitespace checks, full iOS tests, and clean Debug/Release simulator builds.
- Observed: SwiftUI changes also require manual Dynamic Type, VoiceOver, contrast/color-independence, and Reduce Motion inspection where applicable.

## Review roles

- Observed: Controller owns integration, tracking, staging, commits, and finding adjudication; bounded workers may not mutate Git.

## Uncertainties

- Unknown: No automated view/snapshot harness is documented.
- Unknown: Physical-device and formal VoiceOver/manual matrix evidence may remain unavailable.

## Evidence pointers

- `AGENTS.md`
- `docs/architecture.md`
- `docs/product-spec.md`
- `docs/screen-flow.md`
- `docs/ENGINEERING_RUNBOOK.md`
