#!/usr/bin/env pwsh
<#
.SYNOPSIS
  codex-oi - Codex CLI second-opinion bridge (Windows-native PowerShell helper).

.DESCRIPTION
  Five modes: review | plan | audit | closeout | recommit
  Mirrors scripts/codex-oi.sh but uses native PowerShell - no WSL required.

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

$CodexBin = if ($env:CODEX_OI_BIN) { $env:CODEX_OI_BIN } else { 'codex' }
$Timeout = if ($env:CODEX_OI_TIMEOUT) { [int] $env:CODEX_OI_TIMEOUT } else { 600 }
$Yolo = if ($env:CODEX_OI_YOLO -eq '0') { $false } else { $true }
$Telemetry = ($env:CODEX_OI_TELEMETRY -eq '1')
$Output = $env:CODEX_OI_OUTPUT

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Parser = Join-Path $ScriptDir 'stream-parser.py'
$ParallelTests = ''
$PythonBin = ''
$PythonArgs = @()
$SectionBar = '=' * 59

function Die([string] $Message) {
  Write-Error "codex-oi: $Message"
  exit 1
}

function Require-Cmd([string] $Name) {
  if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
    Die "'$Name' not found in PATH"
  }
}

function Set-PythonCommand() {
  if (Get-Command python -ErrorAction SilentlyContinue) {
    try {
      $major = (& python -c "import sys; print(sys.version_info[0])" 2>$null)
      if ($LASTEXITCODE -eq 0 -and $major.Trim() -eq '3') {
        $script:PythonBin = 'python'
        $script:PythonArgs = @()
        return
      }
    } catch {}
  }

  if (Get-Command python3 -ErrorAction SilentlyContinue) {
    try {
      $major = (& python3 -c "import sys; print(sys.version_info[0])" 2>$null)
      if ($LASTEXITCODE -eq 0 -and $major.Trim() -eq '3') {
        $script:PythonBin = 'python3'
        $script:PythonArgs = @()
        return
      }
    } catch {}
  }

  if (Get-Command py -ErrorAction SilentlyContinue) {
    try {
      $major = (& py -3 -c "import sys; print(sys.version_info[0])" 2>$null)
      if ($LASTEXITCODE -eq 0 -and $major.Trim() -eq '3') {
        $script:PythonBin = 'py'
        $script:PythonArgs = @('-3')
        return
      }
    } catch {}
  }

  Die "Python 3 not found in PATH (tried: python, python3, py -3)"
}

function Repo-Root() {
  $root = (& git rev-parse --show-toplevel 2>$null)
  if (-not $root) {
    Die "not in a git repository"
  }
  return $root.Trim()
}

function Project-Name() {
  return (Split-Path -Leaf (Repo-Root))
}

function Git-Brief() {
  $branch = (& git rev-parse --abbrev-ref HEAD 2>$null)
  $sha = (& git rev-parse --short HEAD 2>$null)
  return "$branch @ $sha"
}

function Dirty-Tree() {
  & git diff --quiet 2>$null
  $unstaged = ($LASTEXITCODE -ne 0)

  & git diff --cached --quiet 2>$null
  $staged = ($LASTEXITCODE -ne 0)

  $untracked = [bool] (& git ls-files --others --exclude-standard 2>$null)
  return ($unstaged -or $staged -or $untracked)
}

function PR-Base-Ref() {
  if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    return $null
  }

  try {
    $base = (& gh pr view --json baseRefName --jq .baseRefName 2>$null)
    if ($base) {
      return $base.Trim()
    }
  } catch {}

  return $null
}

function Write-Telemetry([string] $ModeName, [string] $Tokens, [int] $ExitCode) {
  if (-not $Telemetry) {
    return
  }

  $dir = Join-Path $HOME '.codex-oi\logs'
  New-Item -ItemType Directory -Force -Path $dir | Out-Null

  # [DateTime]::UtcNow works on PowerShell 5.1+; Get-Date -AsUTC needs 7.1+.
  $timestamp = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
  $line = "{`"ts`":`"$timestamp`",`"project`":`"$(Project-Name)`",`"mode`":`"$ModeName`",`"tokens`":`"$Tokens`",`"exit`":`"$ExitCode`"}"
  Add-Content -Path (Join-Path $dir 'usage.jsonl') -Value $line
}

function Build-Preamble() {
  $project = Project-Name
  $brief = Git-Brief
  $root = Repo-Root

  $output = "PROJECT CONTEXT - $project`nBranch: $brief`n`n"

  $doc = $null
  foreach ($candidate in 'CLAUDE.md', 'AGENTS.md', '.cursorrules', 'README.md') {
    $path = Join-Path $root $candidate
    if (Test-Path $path) {
      $doc = $candidate
      break
    }
  }

  if ($doc) {
    $body = (Get-Content -Path (Join-Path $root $doc) -TotalCount 120) -join "`n"
    $output += "### Project brief (from $doc)`n$body`n`n"
  } else {
    $output += "(No project docs found. Infer intent from source.)`n`n"
  }

  $output += "### Your job`n"
  $output += "Be a brutally honest second opinion. Find bugs, drift from documented "
  $output += "intent, security holes, overcomplexity, missing edges at boundaries. "
  $output += "Be terse. Use priorities P1 (must fix) > P2 (should fix) > P3 (nice). "
  $output += "No compliments. No filler. Just findings + reasoning + file:line.`n"

  return $output
}

function Filesystem-Boundary() {
  return @"
IMPORTANT: Stay focused on this project's source code (src/, lib/, scripts/,
tests/, app/, pkg/, internal/, cmd/, etc. - whatever this project uses).
Do NOT read or analyze:
  * .claude/ or any agent-config files
  * ~/.codex/ or other CLI-config dirs
  * node_modules, .venv, dist, build, target, .git
You are READ-ONLY. Do not modify any file.
"@
}

function Run-Exec([string] $ModeName, [string] $Effort, [string] $Task) {
  $promptFile = [System.IO.Path]::GetTempFileName()

  try {
    $prompt = (Filesystem-Boundary) + "`n`n" + (Build-Preamble) + "`n" + $Task
    Set-Content -Path $promptFile -Value $prompt -Encoding UTF8

    $repo = Repo-Root

    Write-Host $SectionBar
    Write-Host "CODEX SAYS (${ModeName}):"
    Write-Host $SectionBar

    $codexArgs = @(
      'exec',
      '-C', $repo,
      '-s', 'read-only',
      '-c', "model_reasoning_effort=`"$Effort`"",
      '--json'
    )

    # Scope EAP=Continue around the pipe. The npm-shipped `codex` shim resolves
    # to codex.ps1 (not codex.cmd) on Windows; its inner `& node ...` writes a
    # "Reading prompt from stdin..." banner to stderr. Under EAP=Stop, that
    # stderr line is wrapped as a RemoteException and rethrown — `2>$null` does
    # NOT suppress nested PowerShell error streams, only native stderr. Without
    # this scope, every Run-Exec call dies in catch with $exitCode=1 before any
    # Codex output reaches the parser.
    $exitCode = 0
    $oldEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
      Get-Content -Raw -Path $promptFile |
        & $CodexBin @codexArgs 2>$null |
        & $PythonBin @PythonArgs -u $Parser |
        ForEach-Object {
          if ($Output) {
            Add-Content -Path $Output -Value $_
          }
          Write-Host $_
        }
      $exitCode = $LASTEXITCODE
    } catch {
      # Surface the exception instead of swallowing — silent catch was the
      # reason this class of bug went undiagnosed for a release cycle.
      Write-Host "codex-oi error in Run-Exec: $($_.Exception.Message)"
      $exitCode = 1
    } finally {
      $ErrorActionPreference = $oldEAP
    }

    Write-Host $SectionBar
    Write-Telemetry $ModeName '0' $exitCode
    return $exitCode
  } finally {
    Remove-Item -Force -ErrorAction SilentlyContinue $promptFile
  }
}

function Run-Review([string] $ModeName, [string[]] $ReviewArgs) {
  if ($Yolo) {
    $ReviewArgs += '--dangerously-bypass-approvals-and-sandbox'
  }

  Write-Host $SectionBar
  Write-Host "CODEX SAYS (${ModeName}): $CodexBin review $($ReviewArgs -join ' ')"
  Write-Host $SectionBar

  $job = $null
  if ($ParallelTests) {
    $job = Start-Job -ScriptBlock {
      param($CommandText)
      Invoke-Expression $CommandText
    } -ArgumentList $ParallelTests
  }

  # Same EAP-scoping rationale as Run-Exec: codex.ps1 npm shim writes banner
  # text to stderr that PowerShell wraps as a RemoteException under EAP=Stop.
  $exitCode = 0
  $oldEAP = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    & $CodexBin review @ReviewArgs
    $exitCode = $LASTEXITCODE
  } catch {
    Write-Host "codex-oi error in Run-Review: $($_.Exception.Message)"
    $exitCode = 1
  } finally {
    $ErrorActionPreference = $oldEAP
  }

  if ($job) {
    Wait-Job $job | Out-Null
    Receive-Job $job
    Remove-Job $job
  }

  Write-Host $SectionBar

  if ($exitCode -eq 0) {
    Write-Host "codex-oi clean: no accepted/actionable findings reported"
  }

  Write-Telemetry $ModeName '0' $exitCode
  return $exitCode
}

function Closeout-Auto-Target() {
  if (Dirty-Tree) {
    return 'local'
  }

  $base = PR-Base-Ref
  if ($base) {
    return "branch:$base"
  }

  return 'branch:main'
}

function Show-Usage() {
  Write-Host @"
codex-oi - Codex CLI second-opinion bridge (PowerShell)

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

if (-not $Mode -or $Mode -in @('-h', '--help', 'help')) {
  Show-Usage
  exit 0
}

Require-Cmd $CodexBin
Require-Cmd 'git'
Set-PythonCommand
Repo-Root | Out-Null

$positional = @()
$i = 0
while ($i -lt $RestArgs.Count) {
  switch ($RestArgs[$i]) {
    '--parallel-tests' {
      $ParallelTests = $RestArgs[$i + 1]
      $i += 2
    }
    '--no-yolo' {
      $Yolo = $false
      $i += 1
    }
    '-h' {
      Show-Usage
      exit 0
    }
    '--help' {
      Show-Usage
      exit 0
    }
    default {
      $positional += $RestArgs[$i]
      $i += 1
    }
  }
}

switch ($Mode) {
  'review' {
    if ($positional.Count -lt 1) {
      Die "review needs a path"
    }

    $path = $positional[0]
    $focus = if ($positional.Count -ge 2) { $positional[1] } else { 'general bugs + security + drift from project docs' }
    $task = @"
TASK: Review the file/folder at: $path
Focus: $focus

Find: bugs, security issues, anti-patterns, dead code, drift from any locked
decisions in the project docs, overcomplexity, missing error handling at
boundaries (network, subprocess, user input, DB).

Output format:
  P1/P2/P3 list with ``path:line - issue (1 line) - fix (1 line)``.
  Group by severity. Include at least one observation even if all-clear.
"@
    $exitCode = Run-Exec 'review' 'medium' $task
    exit $exitCode
  }

  'plan' {
    if ($positional.Count -lt 1) {
      Die "plan needs a file path"
    }

    $planPath = $positional[0]
    if (-not (Test-Path $planPath)) {
      Die "plan file not found: $planPath"
    }

    $planBody = Get-Content -Raw -Path $planPath
    $pattern = '[a-zA-Z0-9_./\\-]+\.(py|ts|tsx|js|jsx|go|rs|rb|java|cpp|c|h|sh|ps1)'
    $referenced = ($planBody | Select-String -Pattern $pattern -AllMatches).Matches |
      ForEach-Object { $_.Value } |
      Sort-Object -Unique |
      Select-Object -First 20
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
    $exitCode = Run-Exec 'plan' 'medium' $task
    exit $exitCode
  }

  'audit' {
    Write-Host @"
codex-oi: Full audit is heavy.
  Effort: high
  Expected: 50k-8M tokens, 5-15 minutes
  Cost (Codex API): roughly `$0.30-`$1.00 depending on repo size

Press ENTER to continue, Ctrl-C to abort.
"@
    [void] (Read-Host)

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
## P1 - must fix before next ship
- [P1] path:line - issue (1 line) - fix (1 line)
## P2 - should fix this sprint
## P3 - nice to have
## SUMMARY
- Total findings, dominant theme, biggest risk class.

Aim for at least 5 findings. Be specific with file:line.
"@
    $exitCode = Run-Exec 'audit' 'high' $task
    exit $exitCode
  }

  'closeout' {
    $target = if ($positional.Count -ge 1) { $positional[0] } else { 'auto' }
    $ref = if ($positional.Count -ge 2) { $positional[1] } else { '' }

    switch ($target) {
      'auto' {
        $resolved = Closeout-Auto-Target
        if ($resolved -eq 'local') {
          $exitCode = Run-Review 'closeout-local' @('--uncommitted')
          exit $exitCode
        } else {
          $base = $resolved.Substring('branch:'.Length)
          & git fetch origin 2>$null | Out-Null
          $exitCode = Run-Review 'closeout-branch' @('--base', "origin/$base")
          exit $exitCode
        }
      }
      'local' {
        $exitCode = Run-Review 'closeout-local' @('--uncommitted')
        exit $exitCode
      }
      'branch' {
        $base = if ($ref) { $ref } else { 'main' }
        & git fetch origin 2>$null | Out-Null
        $exitCode = Run-Review 'closeout-branch' @('--base', "origin/$base")
        exit $exitCode
      }
      'commit' {
        if (-not $ref) {
          Die "closeout commit needs <ref>"
        }
        $exitCode = Run-Review 'closeout-commit' @('--commit', $ref)
        exit $exitCode
      }
      default {
        Die "unknown closeout target: $target"
      }
    }
  }

  'recommit' {
    if ($positional.Count -lt 1) {
      Die "recommit needs <ref>"
    }
    $exitCode = Run-Review 'recommit' @('--commit', $positional[0])
    exit $exitCode
  }

  default {
    Die "unknown mode: $Mode (run with --help)"
  }
}
