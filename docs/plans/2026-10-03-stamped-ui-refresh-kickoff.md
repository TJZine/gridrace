# GridRace stamped UI refresh — controller kickoff

Fresh primary controller (Codex, repository-configured roles in
`.codex/agents`). Work in the shared local checkout
`/Users/tristan/Software/gridrace`, branch `dev/classic-mode`. Expected HEAD is
the commit that last touched this file
(`git log -1 --format=%H -- docs/plans/2026-10-03-stamped-ui-refresh-kickoff.md`).
Stop and report if HEAD differs. This packet starts the workflow; the repository plan is the authority
once read.

## Authority and human authorizations (2026-10-03)

The human, in a Claude Code design session:

- accepted the stamped scorecard direction and every surface design in
  `docs/design-direction.md`, plus the `docs/DECISIONS.md` entry of 2026-10-03;
- chose the **rescope** activation: Phase 4's A9 OS-assisted accessibility proof
  (including hardware keyboard input and haptic preference) moves to S4 of
  `docs/plans/2026-10-03-stamped-ui-refresh.md`, Phase 4 closes as Historical
  with that transfer recorded, and the stamped plan becomes Active;
- delegated D3/D4 to the recommended design and authorized reworking app
  presentation and routing needed to fit it, within the plan's non-goals;
- required an adversarial review of the plan and this packet before commit. It
  ran on 2026-10-03; findings and dispositions are in the plan's review ledger
  (H1–H6, M1–M8, L1–L11, all accepted and fixed, D7–D12 added).

No further design or scope approval is needed for work inside the design doc and
plan. The plan's stop conditions still return to the human.

Read before acting: `AGENTS.md`, `docs/ENGINEERING_RUNBOOK.md`,
`docs/design-direction.md`, `docs/plans/2026-10-03-stamped-ui-refresh.md`, the
Active Phase 4 plan, `docs/NOW.md`, `docs/screen-flow.md`, `docs/game-rules.md`,
and `docs/DECISIONS.md`. Apply Ponytail full mode with the repository's
preferences and the interface-design skill within the accepted direction only.

## Step 0 — rescope activation (controller, docs only)

1. Verify the expected HEAD, an empty index, and a clean tracked tree. Capture
   `.codex/runs/stamped-ui-refresh/unrelated-baseline.json` (path → SHA-256) for the
   untracked paths present at kickoff. Expected set: `.DS_Store`, `docs/.DS_Store`,
   every file under the `.codex/cache/` directory,
   `docs/plans/GridRace-dictionary-finalize-and-integrate.md`, and
   `docs/plans/gridrace-corpus-independent-checks.json`. Report any other untracked
   path before continuing. Never stage, reset, stash, or overwrite these.
2. Perform the plan's activation checkpoint exactly as written (Phase 4 transfer
   and Historical status; repoint all listed authorities; stamped plan Active with
   this controller as owner and a refreshed snapshot).
3. Workflow/docs proof: `git diff --check`, every referenced path exists, exactly
   one `Status: Active` plan, `rg -n "Active Phase 4|phase-4-blind-race" docs
   AGENTS.md` resolved. One conventional docs commit. No product write before it.

## Units and dispatch

Follow the plan's work-unit table, write boundaries, and decisions exactly.

- **S0a** then **S0b**, serial, each to one fresh `worker` or run locally. Audit
  the full diff, run the unit's proof, commit, then continue. S0a is the only unit
  that may edit `ios/GridRace.xcodeproj/project.pbxproj`. S0b lands the D6
  contract stubs with defaults so later units compile independently.
- **S1** (`worker`), **S2** (`worker`), **S3** (`worker_luna`), in parallel after
  the S0b commit, isolated per D9: the controller creates one Git worktree per unit
  from the S0b commit, clones a simulator and assigns a derived-data path per unit,
  and runs the runbook's frozen package resolve for each path before dispatch.
  Workers write only inside their boundary in their own worktree and never mutate
  Git. After S0b the controller alone owns `DesignSystem.swift` and
  `BoardViews.swift`; workers return change requests.
- **Integration:** apply returned diffs to the main checkout in order S2, S1, S3,
  proving and committing each there. S1's removal of Home's inline Live controls
  never lands before S2's entry branch. Update `screen-flow.md` per unit for the
  surfaces that shipped. Remove each worktree and cloned simulator after its unit
  integrates.
- **S4:** controller with the human for OS-assisted checks; findings go back to
  the owning unit's files under a new bounded packet.
- **Final review:** one fresh `reviewer` on the integrated diff, proof, and risk
  packet; adjudicate, repair accepted findings with targeted closure, no recursive
  review.

Each dispatch uses the runbook's compact worker packet plus a lease file in
`.codex/runs/stamped-ui-refresh/` (gitignored run state: leases, baselines,
callback results, run memory) recording HEAD, worktree path, write paths with initial hashes,
protected tracked bytes, the unrelated baseline, initial status, and the process
lease (that unit's cloned simulator and derived-data path). Workers: no files
outside their boundary, no new dependencies, no backend/database/reset/remote
work. Artifacts go only under `/tmp/gridrace-stamped-<unit>-*`. Every
`xcodebuild` uses the frozen flags (`-disableAutomaticPackageResolution
-onlyUsePackageVersionsFromResolvedFile -skipPackageUpdates`). The two-client
harness is optional for S2 and needs an explicit backend lease; otherwise record
it as not run.

## Callbacks

Each worker and the reviewer sends exactly one callback to this controller after
releasing all file and process leases, including when blocked or making no
change, with a self-contained result: RESULT | FILES CHANGED | PROOF |
ASSUMPTIONS | BLOCKERS. No writes after the callback. The controller ends each
dispatch turn without polling.

## Stop and ask the human

- Any live state needing actions beyond the plan table's "Current" plus "Added".
- Any design element that cannot fit iPhone SE at default type.
- Any change reaching rules, session/state machines, storage, sync logic,
  backend, API, share text, or `project.pbxproj` outside S0a.
- OS-assisted S4 checks that need human hands (VoiceOver, Reduce Motion,
  hardware keyboard, haptics).

## Done

All units committed with evidence, S4 and A9 evidence recorded, final review
adjudicated, `screen-flow.md` describes the shipped presentation, design doc
marked Implemented and the AGENTS.md pointer updated, plan Historical with its
closeout commit reported. The closeout commit deletes this kickoff file, and the
controller deletes `.codex/runs/stamped-ui-refresh/`.
