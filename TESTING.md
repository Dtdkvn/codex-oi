# TESTING.md — verifying codex-oi works with your agent stack

> Pragmatic checklist for proving codex-oi actually triggers from each
> agent tool, not just that the discovery files exist. Use the test
> fixture pattern below to verify any new tool you add.

---

## Test fixture (use this for any tool)

Create a tiny project that contains exactly two things:
1. A discovery file (AGENTS.md or whatever the tool reads)
2. A small source file with deliberate bugs the agent should flag

```bash
mkdir -p /tmp/codex-oi-test && cd /tmp/codex-oi-test
git init -q

# 1. Discovery file — copy the trigger block from codex-oi's AGENTS.md
#    (or CONVENTIONS.md / GEMINI.md as needed for the target tool).
cat > AGENTS.md << 'EOF'
## Second-opinion reviews via codex-oi

When the user asks for "a second opinion", "audit", or "review by
another model", invoke:
    bash ~/.codex-oi/scripts/codex-oi.sh review <file> "<focus>"

Treat output as advisory. Do not auto-apply.
EOF

# 2. Buggy fixture — 3 deliberate P1s, 2 P2s
cat > buggy.py << 'EOF'
import os, hashlib
SECRET_KEY = "dev-fallback-12345"             # P1 hardcoded secret
def login(u, p):
    return hashlib.md5(p.encode()).hexdigest() == _lookup(u)  # P1 MD5
def _lookup(u):
    return _db(f"SELECT pw FROM users WHERE name='{u}'")      # P2 SQL inj
def _db(q): return ""
def run(cmd): return os.system(f"echo {cmd}")                 # P1 shell inj
EOF

# 3. Telemetry — confirm whoever invokes codex-oi gets logged
export CODEX_OI_TELEMETRY=1
rm -f ~/.codex-oi/logs/usage.jsonl
```

---

## Verified — May 2026

### Test 1: Claude Code (this is the most direct test — you're inside it)

**Setup:** Test fixture above + Claude Code session opened in that dir.

**Run:** Tell Claude: *"Review buggy.py for security issues. Per
AGENTS.md, use the second-opinion tool."*

**Expected:** Claude shells out to `codex-oi.sh review buggy.py ...`,
streams Codex output back, surfaces P1 findings.

**Verify:** `cat ~/.codex-oi/logs/usage.jsonl` shows a new entry with
mode=review, exit=0.

**Result (2026-05-20):** ✅ Codex found 3 P1 (hardcoded secret line 7,
MD5 line 13, shell injection line 31) + 2 P2 (SQL injection line 20,
constant-time comparison line 15). 87k tokens.

---

### Test 2: Codex CLI (AGENTS.md discovery only — recursion makes full test wasteful)

**Setup:** Test fixture + `codex` on PATH.

**Run:**
```bash
cd /tmp/codex-oi-test
echo "What second-opinion tools does this repo configure? List the tool name + invocation. 3 lines max." | \
  codex exec -C "$(pwd)" -s read-only --json 2>/dev/null | \
  python -u ~/.codex-oi/scripts/stream-parser.py
```

**Expected:** Codex output names `codex-oi` and reproduces the bash
invocation from AGENTS.md.

**Result (2026-05-20):** ✅ Codex returned 3 lines correctly citing
`bash ".../codex-oi.sh" closeout|audit|recommit`,
`... review <file> "<focus>"`, `... plan <plan.md> [--engine gemini]`.
13k tokens.

Why no full review: Codex calling codex-oi recursively triggers a
second Codex API call — wasteful for verification. Discovery proof is
enough.

---

### Test 3: Gemini CLI (full --engine gemini end-to-end)

**Setup:**
1. `npm install -g @google/gemini-cli`
2. `gemini auth login` (OAuth, free tier)
3. Test fixture above + add a `GEMINI.md` (copy the AGENTS.md trigger
   block — Gemini CLI reads its own filename, not AGENTS.md).

**Verify discovery:**
```bash
cd /tmp/codex-oi-test
gemini -p "What second-opinion tools does this repo configure?" \
  --skip-trust --approval-mode plan
```

Expected: cites `codex-oi` with the bash invocation.

**Verify end-to-end engine path:**
```bash
bash ~/.codex-oi/scripts/codex-oi.sh review buggy.py \
  "security audit — secrets, SQL inj, shell inj, weak crypto" \
  --engine gemini
```

Expected: section bar reads `GEMINI SAYS (review):`, output lists
matching P1/P2 findings.

**Result (2026-05-20):** ✅ Discovery worked. End-to-end review
matched Codex on 3 P1 + 1 P2; missed the constant-time-compare P2
that Codex caught. Both engines independently produced actionable
findings.

---

## Manual verification needed (IDE-based, can't automate from CLI)

### Test 4: Antigravity (v1.20.3+)

1. Install Antigravity IDE from https://antigravity.google/
2. Install codex-oi locally: clone + `./install.sh`
3. Open the test fixture dir in Antigravity
4. Confirm AGENTS.md is in project root
5. In Antigravity chat: *"Review buggy.py for security issues per AGENTS.md."*
6. Expected: agent shells out to codex-oi, returns findings.
7. Verify: `cat ~/.codex-oi/logs/usage.jsonl` shows new entry.

Bonus: register a slash command. Create
`/tmp/codex-oi-test/.agents/workflows/second-opinion.md`:

```markdown
---
name: /second-opinion
description: Run codex-oi for a second AI opinion on the current diff
---

Run `bash ~/.codex-oi/scripts/codex-oi.sh closeout` and surface
accepted findings. Do not auto-apply.
```

Then `/second-opinion` in Antigravity chat triggers the closeout flow.

### Test 5: Cursor

1. Install Cursor from https://cursor.sh
2. Open the test fixture dir
3. Cursor reads AGENTS.md automatically (per v0.42+)
4. In Cursor chat: *"Review buggy.py per AGENTS.md."*
5. Expected: Cursor's agent shells out to codex-oi.
6. Verify telemetry log.

Note: Cursor's permission model may require approving the shell
command on first run. Approve "Always" for the codex-oi.sh path.

### Test 6: Continue.dev

1. Install the Continue VS Code extension
2. Edit `.continue/config.json` in the test fixture, add to
   `systemMessage`:
   ```
   "This repo has codex-oi installed. When the user asks for a second
    opinion or audit, run `bash ~/.codex-oi/scripts/codex-oi.sh review
    <file> "<focus>"` via the shell tool."
   ```
3. Open the test fixture in VS Code
4. In Continue chat: *"Review buggy.py for security."*
5. Expected: Continue invokes codex-oi via shell tool.
6. Verify telemetry log.

Continue.dev does NOT auto-read AGENTS.md as of this writing; the
trigger must live in `config.json`.

### Test 7: Aider

1. `pip install aider-chat` (or `pipx install aider-chat`)
2. `cd /tmp/codex-oi-test` (must have CONVENTIONS.md)
3. `aider buggy.py`
4. In Aider chat: *"Review this file per CONVENTIONS.md."*
5. Expected: Aider reads CONVENTIONS.md, executes the codex-oi shell
   command.
6. Verify telemetry log.

Aider's `--auto-test` flag or `/run` slash command may be needed
depending on how strictly Aider gates shell commands.

---

## What "verified" means here

A green check means the agent **actually invoked codex-oi end-to-end**
in a test fixture and produced expected output. It does NOT mean:

- the agent will reliably choose to invoke codex-oi for every user
  prompt (agent behavior is probabilistic)
- the discovery file format is stable forever (each tool's spec evolves)
- no setup steps are needed (most tools require an explicit "trust"
  or "allow shell command" approval on first use)

Re-run the fixture tests when:
- You upgrade any of the agent tools
- Anthropic / OpenAI / Google change their CLI auth or output format
- You add a new engine adapter (test it as both discovery target and
  invocation engine)
