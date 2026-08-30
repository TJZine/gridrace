# AGENTS.md

Short entrypoint map for agents working in GridRace.

If a tracked plan is active, locate and read it before changing the repository:

```sh
rg -l '^Status: Active$' docs/plans
```

If more than one plan is active, stop and let the orchestrator resolve ownership.
Use [docs/ENGINEERING_RUNBOOK.md](docs/ENGINEERING_RUNBOOK.md) for workflow, risk,
verification, review, and handoff policy rather than duplicating it here.

Always preserve these product boundaries:

- Supabase is authoritative for answers, guess validation and feedback, timestamps,
  scoring, and match transitions.
- Authenticated clients cannot read round secrets or directly mutate game state.
- Swift and TypeScript evaluators consume the same versioned rule test vectors.
- Realtime events prompt UI updates; canonical snapshots own recovery and convergence.
- Do not simplify away RLS, secret handling, idempotency, accessibility, or safe
  production data practices.
- Build the focused live vertical slice before generalized modes or architecture.

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
- Engineering workflow and verification: [docs/ENGINEERING_RUNBOOK.md](docs/ENGINEERING_RUNBOOK.md)
- Durable architectural decisions: [docs/DECISIONS.md](docs/DECISIONS.md)
- Non-authoritative backlog candidates: [docs/TODO.md](docs/TODO.md)
- Tool-specific rule shim: [.agents/rules/general-guidelines.md](.agents/rules/general-guidelines.md)
