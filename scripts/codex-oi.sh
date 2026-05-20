#!/usr/bin/env bash
#
# codex-oi — Codex CLI second-opinion bridge
# Five modes: review | plan | audit | closeout | recommit
#
# Usage:
#   codex-oi.sh review <path> [focus]
#   codex-oi.sh plan <file.md>
#   codex-oi.sh audit
#   codex-oi.sh closeout [auto|local|branch|commit <ref>]
#   codex-oi.sh recommit <ref>
#
# Environment:
#   CODEX_OI_BIN        Codex binary (default: codex)
#   CODEX_OI_YOLO       1 to keep nested review in full-access mode (default: 1)
#   CODEX_OI_TIMEOUT    Seconds (default: 600)
#   CODEX_OI_TELEMETRY  1 to write ~/.codex-oi/logs/usage.jsonl
#   CODEX_OI_OUTPUT     If set, tee output to this file
#
set -euo pipefail

CODEX_BIN="${CODEX_OI_BIN:-codex}"
TIMEOUT="${CODEX_OI_TIMEOUT:-600}"
YOLO="${CODEX_OI_YOLO:-1}"
TELEMETRY="${CODEX_OI_TELEMETRY:-0}"
OUTPUT="${CODEX_OI_OUTPUT:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARSER="$SCRIPT_DIR/stream-parser.py"

PARALLEL_TESTS=""
PYTHON_BIN=""

# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────

die() {
  echo "codex-oi: $*" >&2
  exit 1
}

require() {
  command -v "$1" >/dev/null 2>&1 || die "'$1' not found in PATH"
}

# Detect a working Python 3 — tries python3, python, py -3 in order.
# On Windows, python3.exe may be the Microsoft Store stub which resolves via
# `command -v` but errors out on actual execution; we probe with --version.
detect_python() {
  for candidate in python3 python "py -3"; do
    # shellcheck disable=SC2086
    if $candidate --version >/dev/null 2>&1; then
      # Confirm it's actually Python 3
      local ver
      # shellcheck disable=SC2086
      ver=$($candidate -c "import sys; print(sys.version_info[0])" 2>/dev/null || true)
      if [ "$ver" = "3" ]; then
        PYTHON_BIN="$candidate"
        return 0
      fi
    fi
  done
  die "Python 3 not found in PATH (tried: python3, python, py -3)"
}

repo_root() {
  git rev-parse --show-toplevel 2>/dev/null || die "not in a git repository"
}

project_name() {
  basename "$(repo_root)"
}

git_brief() {
  local branch sha
  branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "?")
  sha=$(git rev-parse --short HEAD 2>/dev/null || echo "?")
  echo "$branch @ $sha"
}

dirty_tree() {
  ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null \
    || [ -n "$(git ls-files --others --exclude-standard 2>/dev/null)" ]
}

pr_base_ref() {
  command -v gh >/dev/null 2>&1 || return 1
  gh pr view --json baseRefName --jq .baseRefName 2>/dev/null
}

write_telemetry() {
  [ "$TELEMETRY" = "1" ] || return 0
  local mode="$1" tokens="$2" exit_code="$3"
  mkdir -p "$HOME/.codex-oi/logs"
  printf '{"ts":"%s","project":"%s","mode":"%s","tokens":"%s","exit":"%s"}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    "$(project_name)" "$mode" "$tokens" "$exit_code" \
    >> "$HOME/.codex-oi/logs/usage.jsonl"
}

# ─────────────────────────────────────────────────────────────────────────────
# Context preamble — auto-detect project docs
# ─────────────────────────────────────────────────────────────────────────────

build_preamble() {
  local out=""
  local proj="$(project_name)"
  local brief="$(git_brief)"

  out+="PROJECT CONTEXT — $proj"$'\n'
  out+="Branch: $brief"$'\n\n'

  local doc=""
  for candidate in CLAUDE.md AGENTS.md .cursorrules README.md; do
    if [ -f "$(repo_root)/$candidate" ]; then
      doc="$candidate"
      break
    fi
  done

  if [ -n "$doc" ]; then
    out+="### Project brief (from $doc)"$'\n'
    out+="$(head -n 120 "$(repo_root)/$doc")"$'\n\n'
  else
    out+="(No project docs found. Infer intent from source.)"$'\n\n'
  fi

  out+="### Your job"$'\n'
  out+="Be a brutally honest second opinion. Find bugs, drift from documented "
  out+="intent, security holes, overcomplexity, missing edges at boundaries. "
  out+="Be terse. Use priorities P1 (must fix) > P2 (should fix) > P3 (nice). "
  out+="No compliments. No filler. Just findings + reasoning + file:line."$'\n'

  printf '%s' "$out"
}

filesystem_boundary() {
  cat <<'EOF'
IMPORTANT: Stay focused on this project's source code (src/, lib/, scripts/,
tests/, app/, pkg/, internal/, cmd/, etc. — whatever this project uses).
Do NOT read or analyze:
  • .claude/ or any agent-config files
  • ~/.codex/ or other CLI-config dirs
  • node_modules, .venv, dist, build, target, .git
You are READ-ONLY. Do not modify any file.
EOF
}

# ─────────────────────────────────────────────────────────────────────────────
# codex exec (modes A/B/C)
# ─────────────────────────────────────────────────────────────────────────────

run_exec() {
  local mode="$1" effort="$2" task="$3"

  # Intentionally NOT `local` — trap fires at script exit (after function
  # returns), so the variable must remain in scope. Defensive `${var:-}` in
  # the trap body covers the case where mktemp failed before assignment.
  prompt_file="$(mktemp 2>/dev/null || mktemp -t codex-oi.XXXXXX)"
  trap 'rm -f "${prompt_file:-}"' EXIT

  {
    filesystem_boundary
    echo
    build_preamble
    echo
    echo "$task"
  } > "$prompt_file"

  local repo
  repo="$(repo_root)"

  local tee_target=()
  if [ -n "$OUTPUT" ]; then
    tee_target=(tee -a "$OUTPUT")
  else
    tee_target=(cat)
  fi

  echo "═══════════════════════════════════════════════════════════"
  echo "CODEX SAYS ($mode):"
  echo "═══════════════════════════════════════════════════════════"

  local exit_code=0
  # shellcheck disable=SC2086
  if ! timeout "$TIMEOUT" "$CODEX_BIN" exec "$(cat "$prompt_file")" \
        -C "$repo" -s read-only \
        -c "model_reasoning_effort=\"$effort\"" \
        --json 2>/dev/null \
        | $PYTHON_BIN -u "$PARSER" \
        | "${tee_target[@]}"; then
    exit_code=$?
  fi

  echo "═══════════════════════════════════════════════════════════"

  write_telemetry "$mode" "0" "$exit_code"
  return $exit_code
}

# ─────────────────────────────────────────────────────────────────────────────
# codex review (modes D/E)
# ─────────────────────────────────────────────────────────────────────────────

run_review() {
  local mode="$1"
  shift
  local review_args=("$@")

  if [ "$YOLO" = "1" ]; then
    review_args+=("--dangerously-bypass-approvals-and-sandbox")
  fi

  echo "═══════════════════════════════════════════════════════════"
  echo "CODEX SAYS ($mode): $CODEX_BIN review ${review_args[*]}"
  echo "═══════════════════════════════════════════════════════════"

  local exit_code=0
  if [ -n "$PARALLEL_TESTS" ]; then
    bash -c "$PARALLEL_TESTS" &
    local tests_pid=$!
    if ! timeout "$TIMEOUT" "$CODEX_BIN" review "${review_args[@]}"; then
      exit_code=$?
    fi
    wait "$tests_pid" || true
  else
    if ! timeout "$TIMEOUT" "$CODEX_BIN" review "${review_args[@]}"; then
      exit_code=$?
    fi
  fi

  echo "═══════════════════════════════════════════════════════════"

  if [ "$exit_code" = "0" ]; then
    echo "codex-oi clean: no accepted/actionable findings reported"
  fi

  write_telemetry "$mode" "0" "$exit_code"
  return $exit_code
}

# ─────────────────────────────────────────────────────────────────────────────
# Closeout auto-target
# ─────────────────────────────────────────────────────────────────────────────

closeout_auto_target() {
  if dirty_tree; then
    echo "local"
    return
  fi
  local base
  if base="$(pr_base_ref)" && [ -n "$base" ]; then
    echo "branch:$base"
    return
  fi
  echo "branch:main"
}

# ─────────────────────────────────────────────────────────────────────────────
# Mode dispatch
# ─────────────────────────────────────────────────────────────────────────────

usage() {
  cat <<'EOF'
codex-oi — Codex CLI second-opinion bridge

Modes:
  review <path> [focus]            Custom-prompt audit of a file/folder
  plan <file.md>                   Challenge a plan document before coding
  audit                            Full project sweep (high effort)
  closeout [target]                Structured diff review
                                   target: auto (default) | local
                                           | branch [base] | commit <ref>
  recommit <ref>                   Review a single landed commit

Options for closeout/recommit:
  --parallel-tests "<cmd>"         Run tests concurrently
  --no-yolo                        Don't pass --dangerously-bypass-approvals

Env vars:
  CODEX_OI_BIN, CODEX_OI_YOLO, CODEX_OI_TIMEOUT, CODEX_OI_TELEMETRY,
  CODEX_OI_OUTPUT
EOF
}

main() {
  [ $# -ge 1 ] || { usage; exit 0; }

  require "$CODEX_BIN"
  require git
  detect_python
  repo_root >/dev/null

  local mode="$1"
  shift

  # Pull out shared flags
  local positional=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --parallel-tests)
        PARALLEL_TESTS="${2:-}"
        shift 2
        ;;
      --no-yolo)
        YOLO=0
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        positional+=("$1")
        shift
        ;;
    esac
  done
  set -- "${positional[@]:-}"

  case "$mode" in
    review)
      [ $# -ge 1 ] || die "review needs a path"
      local path="$1"
      local focus="${2:-general bugs + security + drift from project docs}"
      local task
      task=$(cat <<EOF
TASK: Review the file/folder at: $path
Focus: $focus

Find: bugs, security issues, anti-patterns, dead code, drift from any locked
decisions in the project docs, overcomplexity, missing error handling at
boundaries (network, subprocess, user input, DB).

Output format:
  P1/P2/P3 list with \`path:line — issue (1 line) — fix (1 line)\`.
  Group by severity. Include at least one observation even if all-clear.
EOF
)
      run_exec "review" "medium" "$task"
      ;;

    plan)
      [ $# -ge 1 ] || die "plan needs a file path"
      local plan_path="$1"
      [ -f "$plan_path" ] || die "plan file not found: $plan_path"
      local plan_body
      plan_body=$(cat "$plan_path")
      local referenced
      referenced=$(grep -oE '[a-zA-Z0-9_./-]+\.(py|ts|tsx|js|jsx|go|rs|rb|java|cpp|c|h|sh|ps1)' \
                     "$plan_path" | sort -u | head -n 20 || true)
      local task
      task=$(cat <<EOF
TASK: Challenge this plan BEFORE coding starts.

Find: logical gaps, unstated assumptions, missing error handling, overcomplex
designs, ordering/dependency issues, drift from documented intent, security
risks, missing rollback paths.

Also read these source files referenced in the plan:
$referenced

THE PLAN:
---
$plan_body
---
EOF
)
      run_exec "plan" "medium" "$task"
      ;;

    audit)
      cat <<EOF
codex-oi: Full audit is heavy.
  Effort: high
  Expected: 50k–8M tokens, 5–15 minutes
  Cost (Codex API): roughly \$0.30–\$1.00 depending on repo size

Press ENTER to continue, Ctrl-C to abort.
EOF
      read -r _
      local task
      task=$(cat <<'EOF'
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
EOF
)
      run_exec "audit" "high" "$task"
      ;;

    closeout)
      local target="${1:-auto}"
      local ref="${2:-}"
      case "$target" in
        auto)
          local resolved
          resolved="$(closeout_auto_target)"
          if [ "$resolved" = "local" ]; then
            run_review "closeout-local" --uncommitted
          else
            local base="${resolved#branch:}"
            git fetch origin >/dev/null 2>&1 || true
            run_review "closeout-branch" --base "origin/$base"
          fi
          ;;
        local)
          run_review "closeout-local" --uncommitted
          ;;
        branch)
          local base="${ref:-main}"
          git fetch origin >/dev/null 2>&1 || true
          run_review "closeout-branch" --base "origin/$base"
          ;;
        commit)
          [ -n "$ref" ] || die "closeout commit needs <ref>"
          run_review "closeout-commit" --commit "$ref"
          ;;
        *)
          die "unknown closeout target: $target"
          ;;
      esac
      ;;

    recommit)
      [ $# -ge 1 ] || die "recommit needs <ref>"
      run_review "recommit" --commit "$1"
      ;;

    -h|--help|help)
      usage
      ;;

    *)
      die "unknown mode: $mode (run with --help)"
      ;;
  esac
}

main "$@"
