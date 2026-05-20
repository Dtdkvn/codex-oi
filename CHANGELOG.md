# Changelog

All notable changes to `codex-oi` follow [Keep a Changelog](https://keepachangelog.com/)
and [Semantic Versioning](https://semver.org/).

## [0.2.0] — multi-tool + multi-engine — 2026-05-20

### Added
- **Cross-tool integration** so any compatible agent can discover and
  invoke codex-oi:
  - `AGENTS.md` — Antigravity (v1.20.3+), Cursor, Codex CLI, Claude Code
  - `CONVENTIONS.md` — Aider
  - README integration table for Gemini CLI (`GEMINI.md`) and
    Continue.dev (`.continue/config.json` system message)
- **Pluggable engine system** via `--engine` flag in the bash dispatcher:
  - `engines/gemini.sh` — Gemini CLI adapter (POC, requires
    `gemini auth login` OR `GEMINI_API_KEY`)
  - `engines/README.md` — adapter interface spec for adding new engines
    (~50–150 LoC per adapter)
  - Default engine `codex` path unchanged from v0.1.x — zero regression
    risk on the most-used path
- **TESTING.md** — verification checklist with 4 paths verified
  end-to-end (Claude Code → codex, Codex CLI discovery, Gemini CLI
  discovery, `codex-oi --engine gemini` full pipeline).

### Fixed
- **PowerShell `$ErrorActionPreference='Stop'` + nested .ps1 shim bug**:
  `Run-Exec` and `Run-Review` now scope `EAP='Continue'` around the
  Codex pipe. Without this, the npm-shipped `codex.ps1` shim's inner
  `& node ...` stderr banner ("Reading prompt from stdin...") was
  wrapped as a `RemoteException` that killed the pipe before Codex
  output reached the parser. `2>$null` does NOT suppress this — only
  scoped EAP does. Silent catch blocks also replaced with verbose ones
  so future similar bugs are visible.
- **PowerShell 5.1 compat for telemetry**: `Get-Date -AsUTC` (PS 7.1+
  only) replaced with `[DateTime]::UtcNow` so the telemetry path
  doesn't crash on stock Windows PowerShell when enabled.
- **Gemini headless trust check**: adapter passes `--skip-trust` so
  Gemini doesn't refuse to run in non-interactive scripts.

### Known TODOs (deferred deliberately)
- PowerShell mirror of `--engine` flag — bash landed first so the
  architecture was observable; ps1 still hardcodes the Codex engine.
- More engine adapters: Claude API (anthropic SDK), Antigravity (when
  it exposes a CLI), local LLM via ollama (OpenAI-compatible API).
- Manual IDE-based verification: Antigravity, Cursor, Continue.dev
  (see [TESTING.md](./TESTING.md) tests 4–7).

---

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
