# Engine adapters

`codex-oi` defaults to the OpenAI Codex CLI engine, but the `--engine` flag
lets the dispatcher route to other AI backends. Each adapter is a self-
contained shell script (bash for the `.sh` dispatcher, PowerShell for the
`.ps1` dispatcher) that exports a small interface.

## Bash adapter interface

A file `engines/<name>.sh` MUST define:

```bash
# Name shown in section bars and telemetry. Default: filename without .sh
ENGINE_NAME="<name>"

# Pre-flight: check the engine's CLI binary + auth. Die with a clear
# message if anything is missing. Called once before any invocation.
engine_check_runtime() {
  command -v <bin> >/dev/null 2>&1 || die "<bin> not installed"
  # Auth checks specific to this engine, e.g. env var presence
}

# Invoke the engine with the prompt from stdin and the desired mode.
# Args: $1 = mode (review|plan|audit), $2 = effort (low|medium|high)
# Reads prompt from stdin, writes engine output to stdout.
# Must respect $TIMEOUT (seconds) — wrap the call in `timeout "$TIMEOUT"`.
# Should keep the engine in read-only mode for prompt-driven modes.
engine_invoke() {
  local mode="$1" effort="$2"
  # ... your engine-specific invocation here, reading from stdin ...
}
```

Optional:

```bash
# Diff-driven review (closeout/recommit modes). Most engines won't have an
# equivalent of `codex review`; return non-zero if unsupported.
engine_invoke_review() {
  local mode="$1"
  shift
  # ... or ...
  return 99  # convention: 99 = mode not supported by this engine
}
```

The dispatcher passes the same prompt file to every engine (preamble +
filesystem boundary + task), so engines see a uniform input shape.

## Currently shipped adapters

| Engine | Modes supported | Auth |
|---|---|---|
| `codex` (default, inline in dispatcher) | review, plan, audit, closeout, recommit | `OPENAI_API_KEY` or `CLAUDE_CODE_OAUTH_TOKEN` |
| `gemini` | review, plan, audit | `GEMINI_API_KEY` |

## Adding a new adapter

1. Create `engines/<name>.sh` (and `engines/<name>.ps1` for Windows).
2. Implement the interface above.
3. Document required auth env vars in this README's table.
4. Smoke-test with `bash scripts/codex-oi.sh review somefile.py --engine <name>`.
5. Mention the new engine in `../AGENTS.md` and `../README.md` integration tables.

Anti-patterns to avoid:
- **Don't auto-apply findings** — every engine output is advisory only.
- **Don't bypass the prompt file contract** — read from stdin so the
  preamble + boundary the dispatcher built is respected.
- **Don't skip the timeout wrap** — runaway agent loops cost real money.
- **Don't silently swallow errors** — if the engine errors, write to
  stderr and return a non-zero exit code.
