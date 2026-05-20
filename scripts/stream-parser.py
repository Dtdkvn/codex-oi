#!/usr/bin/env python3
"""
codex-oi stream parser.

Reads Codex CLI JSON-lines output on stdin and emits a clean
human-readable stream on stdout. Surfaces reasoning, agent messages,
command runs, and token counts; drops framing noise.

Exit code mirrors the upstream Codex turn outcome:
  0  — turn.completed seen, no error
  1  — JSON parse error or no completion seen
  2  — Codex reported an error event
"""
from __future__ import annotations

import json
import sys


def main() -> int:
    saw_completion = False
    saw_error = False
    total_tokens = 0

    for raw in sys.stdin:
        line = raw.strip()
        if not line:
            continue
        try:
            obj = json.loads(line)
        except json.JSONDecodeError:
            # Pass-through non-JSON lines (some Codex versions interleave plain text)
            print(line, flush=True)
            continue

        t = obj.get("type", "")

        if t == "item.completed" and "item" in obj:
            item = obj["item"]
            itype = item.get("type", "")
            text = item.get("text", "")

            if itype == "reasoning" and text:
                snippet = text[:300]
                print(f"[codex thinking] {snippet}", flush=True)
                print(flush=True)

            elif itype == "agent_message" and text:
                print(text, flush=True)

            elif itype == "command_execution":
                cmd = item.get("command", "")
                if cmd:
                    print(f"[codex ran] {cmd[:200]}", flush=True)

        elif t == "turn.completed":
            saw_completion = True
            usage = obj.get("usage", {}) or {}
            total_tokens = int(usage.get("input_tokens", 0) or 0) + int(
                usage.get("output_tokens", 0) or 0
            )
            if total_tokens:
                print(f"\n=== tokens: {total_tokens} ===", flush=True)

        elif t == "error":
            saw_error = True
            msg = obj.get("message", "(no message)")
            print(f"[codex error] {msg}", flush=True, file=sys.stderr)

    if saw_error:
        return 2
    if not saw_completion:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
