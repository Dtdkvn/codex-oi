# Changelog

All notable changes to `codex-oi` follow [Keep a Changelog](https://keepachangelog.com/)
and [Semantic Versioning](https://semver.org/).

## [0.1.0] — initial release

### Added
- Five modes: `review`, `plan`, `audit`, `closeout`, `recommit`.
- Two engines unified under one workflow:
  - `codex exec` for prompt-driven modes (review / plan / audit).
  - `codex review` for diff-driven modes (closeout / recommit).
- Auto-detection of project context from `CLAUDE.md`, `AGENTS.md`,
  `.cursorrules`, or `README.md`.
- Filesystem boundary prepended to every prompt to keep Codex out of
  `.claude/`, `~/.codex/`, build artifacts, etc.
- JSON stream parser (`scripts/stream-parser.py`) that surfaces reasoning,
  agent messages, command runs, and token totals while dropping framing noise.
- Closeout auto-target detection:
  1. dirty tree → `--uncommitted`
  2. open PR → `--base origin/<PR-base>` via `gh pr view`
  3. else → `--base origin/main`
- Cost-aware audit mode (prints token/cost estimate, requires GO).
- Opt-in telemetry (`CODEX_OI_TELEMETRY=1` → `~/.codex-oi/logs/usage.jsonl`,
  fields: timestamp, project, mode, tokens, exit — never source/findings).
- Bash helper (`scripts/codex-oi.sh`) for Linux / macOS / WSL / Git-Bash.
- PowerShell helper (`scripts/codex-oi.ps1`) for native Windows — no WSL needed.
- Installers (`install.sh`, `install.ps1`) that symlink into
  `~/.claude/skills/codex-oi/` with copy fallback.
- Nine-point contract (advisory only / verify findings / reject speculation /
  right-sized fixes / iterate until clean / never override model / one clean
  run = done / no push to review / read-only filesystem).
- Examples directory with sample audit, closeout, and plan-challenge outputs.

### Inspiration
- Diff-review half adapted from [steipete/agent-scripts](https://github.com/steipete/agent-scripts)
  `codex-review` skill.
- Prompt-driven half adapted from a field-tested internal `call-codex` skill.
