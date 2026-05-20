# Example: `codex-oi plan docs/feature-x-plan.md`

Output from challenging a feature plan before any code is written.

## The plan being challenged

```markdown
# Feature X — Background CSV export

## Goal
Let users export large query results as CSV in the background.

## Steps
1. Add `/api/exports` POST endpoint (creates job, returns job_id)
2. Run query in a Celery task
3. Stream CSV to S3
4. Email user a presigned URL
5. Add `/api/exports/{id}` GET to check status

## Acceptance
- 100k-row export completes in under 5 min
- User gets email within 10 sec of job completion
```

## Codex output

```
═══════════════════════════════════════════════════════════
CODEX SAYS (plan):
═══════════════════════════════════════════════════════════
[codex thinking] Plan looks reasonable on surface. Let me read referenced source
to find conflicts. Will probe: existing /api/exports handler? Celery config?
S3 client wrapper? Email service?

[codex ran] rg -n "exports" src/api/

[codex ran] cat src/services/celery_app.py

# Plan challenge

## Logical gaps

1. **No mention of query cancellation.** Step 2 launches a Celery task but
   step 5 only checks status. What if the user closes the tab and a 100k-row
   query is still running? Add a DELETE endpoint or a TTL on the job row.

2. **Step 4 ("email user a presigned URL") leaks the URL to anyone with
   inbox access.** Acceptable for some products, not all. Decide: is the URL
   single-use? Time-limited? Behind auth? Plan doesn't say.

3. **Job_id space not specified.** Sequential integers leak job rate to
   anyone who can hit `/api/exports/{id}`. Use UUIDv4 or signed token.

## Unstated assumptions

4. **Plan assumes Celery is configured.** Repo has `src/services/celery_app.py`
   but it's set up for `redis://localhost`. No prod broker configured. Plan
   should call out the infra gap.

5. **"Stream CSV to S3" — which library?** boto3 multipart upload? s3fs?
   Plan assumes someone knows. Lock it in.

6. **No backpressure / concurrent-job limit.** A user could fire 50 export
   jobs simultaneously. Plan needs a per-user rate limit or queue cap.

## Missing error handling

7. **Step 2 → step 3 transition has no failure path.** If the query succeeds
   but S3 upload fails, what's the job status? "completed_no_artifact"?
   The plan only has happy-path states.

8. **Step 4 email failure.** If SendGrid is down, does the job retry forever?
   Plan needs a retry policy + dead-letter behaviour.

## Drift from documented intent

9. **CLAUDE.md says "no new infra without devops sign-off".** Plan adds a
   hard Celery + Redis + S3 + email dependency chain. Worth a heads-up
   conversation before any of step 1 ships.

## Sequencing concerns

10. **Steps 1+2 should be split.** Ship the synchronous endpoint first with
    a 30-sec timeout to validate the query / CSV / S3 path. Then add Celery
    once you know the format is right. Otherwise you debug 4 layers at once.

═══════════════════════════════════════════════════════════
=== tokens: 38421 ===
```

## What Claude does next

```
── STRUCTURED FINDINGS ──

| # | Sev | Concern                                    | Verify?       |
|---|-----|--------------------------------------------|---------------|
| 1 | P1  | No job cancellation path                   | APPROVED      |
| 2 | P1  | Presigned URL via email — auth model unset | NEED DECISION |
| 3 | P1  | job_id enumeration risk                    | APPROVED      |
| 4 | P2  | Celery broker not prod-configured          | APPROVED      |
| 5 | P2  | S3 upload library not chosen               | NEED DECISION |
| 6 | P2  | No concurrent-job limit                    | APPROVED      |
| 7 | P2  | S3 failure path missing                    | APPROVED      |
| 8 | P2  | Email retry policy missing                 | APPROVED      |
| 9 | P1  | Drift from "no new infra without devops"   | NEED DECISION |
| 10| P2  | Ship sync first, then async                | NEED DECISION |

── ACTIONABLES ──
- [ ] DECISION: presigned URL auth model (#2) — product owner
- [ ] DECISION: devops sign-off on Celery+Redis+S3 (#9) — devops
- [ ] DECISION: ship sync-first vs full async (#10) — tech lead
- [ ] PLAN REV: rewrite plan with cancellation + job_id + error paths
- [ ] Defer code work until DECISIONS resolved

The user said wait on decisions before any code. Plan goes back to the
author for revision.
```

This is the highest-leverage use of `codex-oi`: catch ten plan-level gaps
in 40k tokens instead of finding them after 2 weeks of implementation.
