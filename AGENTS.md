# AGENTS.md

Short entrypoint map for agents working in GridRace.

If a tracked plan is active, locate and read it before changing the repository:

```sh
rg -l '^Status: Active$' docs/plans
```

If multiple plans are active, the primary controller resolves ownership before
affected writes; workers return the conflict to the controller. Continue independent
read-only work.

Use [docs/ENGINEERING_RUNBOOK.md](docs/ENGINEERING_RUNBOOK.md) for workflow, risk,
verification, review, and handoff policy rather than duplicating it here.

Always preserve these product boundaries:

Server-authoritative gameplay and pre-reveal answer secrecy apply to live racing and
future verified competition. Daily Classic and the tutorial follow their documented
local behavior; imported Daily results remain owner-private personal history and
cannot become verified competitive results.

- Supabase is authoritative for answers, guess validation and feedback, timestamps,
  scoring, and match transitions.
- Authenticated clients cannot read round secrets or directly mutate game state.
- Swift and TypeScript evaluators consume the same versioned rule test vectors.
- Realtime events prompt UI updates; canonical snapshots own recovery and convergence.
- Do not simplify away RLS, secret handling, idempotency, accessibility, or safe
  production data practices.
- Follow the accepted Daily Classic scope. For live racing, prove the focused
  vertical slice before broader match flow or generalized architecture.

Coordination boundaries:

- The orchestrator owns shared contracts, the active plan, integration, staging, and
  commits.
- Bounded workers stay inside their assigned write paths and report evidence; they do
  not edit tracking state or mutate Git.
- Preserve unrelated user and agent changes in the shared worktree.
- Use only commands documented for surfaces that currently exist; the runbook owns
  verification selection.

Where to look next:

- Active execution state and evidence: `docs/plans/`
- Current product behavior and exact rules: [docs/product-spec.md](docs/product-spec.md)
  and [docs/game-rules.md](docs/game-rules.md)
- Current system, privacy, and presentation boundaries:
  [docs/architecture.md](docs/architecture.md),
  [docs/privacy-data-map.md](docs/privacy-data-map.md), and
  [docs/screen-flow.md](docs/screen-flow.md)
- Engineering workflow and verification: [docs/ENGINEERING_RUNBOOK.md](docs/ENGINEERING_RUNBOOK.md)
- Durable architectural decisions: [docs/DECISIONS.md](docs/DECISIONS.md)
- Non-authoritative backlog candidates: [docs/TODO.md](docs/TODO.md)
- Tool-specific rule shim: [.agents/rules/general-guidelines.md](.agents/rules/general-guidelines.md)
