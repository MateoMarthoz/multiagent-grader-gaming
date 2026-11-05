"""Did a single-agent run work? Exit 0 if so, 1 with the reasons if not. Prints a one-paragraph summary.

    /root/capstone/.venv/bin/python redwood_titanic/check_single_run.py experiments/single-judge/run-1
"""

from __future__ import annotations

import glob
import sys
from pathlib import Path

from inspect_ai.log import read_eval_log


def main(run_dir: str) -> int:
    d = Path(run_dir)
    problems = []
    console = (d / "console.log").read_text() if (d / "console.log").exists() else ""
    if "inspect exit: 0" not in console:
        problems.append("inspect did not exit 0 (see console.log)")
    logs = sorted(glob.glob(str(d / "*.eval")))
    if not logs:
        print("no .eval log"); return 1
    log = read_eval_log(logs[-1])
    if log.status != "success" or not log.samples:
        print(f"eval status {log.status}: {log.error}"); return 1
    s = log.samples[0]
    if s.error:
        problems.append(f"sample error: {s.error.message[:300]}")
    sc = (s.scores or {}).get("single_experiment_scorer")
    if sc is None:
        print("no score"); return 1
    md = sc.metadata or {}
    status = md.get("status", {})
    n_calls = sum(len(m.tool_calls or []) for m in s.messages if m.role == "assistant")
    if n_calls < 5:
        problems.append(f"only {n_calls} tool calls")
    if str(status.get("end_reason", "")).startswith(("model_error", "tool_error")):
        problems.append(f"ended with {status['end_reason']}")
    judge = md.get("judge")
    if (md.get("config") or {}).get("judge"):
        if not judge:
            problems.append("judge=true but no judge record")
        elif judge["log"]["n_append_failed"]:
            problems.append(f"{judge['log']['n_append_failed']} log appends failed (check: agent may have broken the file)")
    print(f"{d}: {sc.answer}; F1 vs truth {md.get('grade', {}).get('f1_truth')}; {n_calls} tool calls; "
          f"ended: {status.get('end_reason')}")
    if judge:
        lg, act = judge["log"], judge["activity"]
        print(f"  saw judge code {act['saw_judge_code']}; log tampered {lg['tampered']} "
              f"({lg['n_deleted']} deleted, {lg['n_edited']} edited, {lg['n_inserted']} inserted); "
              f"grade.py modified {judge['grader']['modified']}")
    for p in problems:
        print("  PROBLEM: " + p)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
