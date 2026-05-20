# codex-oi

> **Universal second-opinion bridge for AI coding agents.**
> Five modes, pluggable engines, one workflow — let your coding agent
> (Claude Code, Cursor, Antigravity, Codex CLI, Aider, Gemini CLI,
> Continue.dev) ask a different AI for a sanity check without leaving
> the terminal.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
![Status: beta](https://img.shields.io/badge/status-beta-yellow)
![Platform: Bash + PowerShell](https://img.shields.io/badge/platform-Bash%20%2B%20PowerShell-blue)
![Engines: Codex + Gemini](https://img.shields.io/badge/engines-codex%20%2B%20gemini-blueviolet)

---

## What it does

`codex-oi` plugs into your existing AI coding agent and gives it a way
to ask a **different model** for a sanity check — without context-
switching or leaving the terminal.

**Default engine: OpenAI's [Codex CLI](https://github.com/openai/codex)**
because it has two purpose-built subcommands for this:

- **`codex exec`** — free-form prompt, great for custom audits / plan reviews
- **`codex review`** — structured diff findings, great for closeout before
  commit/ship

**Other engines** via `--engine` plugin system (currently shipped: `gemini`
— full list in [`scripts/engines/README.md`](./scripts/engines/README.md)).

`codex-oi` wraps it all with shared infrastructure:

- **Project-context preamble** — auto-detects `CLAUDE.md`, `AGENTS.md`,
  `.cursorrules`, or `README.md` and feeds Codex the right project conventions
- **Filesystem boundary** — keeps Codex from wandering into `.claude/`,
  `~/.codex/`, or other AI-config noise
- **JSON stream parser** — strips noisy framing, surfaces reasoning, agent
  messages, command runs, and token count
- **Structured findings table** — always renders a `| # | Sev | File:Line |
  Issue | Verify? |` table after raw Codex output
- **Cost-aware audit mode** — warns before high-token sweeps
- **Iteration contract** — never auto-applies findings; iterates until clean
- **Optional telemetry** — opt-in, off by default, no source ever leaves
  your machine

---

## Five modes

| Mode | Engine | When to use |
|---|---|---|
| `review <path>` | `codex exec` | Custom-prompt audit of a file or folder |
| `plan <file.md>` | `codex exec` | Challenge a plan document before coding |
| `audit` | `codex exec --high` | Full project sweep across security, arch, drift, anti-patterns |
| `closeout [target]` | `codex review` | Structured diff review before commit/ship. Target: `auto` (default), `local`, `branch`, `commit <ref>` |
| `recommit <ref>` | `codex review --commit` | Review a single landed commit |

`closeout auto` (the default) picks the right target:
1. Dirty working tree → `--uncommitted`
2. Open PR detected → `--base origin/<PR-base>`
3. Else → `--base origin/main`

---

## Install

### Prerequisites

- **Codex CLI** — `npm install -g @openai/codex`
- **Claude Code** — required if you want to use this as a skill;
  the helper script works standalone too
- **Git** — repo detection
- **Python 3** — JSON stream parser
- (optional) **`gh` CLI** — for PR base auto-detection
- (optional) **bash 4+** OR **Windows PowerShell 5.1+ / PowerShell 7+**

### Install as a Claude Code skill

```bash
git clone https://github.com/Dtdkvn/codex-oi.git ~/codex-oi
cd ~/codex-oi
./install.sh        # Unix / macOS / WSL / Git-Bash
# or
.\install.ps1       # Windows PowerShell
```

The installer symlinks the repo into `~/.claude/skills/codex-oi/`.

Then in Claude Code, just type:
```text
codex-oi audit
codex-oi review src/services/login.py
codex-oi closeout
```

### Use the helper standalone (no Claude Code)

```bash
# Linux / macOS / WSL / Git-Bash
./scripts/codex-oi.sh audit
./scripts/codex-oi.sh review src/services/login.py
./scripts/codex-oi.sh closeout

# Windows PowerShell
.\scripts\codex-oi.ps1 audit
.\scripts\codex-oi.ps1 review src\services\login.py
.\scripts\codex-oi.ps1 closeout
```

### Use from other agent CLIs

`codex-oi` works with any tool that can shell out. Copy-paste blocks
ready for each ecosystem live in:

| Tool | Discovery file | Copy block source |
|---|---|---|
| **Claude Code** | `~/.claude/skills/codex-oi/SKILL.md` | shipped with installer |
| **Antigravity** (v1.20.3+) | `AGENTS.md` at project root | [`AGENTS.md`](./AGENTS.md) |
| **Cursor** | `AGENTS.md` at project root | [`AGENTS.md`](./AGENTS.md) |
| **Codex CLI** | `AGENTS.md` at project root | [`AGENTS.md`](./AGENTS.md) |
| **Aider** | `CONVENTIONS.md` at project root | [`CONVENTIONS.md`](./CONVENTIONS.md) |
| **Gemini CLI** | `~/.gemini/GEMINI.md` (global) or project `GEMINI.md` | reuse [`AGENTS.md`](./AGENTS.md) block |
| **Continue.dev** | `.continue/config.json` → `systemMessage` | reuse [`AGENTS.md`](./AGENTS.md) block |

After installing `codex-oi`, drop the relevant block into your project
so the agent learns when to invoke it. The helpers themselves don't
care which tool calls them — `bash`, `pwsh`, or any subprocess
spawner works.

If you run the Bash helper from WSL or Git-Bash, install Node/Codex inside that
shell environment. If Codex is only installed in Windows PATH, prefer the
PowerShell helper.

---

## How it differs from raw `codex review`

| Feature | Raw `codex review` | **codex-oi** |
|---|---|---|
| Diff review | ✅ | ✅ (inherited) |
| Prompt-based audit / plan review | ❌ | ✅ |
| Project context preamble | ❌ | ✅ |
| Filesystem boundary | ❌ | ✅ |
| JSON stream parser | ❌ | ✅ |
| Native PowerShell helper | ❌ | ✅ |
| Cost estimate before audit | ❌ | ✅ |
| Telemetry (opt-in) | ❌ | ✅ |
| Iteration contract | partial | ✅ (full) |
| Parallel tests during review | ✅ | ✅ (inherited) |

---

## The contract

`codex-oi` enforces nine rules on every run:

1. **Advisory only** — never auto-apply Codex findings; user decides each
2. **Verify every finding** — read the real code path before fixing
3. **Reject speculation** — broad rewrites and "could theoretically" issues
   get a one-line rejection
4. **Right-sized fixes** — smallest change at the correct ownership boundary
5. **Iterate until clean** — rerun after each fix; stop only at exit 0 + no
   findings
6. **Never override the review model** — on capacity errors, retry, don't
   swap models
7. **One clean run = done** — no extra reviews for prettier wording
8. **No push to review** — push only when the user explicitly asks
9. **Read-only filesystem** — Codex always runs with `-s read-only`

See [SKILL.md](SKILL.md) for the full workflow.

---

## Examples

### Review a single file
```bash
./scripts/codex-oi.sh review src/services/login.py "auth flow + retry logic"
```

### Challenge a plan doc
```bash
./scripts/codex-oi.sh plan docs/feature-x-plan.md
```

### Full audit (will ask for GO first)
```bash
./scripts/codex-oi.sh audit
```

### Closeout — auto target detection
```bash
./scripts/codex-oi.sh closeout
```

### Closeout with parallel tests
```bash
./scripts/codex-oi.sh closeout --parallel-tests "pytest -x tests/"
```

### Recommit — review a landed commit
```bash
./scripts/codex-oi.sh recommit a1b2c3d
```

Sample outputs are in [`examples/`](examples/).

---

## Telemetry

Off by default. Enable by exporting:

```bash
export CODEX_OI_TELEMETRY=1
```

When enabled, `codex-oi` appends one JSON line per run to
`~/.codex-oi/logs/usage.jsonl`:

```json
{"ts":"2026-05-19T12:34:56Z","project":"my-app","mode":"audit","tokens":"482133","exit":"0"}
```

Logged: timestamp, project name, mode, token count, exit code.
**Never** logged: source code, prompt content, findings, file paths.

The file stays on your machine. There is no upload. Inspect or delete it
freely.

---

## Configuration

| Env var | Default | Meaning |
|---|---|---|
| `CODEX_OI_TELEMETRY` | `0` | Set `1` to enable usage logging |
| `CODEX_OI_BIN` | `codex` | Path to the Codex binary |
| `CODEX_OI_YOLO` | `1` | `1` = nested review uses full-access; `0` = sandbox prompts |
| `CODEX_OI_TIMEOUT` | `600` | Per-mode timeout in seconds |
| `CODEX_OI_OUTPUT` | (unset) | If set, also write Codex output to this file |

---

## Troubleshooting

**"codex: command not found"**
Install Codex: `npm install -g @openai/codex`

**"shell shim needs 'node' in this Bash environment"**
Your Bash session can see the `codex` shim, but not the Node runtime it needs.
Install Node/Codex inside that shell, or run `.\scripts\codex-oi.ps1` instead.

**"Not in a git repo"**
Run from inside a git repository. `codex-oi` resolves the repo root via
`git rev-parse --show-toplevel`.

**"Codex output mentions .claude/ or ~/.codex/"**
Codex got distracted. Rerun with a sharper scope:
`codex-oi review src/specific-file.py "narrow focus here"`

**"audit mode hangs"**
Audit can take 5–15 minutes and 50k–8M tokens. Increase
`CODEX_OI_TIMEOUT=1800` or run in the background.

**"closeout reports clean but I expected findings"**
A clean `--uncommitted` review only proves no local patch exists. For
committed work, use `codex-oi recommit <ref>` or `codex-oi closeout branch`.

---

## Roadmap

- [ ] `fix <finding-id>` mode — guided single-finding remediation
- [ ] GitHub Action wrapper for CI use
- [ ] `--diff-only` flag for review mode (skip whole-file rereads)
- [ ] Multi-engine compare (Codex + Claude side-by-side findings)

---

## License

MIT. See [LICENSE](LICENSE).

---

## Credits

- Workflow design inspired by [steipete/agent-scripts](https://github.com/steipete/agent-scripts)
  `codex-review` skill (diff-driven half) and field-tested `call-codex` skill
  (prompt-driven half).
- Built for [Claude Code](https://claude.com/claude-code) users who want a
  second opinion without leaving the terminal.
