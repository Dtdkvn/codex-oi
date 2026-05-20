#!/usr/bin/env pwsh
<#
.SYNOPSIS
  codex-oi installer for Windows / PowerShell.
.DESCRIPTION
  Symlinks (or copies) this repo into ~\.claude\skills\codex-oi\
  so Claude Code picks it up as a user-level skill.
#>

$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$TargetDir = Join-Path $HOME '.claude\skills\codex-oi'

Write-Host "codex-oi installer"
Write-Host "  source: $ScriptDir"
Write-Host "  target: $TargetDir"
Write-Host ""

if (Test-Path $TargetDir) {
  Write-Error "Target already exists. Remove or back up first:`n  Remove-Item -Recurse -Force '$TargetDir'"
  exit 1
}

$parent = Split-Path -Parent $TargetDir
New-Item -ItemType Directory -Force -Path $parent | Out-Null

# Try symlink first (requires Developer Mode or admin on Windows)
try {
  New-Item -ItemType SymbolicLink -Path $TargetDir -Target $ScriptDir -ErrorAction Stop | Out-Null
  Write-Host "Linked: $TargetDir -> $ScriptDir"
} catch {
  Write-Host "Symlink failed (need Developer Mode or admin). Copying instead."
  Copy-Item -Recurse -Path $ScriptDir -Destination $TargetDir
  Write-Host "Copied: $TargetDir"
  Write-Host "Note: re-run installer after every update to refresh the copy."
}

Write-Host ""
Write-Host "Done. Test with:"
Write-Host "  $ScriptDir\scripts\codex-oi.ps1 --help"
Write-Host ""
Write-Host "In Claude Code, the skill will be picked up as 'codex-oi' next session."
