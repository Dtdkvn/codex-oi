# AGENTS.md — codex-oi

> Cross-tool agent rules file. Recognized by **Antigravity** (v1.20.3+),
> **Cursor**, **Codex CLI**, **Claude Code**, and any tool that adopts the
> [AGENTS.md convention](https://agents.md). Use this file to teach your
> coding agent when and how to invoke `codex-oi` for a second opinion.

This repo IS `codex-oi`. The note below is meant to be **copied into the
AGENTS.md of any project that wants the agent to use codex-oi as a
second-opinion engine.** For working on this repo itself, see
[CLAUDE.md](./CLAUDE.md) (if present) and [SKILL.md](./SKILL.md).

---

## Copy-paste block — drop into your project's `AGENTS.md`

```markdown
## Second-opinion reviews via codex-oi

This repo has `codex-oi` available — a Codex CLI bridge that gives a
second AI opinion on code without leaving the terminal. Use it
proactively in these situations:

1. **Before committing a non-trivial diff** — run a closeout check:
   ```bash
   ~/.codex-oi/scripts/codex-oi.sh closeout
   ```

2. **When the user asks for "a second opinion", "audit", or "review by
   another model"** — pick the matching mode:
   ```bash
   ~/.codex-oi/scripts/codex-oi.sh review <file-or-folder> "<focus>"
   ~/.codex-oi/scripts/codex-oi.sh plan <plan.md>
   ~/.codex-oi/scripts/codex-oi.sh audit       # full project sweep, cost-warned
   ```

3. **After landing a non-trivial commit** — retrospective:
   ```bash
   ~/.codex-oi/scripts/codex-oi.sh recommit HEAD
   ```

Treat the output as **advisory only**. Verify every finding against the
real code path. Reject speculative or out-of-scope claims with a
one-line reason. Do not auto-apply fixes.

Windows-native (no WSL): use `scripts\codex-oi.ps1` with the same modes.
```

---

## What `codex-oi` does

Wraps OpenAI's [Codex CLI](https://github.com/openai/codex) into a
unified workflow with:

- **Project-context preamble** auto-built from `AGENTS.md` / `CLAUDE.md`
  / `.cursorrules` / `README.md` (priority in that order — so this very
  file becomes Codex's context when you invoke it inside a project)
- **Filesystem boundary** that keeps Codex inside source dirs
- **Structured findings** table (severity / file:line / fix)
- **Iteration contract** — never auto-applies; loops until clean

Five modes: `review`, `plan`, `audit`, `closeout`, `recommit`. Full docs
in [SKILL.md](./SKILL.md) and [README.md](./README.md).

---

## Tool-specific notes

### Antigravity (v1.20.3+)
This `AGENTS.md` is auto-loaded at project root. Antigravity also
supports custom slash commands via `.agents/workflows/*.md` — you can
register `/second-opinion` as a slash command that runs codex-oi.
Sample workflow file:

```markdown
---
name: /second-opinion
description: Run codex-oi for a second AI opinion on the current diff
---

Run `bash ~/.codex-oi/scripts/codex-oi.sh closeout` and surface any
accepted findings to the user. Do not auto-apply fixes.
```

### Cursor
This `AGENTS.md` is read alongside `.cursorrules`. If your project uses
`.cursorrules`, add a short pointer there: `"For second opinions, see
AGENTS.md > Second-opinion reviews via codex-oi"`.

### Codex CLI (when used standalone, not as second opinion)
Codex itself reads `AGENTS.md`. If a Codex session is the primary agent
and you want it to invoke `codex-oi` against itself, the block above
still works — Codex will shell out to the helper.

### Claude Code
Claude Code's primary skill discovery is `SKILL.md`, not `AGENTS.md`,
but Claude Code also reads `AGENTS.md` for general project rules. The
copy-paste block above gives Claude Code the same trigger guidance the
skill provides, useful when the user hasn't installed the codex-oi
skill globally.

### Gemini CLI
Gemini reads `~/.gemini/GEMINI.md` (global) and `GEMINI.md` (project).
Antigravity uses the same global path, so be aware of conflicts (see
[google-gemini/gemini-cli#16058](https://github.com/google-gemini/gemini-cli/issues/16058)).
For per-project: copy the block above into your project's `GEMINI.md`.

### Aider
See [CONVENTIONS.md](./CONVENTIONS.md) — Aider reads that file when
present.

### Continue.dev
Continue doesn't have an `AGENTS.md`-style auto-discovery; add the
trigger guidance into your `.continue/config.json` system prompt or
`rules` field.

---

## Why this exists

Different AI agent tools have different file-discovery formats — Claude
Code uses `SKILL.md`, Cursor uses `.cursorrules`, Continue uses
`.continue/config.json`, Aider uses `CONVENTIONS.md`, etc. `AGENTS.md`
is a recent cross-tool standard adopted by Antigravity (Google),
Cursor, Codex CLI, and a growing list of agentic coding tools. By
maintaining one `AGENTS.md` per project, you teach all compatible
agents about `codex-oi` simultaneously without per-tool duplication.
