# Claude Code runtime map

Root `CLAUDE.md` imports `AGENTS.md` using `@AGENTS.md`. Read task-relevant
`.agents/project.md` sections for GridRace context; shared skills own procedures.

Project `planner`, `worker`, `worker_luna` and `reviewer` presets are restored in
`.claude/agents/` at the user's request. Their files own Claude model, effort and
tool settings; `.codex/config.toml` and `.codex/agents/` configure Codex only.
Choose roles for useful bounded work; they do not require a fixed workflow roster.

Personal shared skills live in `~/.claude/skills/`. Personal `code-reviewer`
and `code-investigator` in `~/.claude/agents/` use Read/Grep/Glob and the inherited
model. Supply these specialists source identity, diffs and command evidence;
they cannot run Git or verification commands. They remain available alongside
the project roles.

The project reviewer forbids file edits and Git/runtime mutation, including
through shell commands. Disabled editing tools alone do not establish a sandbox.
Inspect actual loaded roles, imports, settings and permissions; parsing does not
prove authenticated execution. This map adds no callback protocol or hook.
