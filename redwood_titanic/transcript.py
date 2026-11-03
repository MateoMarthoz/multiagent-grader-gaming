"""Print a condensed transcript of one trial for manual review.

    /root/capstone/.venv/bin/python redwood_titanic/transcript.py logs/redwood-titanic/trial-1 [max_chars] [epoch]

Each assistant turn: reasoning (clipped), text, bash command; each tool result (clipped).
"""

from __future__ import annotations

import glob
import sys

from inspect_ai.log import read_eval_log
from inspect_ai.model import ContentReasoning, ContentText


def clip(s: str, n: int) -> str:
    s = (s or "").strip()
    return s if len(s) <= n else s[: n // 2] + f"\n …[{len(s) - n} chars cut]… \n" + s[-n // 2 :]


def main(log_dir: str, n: int = 1200, epoch: int = 1) -> None:
    log = read_eval_log(sorted(glob.glob(f"{log_dir}/*.eval"))[-1])
    s = next(x for x in log.samples if x.epoch == epoch)
    for i, m in enumerate(s.messages):
        if m.role == "user":
            print(f"[{i}] USER: {clip(m.text, n)}")
        elif m.role == "assistant":
            parts = m.content if isinstance(m.content, list) else [ContentText(text=m.content or "")]
            for p in parts:
                if isinstance(p, ContentReasoning):
                    print(f"[{i}] REASONING: {clip(p.reasoning or p.summary or '', n)}")
                elif isinstance(p, ContentText) and p.text.strip():
                    print(f"[{i}] TEXT: {clip(p.text, n)}")
            for tc in m.tool_calls or []:
                args = tc.arguments or {}
                print(f"[{i}] CALL: {clip(str(args.get('command') or args.get('cmd') or args), n)}")
        elif m.role == "tool":
            print(f"[{i}] OUT: {clip(m.text, n // 2)}" + (f"  ERROR: {m.error.message}" if m.error else ""))
        print()


if __name__ == "__main__":
    main(sys.argv[1], int(sys.argv[2]) if len(sys.argv) > 2 else 1200, int(sys.argv[3]) if len(sys.argv) > 3 else 1)
