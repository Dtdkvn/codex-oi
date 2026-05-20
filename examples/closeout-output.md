# Example: `codex-oi closeout`

Output from running `./scripts/codex-oi.sh closeout` after staging a small
refactor. The auto-target picked `--uncommitted` because the working tree
was dirty.

```
═══════════════════════════════════════════════════════════
CODEX SAYS (closeout-local): codex review --uncommitted --dangerously-bypass-approvals-and-sandbox
═══════════════════════════════════════════════════════════
Reviewing 47 lines across 3 files (uncommitted).

# Findings

## src/services/user.py
- Lines 21-28 — extracted `_validate_email()` from inline regex. Good move.
  No issues with the extraction itself.
- Line 34 — new branch handles `None` username but logs `username.lower()`
  one line later. Will raise AttributeError on the new None path. Fix:
  guard the log call, or short-circuit return earlier.

## src/api/users.py
- Lines 12-15 — added rate-limit decorator import but not applied to the
  endpoint. Either apply it or remove the dead import.

## tests/test_user.py
- Lines 88-105 — new tests for `_validate_email()`. Coverage looks good.
  No issues.

# Summary
2 accepted findings (1 bug, 1 dead import). 1 file clean.

═══════════════════════════════════════════════════════════
codex-oi clean: false (2 findings)
```

## What Claude does next

```
── STRUCTURED FINDINGS ──

| # | Sev | File:Line              | Issue                          | Verify?       |
|---|-----|------------------------|--------------------------------|---------------|
| 1 | P1  | src/services/user.py:34 | None-guard then .lower()      | APPROVED      |
| 2 | P3  | src/api/users.py:12-15 | Dead rate-limit import         | APPROVED      |

── ACTIONABLES ──
- [ ] P1 fix #1 — short-circuit return when username is None (developer)
- [ ] P3 fix #2 — either apply decorator OR drop import (developer)

After applying fixes, re-run:
  codex-oi closeout
Loop until clean exit.
```

## Iteration loop

After the user applies the two fixes:

```
$ ./scripts/codex-oi.sh closeout

═══════════════════════════════════════════════════════════
CODEX SAYS (closeout-local): codex review --uncommitted ...
═══════════════════════════════════════════════════════════
Reviewing 5 lines across 2 files (uncommitted).

# Findings
No accepted findings.

═══════════════════════════════════════════════════════════
codex-oi clean: no accepted/actionable findings reported
```

Exit 0. Closeout is done — safe to commit and ship.
