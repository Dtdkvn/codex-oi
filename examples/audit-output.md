# Example: `codex-oi audit`

Output from running `./scripts/codex-oi.sh audit` against a small Python
Flask app. Trimmed for readability.

```
codex-oi: Full audit is heavy.
  Effort: high
  Expected: 50k–8M tokens, 5–15 minutes
  Cost (Codex API): roughly $0.30–$1.00 depending on repo size

Press ENTER to continue, Ctrl-C to abort.

═══════════════════════════════════════════════════════════
CODEX SAYS (audit):
═══════════════════════════════════════════════════════════
[codex thinking] Scanning repo structure. Sees src/app.py, src/models/, src/api/,
tests/. CLAUDE.md describes a Flask + SQLAlchemy stack with JWT auth. Will sweep
security first, then arch drift, then anti-patterns.

[codex ran] rg -n "exec\(|eval\(|os\.system" src/

[codex ran] rg -n "SECRET|TOKEN|PASSWORD" src/ --type py

# AUDIT FINDINGS

## P1 — must fix before next ship
- [P1] src/api/auth.py:42 — SECRET_KEY falls back to literal "dev-only-secret"
  when env var is missing — fix: raise on startup instead of silent fallback
- [P1] src/api/users.py:88 — raw SQL string interpolation in search endpoint
  (`f"WHERE name LIKE '{q}%'"`) — fix: use parameterised query
- [P1] src/models/session.py:15 — JWT decode does not pin algorithm, accepts
  any incl. `none` — fix: pass `algorithms=["HS256"]` explicitly

## P2 — should fix this sprint
- [P2] src/api/upload.py:31 — uploaded filename passed to `os.path.join` without
  `werkzeug.secure_filename` — path traversal risk
- [P2] src/db/session.py:22 — engine created with `echo=True` in prod codepath
  — leaks SQL to stdout
- [P2] tests/test_auth.py:50 — test asserts nothing (no `assert` statements);
  passes vacuously

## P3 — nice to have
- [P3] src/app.py:18 — `debug=True` hardcoded; should read from FLASK_ENV
- [P3] src/api/*.py — 6 modules import `requests` but never set a timeout

## SUMMARY
Total: 8 findings (3 P1 / 3 P2 / 2 P3).
Dominant theme: auth/session hardening (P1 cluster around SECRET_KEY + JWT alg
pinning + SQL injection). Biggest risk class: silent credential fallback on
startup (issue #1). Recommend addressing all P1s before next deploy.

═══════════════════════════════════════════════════════════
=== tokens: 412857 ===
```

## What Claude does next

After the raw Codex block, Claude builds the structured findings table and
actionables. The user decides each one — Claude never auto-applies.

```
── STRUCTURED FINDINGS ──

| # | Sev | File:Line              | Issue                          | Verify?       |
|---|-----|------------------------|--------------------------------|---------------|
| 1 | P1  | src/api/auth.py:42     | SECRET_KEY dev fallback        | NEED VERIFY   |
| 2 | P1  | src/api/users.py:88    | SQL string interpolation       | APPROVED      |
| 3 | P1  | src/models/session.py:15 | JWT alg not pinned           | APPROVED      |
| 4 | P2  | src/api/upload.py:31   | Path traversal risk            | NEED VERIFY   |
| 5 | P2  | src/db/session.py:22   | SQL echo in prod path          | NEED VERIFY   |
| 6 | P2  | tests/test_auth.py:50  | Test asserts nothing           | APPROVED      |
| 7 | P3  | src/app.py:18          | debug=True hardcoded           | APPROVED      |
| 8 | P3  | src/api/*.py           | requests w/o timeout           | NEED VERIFY   |

Aligned with documented intent? Mostly yes — three P1s drift from the
"never ship dev secrets" rule in CLAUDE.md.

── ACTIONABLES ──
- [ ] P1 fix #2 SQL injection (developer — single-line param fix)
- [ ] P1 fix #3 JWT algorithm pin (developer — one-line fix)
- [ ] P1 verify #1 — does prod env always set SECRET_KEY? (user)
- [ ] P2 batch #4-#6 — group into "test + upload hardening" branch (developer)
- [ ] P3 batch #7-#8 — sprint backlog
```
