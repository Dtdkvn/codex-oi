#!/usr/bin/env pwsh
<#
.SYNOPSIS
  codex-oi — Codex CLI second-opinion bridge (Windows-native PowerShell helper).

.DESCRIPTION
  Five modes: review | plan | audit | closeout | recommit
  Mirrors scripts/codex-oi.sh but uses native PowerShell — no WSL required.

.PARAMETER Mode
  review | plan | audit | closeout | recommit | -h | --help

.PARAMETER Args
  Mode-specific positional args; see -h for details.

.EXAMPLE
  .\codex-oi.ps1 review src\services\login.py "auth flow"
  .\codex-oi.ps1 plan docs\plan.md
  .\codex-oi.ps1 audit
  .\codex-oi.ps1 closeout
  .\codex-oi.ps1 closeout local
  .\codex-oi.ps1 closeout branch
  .\codex-oi.ps1 recommit a1b2c3d
#>

[CmdletBinding()]
param(
  [Parameter(Position = 0)] [string] $Mode = '',
  [Parameter(ValueFromRemainingArguments = $true)] [string[]] $RestArgs = @()
)

$ErrorActionPreference = 'Stop'

$CodexBin   = if ($env:CODEX_OI_BIN)       { $env:CODEX_OI_BIN }       else { 'codex' }
$Timeout    = if ($env:CODEX_OI_TIMEOUT)   { [int]$env:CODEX_OI_TIMEOUT } else { 600 }
$Yolo       = if ($env:CODEX_OI_YOLO -eq '0') { $false } else { $true }
$Telemetry  = ($env:CODEX_OI_TELEMETRY -eq '1')
$Output     = $env:CODEX_OI_OUTPUT

$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$Parser     = Join-Path $ScriptDir 'stream-parser.py'

$ParallelTests = ''

function Die([string] $msg) {
  Write-Error "codex-oi: $msg"
  exit 1
}

function Require-Cmd([string] $name) {
  if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
    Die "'$name' not found in PATH"
  }
}

function Repo-Root() {
  $root = (& git rev-parse --show-toplevel 2>$null)
  if (-not $root) { Die "not in a git repository" }
  return $root.Trim()
}

function Project-Name() {
  return (Split-Path -Leaf (Repo-Root))
}

function Git-Brief() {
  $branch = (& git rev-parse --abbrev-ref HEAD 2>$null)
  $sha    = (& git rev-parse --short HEAD 2>$null)
  return "$branch @ $sha"
}

function Dirty-Tree() {
  & git diff --quiet 2>$null
  $unstaged = ($LASTEXITCODE -ne 0)
  & git diff --cached --quiet 2>$null
  $staged   = ($LASTEXITCODE -ne 0)
  $untracked = ((& git ls-files --others --exclude-standard 2>$null) -ne $null)
  return ($unstaged -or $staged -or $untracked)
}

function PR-Base-Ref() {
  if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { return $null }
  try {
    $base = (& gh pr view --json baseRefName --jq .baseRefName 2>$null)
    if ($base) { return $base.Trim() }
  } catch {}
  return $null
}

function Write-Telemetry([string] $mode, [string] $tokens, [int] $exitCode) {
  if (-not $Telemetry) { return }
  $dir = Join-Path $HOME '.codex-oi\logs'
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  $ts = (Get-Date -AsUTC).ToString('yyyy-MM-ddTHH:mm:ssZ')
  $line = "{`"ts`":`"$ts`",`"project`":`"$(Project-Name)`",`"mode`":`"$mode`",`"tokens`":`"$tokens`",`"exit`":`"$exitCode`"}"
  Add-Content -Path (Join-Path $dir 'usage.jsonl') -Value $line
}

function Build-Preamble() {
  $proj  = Project-Name
  $brief = Git-Brief
  $root  = Repo-Root

  $out = "PROJECT CONTEXT — $proj`nBranch: $brief`n`n"

  $doc = $null
  foreach ($candidate in 'CLAUDE.md', 'AGENTS.md', '.cursorrules', 'README.md') {
    $path = Join-Path $root $candidate
    if (Test-Path $path) { $doc = $candidate; break }
  }

  if ($doc) {
    $body = (Get-Content -Path (Join-Path $root $doc) -TotalCount 120) -join "`n"
    $out += "### Project brief (from $doc)`n$body`n`n"
  } else {
    $out += "(No project docs found. Infer intent from source.)`n`n"
  }

  $out += "### Your job`n"
  $out += "Be a brutally honest second opinion. Find bugs, drift from documented "
  $out += "intent, security holes, overcomplexity, missing edges at boundaries. "
  $out += "Be terse. Use priorities P1 (must fix) > P2 (should fix) > P3 (nice). "
  $out += "No compliments. No filler. Just findings + reasoning + file:line.`n"
  return $out
}

function Filesystem-Boundary() {
  return @"
IMPORTANT: Stay focused on this project's source code (src/, lib/, scripts/,
tests/, app/, pkg/, internal/, cmd/, etc. — whatever this project uses).
Do NOT read or analyze:
  * .claude/ or any agent-config files
  * ~/.codex/ or other CLI-config dirs
  * node_modules, .venv, dist, build, target, .git
You are READ-ONLY. Do not modify any file.
"@
}

function Run-Exec([string] $mode, [string] $effort, [string] $task) {
  $promptFile = [System.IO.Path]::GetTempFileName()
  try {
    $prompt = (Filesystem-Boundary) + "`n`n" + (Build-Preamble) + "`n" + $task
    Set-Content -Path $promptFile -Value $prompt -Encoding UTF8

    $repo = Repo-Root

    Write-Host "═══════════════════════════════════════════════════════════"
    Write-Host "CODEX SAYS (${mode}):"
    Write-Host "═══════════════════════════════════════════════════════════"

    $promptText = Get-Content -Raw -Path $promptFile
    $codexArgs = @(
      'exec', $promptText,
      '-C', $repo,
      '-s', 'read-only',
      '-c', "model_reasoning_effort=`"$effort`"",
      '--json'
    )

    $exitCode = 0
    try {
      & $CodexBin @codexArgs 2>$null | python -u $Parser | ForEach-Object {
        if ($Output) { Add-Content -Path $Output -Value $_ }
        Write-Output $_
      }
      $exitCode = $LASTEXITCODE
    } catch {
      $exitCode = 1
    }

    Write-Host "═══════════════════════════════════════════════════════════"

    Write-Telemetry $mode '0' $exitCode
    exit $exitCode
  } finally {
    Remove-Item -Force -ErrorAction SilentlyContinue $promptFile
  }
}

function Run-Review([string] $mode, [string[]] $reviewArgs) {
  if ($Yolo) {
    $reviewArgs += '--dangerously-bypass-approvals-and-sandbox'
  }

  Write-Host "═══════════════════════════════════════════════════════════"
  Write-Host "CODEX SAYS (${mode}): $CodexBin review $($reviewArgs -join ' ')"
  Write-Host "═══════════════════════════════════════════════════════════"

  $exitCode = 0
  $job = $null
  if ($ParallelTests) {
    $job = Start-Job -ScriptBlock {
      param($cmd)
      Invoke-Expression $cmd
    } -ArgumentList $ParallelTests
  }

  try {
    & $CodexBin review @reviewArgs
    $exitCode = $LASTEXITCODE
  } catch {
    $exitCode = 1
  }

  if ($job) {
    Wait-Job $job | Out-Null
    Receive-Job $job
    Remove-Job $job
  }

  Write-Host "═══════════════════════════════════════════════════════════"

  if ($exitCode -eq 0) {
    Write-Host "codex-oi clean: no accepted/actionable findings reported"
  }

  Write-Telemetry $mode '0' $exitCode
  exit $exitCode
}

function Closeout-Auto-Target() {
  if (Dirty-Tree) { return 'local' }
  $base = PR-Base-Ref
  if ($base) { return "branch:$base" }
  return 'branch:main'
}

function Show-Usage() {
  Write-Host @"
codex-oi — Codex CLI second-opinion bridge (PowerShell)

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
"@
}

# ─── Main dispatch ──────────────────────────────────────────────────────────

if (-not $Mode -or $Mode -in @('-h', '--help', 'help')) {
  Show-Usage
  exit 0
}

Require-Cmd $CodexBin
Require-Cmd 'git'
Require-Cmd 'python'
Repo-Root | Out-Null

# Pull flags out of RestArgs
$positional = @()
$i = 0
while ($i -lt $RestArgs.Count) {
  switch ($RestArgs[$i]) {
    '--parallel-tests' { $ParallelTests = $RestArgs[$i + 1]; $i += 2 }
    '--no-yolo'        { $Yolo = $false; $i += 1 }
    '-h'               { Show-Usage; exit 0 }
    '--help'           { Show-Usage; exit 0 }
    default            { $positional += $RestArgs[$i]; $i += 1 }
  }
}

switch ($Mode) {
  'review' {
    if ($positional.Count -lt 1) { Die "review needs a path" }
    $path  = $positional[0]
    $focus = if ($positional.Count -ge 2) { $positional[1] } else { 'general bugs + security + drift from project docs' }
    $task = @"
TASK: Review the file/folder at: $path
Focus: $focus

Find: bugs, security issues, anti-patterns, dead code, drift from any locked
decisions in the project docs, overcomplexity, missing error handling at
boundaries (network, subprocess, user input, DB).

Output format:
  P1/P2/P3 list with ``path:line — issue (1 line) — fix (1 line)``.
  Group by severity. Include at least one observation even if all-clear.
"@
    Run-Exec 'review' 'medium' $task
  }

  'plan' {
    if ($positional.Count -lt 1) { Die "plan needs a file path" }
    $planPath = $positional[0]
    if (-not (Test-Path $planPath)) { Die "plan file not found: $planPath" }
    $planBody = Get-Content -Raw -Path $planPath
    $pattern = '[a-zA-Z0-9_./\\-]+\.(py|ts|tsx|js|jsx|go|rs|rb|java|cpp|c|h|sh|ps1)'
    $referenced = ($planBody | Select-String -Pattern $pattern -AllMatches).Matches |
                  ForEach-Object { $_.Value } | Sort-Object -Unique | Select-Object -First 20
    $referencedJoined = ($referenced -join "`n")
    $task = @"
TASK: Challenge this plan BEFORE coding starts.

Find: logical gaps, unstated assumptions, missing error handling, overcomplex
designs, ordering/dependency issues, drift from documented intent, security
risks, missing rollback paths.

Also read these source files referenced in the plan:
$referencedJoined

THE PLAN:
---
$planBody
---
"@
    Run-Exec 'plan' 'medium' $task
  }

  'audit' {
    Write-Host @"
codex-oi: Full audit is heavy.
  Effort: high
  Expected: 50k–8M tokens, 5–15 minutes
  Cost (Codex API): roughly `$0.30–`$1.00 depending on repo size

Press ENTER to continue, Ctrl-C to abort.
"@
    [void](Read-Host)
    $task = @"
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
"@
    Run-Exec 'audit' 'high' $task
  }

  'closeout' {
    $target = if ($positional.Count -ge 1) { $positional[0] } else { 'auto' }
    $ref    = if ($positional.Count -ge 2) { $positional[1] } else { '' }
    switch ($target) {
      'auto' {
        $resolved = Closeout-Auto-Target
        if ($resolved -eq 'local') {
          Run-Review 'closeout-local' @('--uncommitted')
        } else {
          $base = $resolved.Substring('branch:'.Length)
          & git fetch origin 2>$null | Out-Null
          Run-Review 'closeout-branch' @('--base', "origin/$base")
        }
      }
      'local' { Run-Review 'closeout-local' @('--uncommitted') }
      'branch' {
        $base = if ($ref) { $ref } else { 'main' }
        & git fetch origin 2>$null | Out-Null
        Run-Review 'closeout-branch' @('--base', "origin/$base")
      }
      'commit' {
        if (-not $ref) { Die "closeout commit needs <ref>" }
        Run-Review 'closeout-commit' @('--commit', $ref)
      }
      default { Die "unknown closeout target: $target" }
    }
  }

  'recommit' {
    if ($positional.Count -lt 1) { Die "recommit needs <ref>" }
    Run-Review 'recommit' @('--commit', $positional[0])
  }

  default { Die "unknown mode: $Mode (run with --help)" }
}
