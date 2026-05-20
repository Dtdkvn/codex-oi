---
name: codex-oi
description: |
  Codex CLI second-opinion bridge for Claude Code. Wraps both `codex exec`
  (prompt-driven) and `codex review` (diff-driven) under one workflow with
  shared project-context preamble, filesystem boundary, JSON stream parsing,
  and a structured findings table. Five modes:
    review <path>     — custom-prompt audit of file/folder
    plan <file.md>    — challenge a plan doc before coding
    audit             — full project sweep (high effort, cost-warned)
    closeout [target] — structured diff review (auto | local | branch | commit)
    recommit <ref>    — review a single landed commit
  Project-agnostic: auto-detects CLAUDE.md / AGENTS.md / .cursorrules / README.md
  and embeds them as context. Read-only. Never auto-applies findings.
  Trigger: "codex-oi", "/codex-oi", "second opinion", "ask codex", "codex review",
  "codex audit", "challenge plan".
allowed-tools:
  - Bash
  - Read
  - Glob
  - Grep
  - Write
---

# codex-oi — Codex Second-Opinion Bridge

A unified workflow that calls **OpenAI's Codex CLI** as a second opinion on your
code. Two engines, one experience:

| Engine | Used for | Output style |
|---|---|---|
| `codex exec` | review / plan / audit | Free-form, custom prompt with project context |
| `codex review` | closeout / recommit | Structured diff findings, built-in severity |

The skill shares one pipeline across both engines: pre-flight → context preamble
→ filesystem boundary → engine dispatch → stream parser → structured synthesis.

---

## Contract (read first, applies to every mode)

1. **Advisory only.** Never auto-apply Codex findings. User decides each one.
2. **Verify every finding.** Read the real code path before agreeing or fixing.
3. **Reject speculation.** Unrealistic edges, broad rewrites, "could theoretically"
   findings → reject with a one-line reason.
4. **Right-sized fixes.** Smallest change at the correct ownership boundary.
   No drive-by refactors.
5. **Iterate until clean.** If a fix is applied, rerun the relevant mode. Stop
   only when the helper exits 0 with no actionable findings.
6. **Never override the review model.** On capacity errors, retry the same
   command. Do not swap models.
7. **One clean run is the result.** Do not run an extra review just for prettier
   "clean" wording.
8. **No push to review.** Push only when the user explicitly asks.
9. **Read-only filesystem.** Codex runs with `-s read-only`. Never modify files
   from inside this skill.

---

## Stage 0 — Pre-flight (always run first)

```bash
codex --version 2>&1 | tail -1            # codex installed?
git rev-parse --show-toplevel 2>&1 | tail -1   # in a git repo?
PROJECT_NAME=$(basename "$(git rev-parse --show-toplevel 2>/dev/null)" 2>/dev/null)
echo "PROJECT: $PROJECT_NAME"
for f in CLAUDE.md AGENTS.md .cursorrules README.md; do
  [ -f "$f" ] && echo "CTX: $f ($(wc -l < "$f") lines)"
done
```

Failure modes:
- `codex` not in PATH → STOP, instruct user: `npm install -g @openai/codex`
- Bash sees a Windows `codex` shim but no `node` in that shell → STOP, tell the
  user to install Node/Codex inside that shell or use `scripts/codex-oi.ps1`
- Not in a git repo → STOP, instruct user to `cd` into one

---

## Stage 1 — Detect mode

Parse the user's input after `codex-oi` / `/codex-oi`:

| User input | Mode | Engine |
|---|---|---|
| `review <path> [focus]` | A — Review | `codex exec` |
| `plan <file.md>` | B — Plan | `codex exec` |
| `audit` | C — Audit | `codex exec --high` |
| `closeout` or `closeout auto` | D — Closeout (auto-target) | `codex review` |
| `closeout local` | D | `codex review --uncommitted` |
| `closeout branch [base]` | D | `codex review --base <base>` |
| `closeout commit <ref>` | D | `codex review --commit <ref>` |
| `recommit <ref>` | E — Recommit (alias) | `codex review --commit <ref>` |
| empty / ambiguous | — | Ask the user via `AskUserQuestion` |

For `closeout auto`, the helper picks:
1. dirty working tree → `--uncommitted`
2. open PR (via `gh pr view --json baseRefName`) → `--base origin/<base>`
3. else → `--base origin/main`

---

## Stage 2 — Build project-context preamble (every mode)

Priority order. Read the first file that exists. Embed ≤ 120 relevant lines.

1. **CLAUDE.md** — Claude Code project brief (most common)
2. **AGENTS.md** — generic AI-agent rules
3. **.cursorrules** — Cursor project rules
4. **README.md** — fallback

Build preamble template (kept short, ~30–60 lines):

```text
PROJECT CONTEXT — <PROJECT_NAME>
Branch: <branch> @ <short-sha>

### Project brief (from <source-file>)
<embedded top of file, trimmed>

### Your job
Be a brutally honest second opinion. Find bugs, drift from documented intent,
security holes, overcomplexity, missing edges at boundaries. Be terse. Use
priorities P1 (must fix) > P2 (should fix) > P3 (nice). No compliments.
No filler. Just findings + reasoning + file:line.
```

If no doc files found, use a generic preamble: `"No project docs found. Infer
intent from source. Same priority scheme."`

---

## Stage 3 — Filesystem boundary (prepended to every prompt)

```text
IMPORTANT: Stay focused on this project's source code (src/, lib/, scripts/,
tests/, app/, pkg/, internal/, cmd/, etc. — whatever this project uses).
Do NOT read or analyze:
  • .claude/ or any agent-config files
  • ~/.codex/ or other CLI-config dirs
  • node_modules, .venv, dist, build, target, .git
You are READ-ONLY. Do not modify any file.
```

---

## Stage 4 — Engine dispatch

### A / B / C → `codex exec`

Write the full prompt (boundary + preamble + task) to a temp file to avoid
shell-quoting issues, then run:

```bash
PROMPT_FILE=$(mktemp)
cat > "$PROMPT_FILE" << 'EOF'
<full prompt body>
EOF

REPO=$(git rev-parse --show-toplevel)
cat "$PROMPT_FILE" \
  | codex exec -C "$REPO" -s read-only \
      -c "model_reasoning_effort=\"$EFFORT\"" \
      --json 2>/dev/null \
  | python -u "$SKILL_DIR/scripts/stream-parser.py"

rm -f "$PROMPT_FILE"
```

Effort by mode:
- Review (A) → `medium`
- Plan (B) → `medium`
- Audit (C) → `high`

Use `timeout: 600000` (10 min) on the Bash call. For audit, recommend
`run_in_background: true` and stream progress.

### D / E → `codex review` (via helper)

```bash
scripts/codex-oi.sh closeout [auto|local|branch|commit <ref>]
```

The helper:
- chooses target automatically when `auto` (or no target given)
- runs `codex review --uncommitted | --base <base> | --commit <ref>`
- optionally runs tests in parallel via `--parallel-tests "<cmd>"`
- runs nested review in yolo/full-access mode by default (`--no-yolo` to opt out)
- prints a final "clean" line when the review exits 0 with no findings

---

## Stage 5 — Mode prompts (exec engine only)

### Mode A — Review
```text
TASK: Review the file/folder at: <path>
Focus: <user focus, or "general bugs + security + drift from project docs">

Find: bugs, security issues, anti-patterns, dead code, drift from any locked
decisions in the project docs, overcomplexity, missing error handling at
boundaries (network, subprocess, user input, DB).

Output format:
  P1/P2/P3 list with `path:line — issue (1 line) — fix (1 line)`.
  Group by severity. Include at least one observation even if all-clear.
```

### Mode B — Plan
1. Read the plan file fully (`Read` tool).
2. Grep the plan body for referenced source paths; list them for Codex to read.
3. Embed the plan verbatim:

```text
TASK: Challenge this plan BEFORE coding starts.

Find: logical gaps, unstated assumptions, missing error handling, overcomplex
designs, ordering/dependency issues, drift from documented intent, security
risks, missing rollback paths.

Also read these source files referenced in the plan:
<auto-listed paths>

THE PLAN:
---
<full plan content embedded verbatim>
---
```

### Mode C — Audit
**Cost warning first.** Full audit may use 50k–8M tokens. Print estimate, ask
GO/no-GO via `AskUserQuestion` before invoking.

```text
TASK: Full project audit. Sweep these axes:

1. SECURITY
   OWASP top 10, secrets in code, SQL injection, command injection,
   path traversal, subprocess argv safety, auth/authz gaps, secret leakage
   in logs.

2. ARCHITECTURE
   Cross-cutting concerns, coupling smells, DB consistency, race conditions,
   resource leaks, dead code, half-finished features.

3. DRIFT vs documented intent
   If project docs include locked decisions / non-negotiables / contracts,
   list every drift found, with file:line.

4. ANTI-PATTERNS
   Bypassed gates, missing migrations, hardcoded defaults that should be
   config, magic numbers, tests that assert nothing, swallowed exceptions.

Output format:

# AUDIT FINDINGS
## P1 — must fix before next ship
- [P1] path:line — issue (1 line) — fix (1 line)
## P2 — should fix this sprint
## P3 — nice to have
## SUMMARY
- Total findings, dominant theme, biggest risk class.

Aim for at least 5 findings. Be specific with file:line.
```

---

## Stage 6 — Present output

```text
═══════════════════════════════════════════════════════════
CODEX SAYS (<mode>):
═══════════════════════════════════════════════════════════
<full Codex output, verbatim — DO NOT truncate>
═══════════════════════════════════════════════════════════
Tokens: <N>
```

Followed by:

```text
── STRUCTURED FINDINGS ──

| # | Sev | File:Line | Issue | Verify? |
|---|-----|-----------|-------|---------|
| 1 | P1  | path:line | one-line summary | APPROVED / NEED VERIFY / REJECT |
| 2 | ... |

Aligned with documented intent? <yes / no — list drifts>

── ACTIONABLES ──
- [ ] P1 action 1 (owner: user)
- [ ] P1 action 2 (owner: developer)
- [ ] P2 action 3
```

Never auto-apply. Always stop here and let the user decide.

---

## Stage 7 — Iteration loop (closeout / recommit only)

After presenting findings:

- **0 accepted findings + helper exit 0** → report `CLEAN — no accepted/actionable findings.` and stop.
- **≥ 1 accepted finding** → instruct the user: *"Apply fixes manually, then
  re-run `codex-oi closeout` until clean."* Do not loop automatically; the
  user owns each fix.

Do not run an extra `codex review` solely to get nicer wording or a second
opinion on already-clean output.

---

## Stage 8 — Telemetry (opt-in)

Off by default. Enable with `CODEX_OI_TELEMETRY=1` in the environment.

```bash
if [ "${CODEX_OI_TELEMETRY:-0}" = "1" ]; then
  mkdir -p "$HOME/.codex-oi/logs"
  echo "{\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"project\":\"$PROJECT_NAME\",\"mode\":\"$MODE\",\"tokens\":\"$TOKENS\",\"exit\":\"$EXIT_CODE\"}" \
    >> "$HOME/.codex-oi/logs/usage.jsonl"
fi
```

Logged fields: timestamp, project name, mode, token count, helper exit code.
No source code, no prompt content, no findings.

---

## Installation

Place this directory at one of:
- `~/.claude/skills/codex-oi/` (Claude Code user-level)
- `<project>/.claude/skills/codex-oi/` (per-project override)

Run `./install.sh` (Unix/WSL/Git-Bash) or `.\install.ps1` (Windows) to symlink.

---

## Rules summary

- **Project-agnostic.** Always resolve repo via `git rev-parse --show-toplevel`.
  Never hardcode project names or paths.
- **Read-only.** Codex runs with `-s read-only`. No file modifications.
- **Verbatim output.** Don't truncate or summarize inside the `CODEX SAYS`
  block. Synthesis goes *after*, never instead of.
- **Never auto-execute findings.** All actionables wait for user GO.
- **10-min timeout** max. Audit mode → use `run_in_background: true`.
- **Cost-aware.** Audit mode prints token estimate and asks GO before running.
- **Distraction guard.** If Codex output mentions `.claude/`, `~/.codex/`, or
  AI-config files, warn the user and suggest retrying with sharper scope.

---

## Examples

### Review a single file
```text
codex-oi review src/services/login.py "auth flow + retry logic"
```

### Challenge a plan doc
```text
codex-oi plan docs/feature-x-plan.md
```

### Full audit (cost-warned)
```text
codex-oi audit
```

### Closeout — auto target detection
```text
codex-oi closeout
```

### Closeout — explicit local diff
```text
codex-oi closeout local
```

### Closeout — branch diff vs PR base
```text
codex-oi closeout branch
```

### Recommit — review a landed commit
```text
codex-oi recommit a1b2c3d
```
