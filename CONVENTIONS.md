# CONVENTIONS.md — codex-oi

> Aider-compatible conventions file. Aider auto-loads this when present
> in the project root. See [Aider docs on conventions](https://aider.chat/docs/usage/conventions.html).

This repo IS `codex-oi`. Copy the block below into your own project's
`CONVENTIONS.md` if you want Aider to know when to invoke `codex-oi`
as a second-opinion engine. For the full skill design, see
[SKILL.md](./SKILL.md).

---

## Copy-paste block — drop into your project's `CONVENTIONS.md`

```markdown
## Second-opinion reviews via codex-oi

This project has codex-oi installed. It bridges OpenAI's Codex CLI as
a second AI opinion. When you finish a non-trivial change, before
committing, run:

    ~/.codex-oi/scripts/codex-oi.sh closeout

If the user asks for an "audit", "review", or "second opinion", pick
the right mode:

    ~/.codex-oi/scripts/codex-oi.sh review <file> "<focus>"
    ~/.codex-oi/scripts/codex-oi.sh plan <plan.md>
    ~/.codex-oi/scripts/codex-oi.sh audit       # full project, cost-warned
    ~/.codex-oi/scripts/codex-oi.sh recommit HEAD

Treat output as advisory. Verify every finding against the actual
code before changing anything. Reject speculative findings with a
one-line reason. Do not auto-apply.
```

---

## Why use codex-oi from Aider

Aider already supports `--model` to pick which LLM drives the session,
but switching mid-task is disruptive. `codex-oi` keeps Aider's primary
model in charge and only spawns a Codex turn when you specifically want
a second opinion — typical use is right before commit.

The findings come back as a structured markdown table you can paste
into the chat as "here's what Codex flagged" and let Aider decide what
to fix (subject to your verification).

See [AGENTS.md](./AGENTS.md) for the same pattern in
Antigravity / Cursor / Codex CLI / Claude Code.
