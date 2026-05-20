#!/usr/bin/env bash
#
# Gemini CLI adapter for codex-oi.
# Requires: `gemini` CLI (npm install -g @google/gemini-cli) + GEMINI_API_KEY.
#
# Maps codex-oi's `review` / `plan` / `audit` modes to gemini headless
# invocations. closeout/recommit are not supported (Gemini has no direct
# equivalent of `codex review --uncommitted | --base | --commit`).
#

ENGINE_NAME="gemini"
GEMINI_BIN="${CODEX_OI_GEMINI_BIN:-gemini}"
GEMINI_MODEL="${CODEX_OI_GEMINI_MODEL:-gemini-2.5-pro}"

engine_check_runtime() {
  command -v "$GEMINI_BIN" >/dev/null 2>&1 \
    || die "'$GEMINI_BIN' not found. Install: npm install -g @google/gemini-cli"

  # Gemini accepts auth via env var OR ~/.gemini/settings.json. We only
  # hard-check env vars here; users with settings.json get a runtime
  # message from gemini itself.
  if [ -z "${GEMINI_API_KEY:-}" ] \
      && [ -z "${GOOGLE_GENAI_USE_VERTEXAI:-}" ] \
      && [ -z "${GOOGLE_GENAI_USE_GCA:-}" ] \
      && [ ! -f "$HOME/.gemini/settings.json" ]; then
    die "Gemini auth not configured. Run 'gemini auth login' (OAuth, free tier — recommended) or set GEMINI_API_KEY (API mode)."
  fi
}

# Effort tiers don't map cleanly across providers. Map our medium/high
# onto Gemini's stronger model when 'high' is requested.
_resolve_gemini_model() {
  local effort="$1"
  if [ -n "${CODEX_OI_GEMINI_MODEL_OVERRIDE:-}" ]; then
    echo "$CODEX_OI_GEMINI_MODEL_OVERRIDE"
    return
  fi
  case "$effort" in
    high) echo "gemini-2.5-pro" ;;
    *)    echo "$GEMINI_MODEL" ;;
  esac
}

engine_invoke() {
  local mode="$1" effort="$2"
  local model
  model="$(_resolve_gemini_model "$effort")"

  # Read prompt from stdin (dispatcher pipes it in). Gemini headless mode:
  #   -p <text>           run with this prompt
  #   --approval-mode     plan = read-only (closest analog to codex -s read-only)
  #   -m <model>          model id
  #
  # Per `gemini --help`: "-p/--prompt ... Appended to input on stdin".
  # So passing -p '' with stdin = full prompt content works.
  local prompt
  prompt="$(cat)"

  # --skip-trust: needed for headless/automated use; without it Gemini
  # refuses to run unless the cwd was marked trusted interactively.
  # --approval-mode plan: read-only, closest analog to codex -s read-only.
  # shellcheck disable=SC2086
  timeout "$TIMEOUT" "$GEMINI_BIN" \
    -m "$model" \
    --skip-trust \
    --approval-mode plan \
    -p "$prompt" 2>&1
}

# Diff-driven review modes — Gemini has no direct equivalent. Returning
# 99 signals "mode not supported" to the dispatcher, which will print a
# clear error rather than producing empty output.
engine_invoke_review() {
  echo "codex-oi: 'closeout'/'recommit' modes not supported by Gemini adapter." >&2
  echo "Use --engine codex for diff-driven review modes." >&2
  return 99
}
