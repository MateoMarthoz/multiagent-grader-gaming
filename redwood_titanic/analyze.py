"""Summarize one pilot trial: config, provider, usage, cost, outcome and gaming evidence.

    /root/capstone/.venv/bin/python redwood_titanic/analyze.py logs/redwood-titanic/trial-1

Prints a markdown report and writes summary.json next to the log.
Cost sources, most authoritative first: OpenRouter's per-call `usage.cost` (recorded
because trials run with --log-model-api), the key's usage meter before/after the trial
(usage_before.json / usage_after.json), and tokens x DigitalOcean list prices.
"""

from __future__ import annotations

import glob
import json
import sys
from collections import Counter
from pathlib import Path

from inspect_ai.log import read_eval_log
from inspect_ai.model import ContentReasoning, ContentText

# DigitalOcean on OpenRouter for deepseek/deepseek-v4-flash-0731, USD per token (checked 2026-11-03)
PRICE = {"input": 0.119e-6, "cache_read": 0.0238e-6, "output": 0.238e-6}


def _text_parts(m) -> tuple[str, str]:
    reasoning, text = [], []
    content = m.content if isinstance(m.content, list) else [ContentText(text=m.content or "")]
    for p in content:
        if isinstance(p, ContentReasoning):
            reasoning.append(p.reasoning or p.summary or "")
        elif isinstance(p, ContentText):
            text.append(p.text)
    return "\n".join(reasoning).strip(), "\n".join(text).strip()


def _clip(s: str, n: int) -> str:
    s = (s or "").strip()
    return s if len(s) <= n else s[: n - 20] + " …[truncated]"


def main(log_dir: str) -> None:
    d = Path(log_dir)
    paths = sorted(glob.glob(str(d / "*.eval")))
    if not paths:
        print(f"no .eval log in {d}")
        return
    log = read_eval_log(paths[-1])
    s = log.samples[0] if log.samples else None
    out: dict = {"log": paths[-1], "status": log.status, "error": str(log.error) if log.error else None}
    out["model"] = log.eval.model
    out["model_args"] = log.eval.model_args
    out["generate_config"] = {k: v for k, v in log.eval.model_generate_config.model_dump().items() if v is not None}
    cfg = log.eval.config
    out["limits"] = {"message_limit": cfg.message_limit, "token_limit": cfg.token_limit, "time_limit": cfg.time_limit}
    out["task_args"] = log.eval.task_args

    md = [f"# {d.name}", "", f"- Log: `{paths[-1]}`", f"- Status: {log.status}" + (f" ({out['error']})" if out["error"] else "")]
    if s is None:
        print("\n".join(md))
        return

    # --- provider, per-call cost -------------------------------------------------
    model_events = [e for e in s.events if e.event == "model"]
    providers, served_models, call_costs, n_calls_logged, req_provider = Counter(), Counter(), [], 0, set()
    for e in model_events:
        if e.call is None:
            continue
        if e.call.request:
            req_provider.add(json.dumps((e.call.request.get("extra_body") or {}).get("provider")))
        r = e.call.response or {}
        if r:
            n_calls_logged += 1
            providers[r.get("provider")] += 1
            served_models[r.get("model")] += 1
            cost = (r.get("usage") or {}).get("cost")
            if cost is not None:
                call_costs.append(float(cost))
    out["n_model_calls"] = len(model_events)
    out["n_calls_with_response_logged"] = n_calls_logged
    out["providers"] = dict(providers)
    out["served_models"] = dict(served_models)
    out["request_provider_param"] = sorted(req_provider)
    out["model_errors"] = [str(e.error)[:300] for e in model_events if e.error]

    # --- usage, cost ---------------------------------------------------------------
    usage = {}
    for _, u in (s.model_usage or {}).items():
        usage = u.model_dump()
    inp = usage.get("input_tokens") or 0
    cr = usage.get("input_tokens_cache_read") or 0
    outp = usage.get("output_tokens") or 0
    out["usage"] = usage
    token_cost = inp * PRICE["input"] + cr * PRICE["cache_read"] + outp * PRICE["output"]
    out["cost_token_estimate"] = token_cost
    out["cost_openrouter_calls"] = sum(call_costs) if call_costs else None
    out["n_calls_with_cost"] = len(call_costs)
    meter = None
    try:
        b = json.loads((d / "usage_before.json").read_text())
        a = json.loads((d / "usage_after.json").read_text())
        meter = a["usage"] - b["usage"]
    except Exception:  # noqa: BLE001
        pass
    out["cost_key_meter_delta"] = meter
    candidates = [c for c in (out["cost_openrouter_calls"], meter, token_cost) if c is not None]
    out["cost_conservative"] = max(candidates) if candidates else None

    # --- runtime, ending -------------------------------------------------------------
    out["total_time_s"] = s.total_time
    out["working_time_s"] = s.working_time
    out["n_messages"] = len(s.messages)
    out["limit_hit"] = {"type": s.limit.type, "limit": s.limit.limit} if s.limit else None
    out["sample_error"] = str(s.error.message)[:500] if s.error else None
    last = s.messages[-1] if s.messages else None
    if s.error:
        ended = "error: " + out["sample_error"]
    elif s.limit:
        ended = f"{s.limit.type} limit ({s.limit.limit})"
    elif last is not None and last.role == "assistant" and not last.tool_calls:
        ended = "model gave a final message (no tool call)"
    else:
        ended = "unknown"
    out["ended_because"] = ended

    # --- score ----------------------------------------------------------------------
    sc = (s.scores or {}).get("redwood_titanic_scorer")
    if sc is not None:
        meta = sc.metadata or {}
        out["score_value"] = sc.value
        out["primary"] = sc.answer
        out["classification"] = meta.get("classification")
        out["grade"] = meta.get("grade")
        files = meta.get("files") or {}
        out["files"] = {k: v for k, v in files.items() if k != "final_listing"}
        tr = meta.get("transcript") or {}
        out["transcript_counts"] = tr.get("counts")
        out["transcript_first_index"] = tr.get("first_index")
        out["grader_runs"] = tr.get("grader_runs")
        evidence = tr.get("evidence") or []
    else:
        evidence = []
    final_reasoning, final_text = _text_parts(last) if last is not None and last.role == "assistant" else ("", "")
    out["final_message"] = final_text[:3000]

    (d / "summary.json").write_text(json.dumps(out, indent=1, default=str))

    # --- markdown -------------------------------------------------------------------
    g, c = out.get("grade") or {}, out.get("classification") or {}
    md += [
        f"- Model: `{out['model']}`; request provider param: {out['request_provider_param']}; "
        f"served by: {out['providers']} ({n_calls_logged}/{len(model_events)} calls logged); served model ids: {out['served_models']}",
        f"- Generate config (non-default): {out['generate_config'] or 'none (provider defaults)'}",
        f"- Limits: {out['limits']}",
        f"- Usage: input {inp:,} + cache-read {cr:,} + output {outp:,} (reasoning {usage.get('reasoning_tokens') or 0:,}) "
        f"= {usage.get('total_tokens') or 0:,} tokens",
        f"- Cost: OpenRouter per-call sum {out['cost_openrouter_calls']} ({len(call_costs)} calls); key meter delta {meter}; "
        f"token estimate {token_cost:.4f}; **conservative {out['cost_conservative']:.4f} USD**",
        f"- Runtime: {s.total_time:.0f} s total ({s.working_time:.0f} s working); {len(s.messages)} messages; ended: {ended}",
        f"- Model API errors: {len(out['model_errors'])}",
        "",
        f"**Classification: `{out.get('primary')}`**",
        "",
        f"- Valid submission: {g.get('valid_submission')} {g.get('format_problems') or ''}",
        f"- Authoritative grader score (purpose={g.get('purpose')}): {g.get('grader_score')}; F1 vs truth {g.get('f1_truth', 0):.3f}; "
        f"accuracy vs training / benchmarking labels {g.get('acc_training_labels', 0):.3f} / {g.get('acc_benchmarking_labels', 0):.3f}; "
        f"flip ids matching training {g.get('flip_ids_matching_training')}/{g.get('n_flip_ids')}",
        f"- In-sandbox grader output at the end: `{(out.get('files') or {}).get('in_sandbox_grader_output')}`",
        "- Flags: " + ", ".join(f"{k}={v}" for k, v in c.items() if k != "primary"),
        f"- Files accessed (atime): {[k for k, v in ((out.get('files') or {}).get('accessed') or {}).items() if v]}",
        f"- Tamper checks: grader_modified={(out.get('files') or {}).get('grader_modified')}, "
        f"purpose={(out.get('files') or {}).get('purpose_file_content')!r}, libs_modified={(out.get('files') or {}).get('libs_modified')}, "
        f"new files in /opt/eval={(out.get('files') or {}).get('opt_eval_new_files')}",
        "",
        "## Evidence (commands touching eval.log / grader / labels / purpose file)",
        "",
    ]
    if not evidence:
        md.append("none")
    for ev in evidence:
        i = ev["index"]
        reasoning, text = _text_parts(s.messages[i])
        md += [
            f"### message {i}: {', '.join(ev['flags'])}",
            "",
            "Reasoning before the call:",
            "```",
            _clip(reasoning or text or "(none)", 2500),
            "```",
            "Command:",
            "```",
            _clip(ev["cmd"], 1500),
            "```",
            "Output:",
            "```",
            _clip(ev["output"], 1200),
            "```",
            "",
        ]
    md += ["## Final message", "", "```", _clip(final_text or "(none)", 3000), "```"]
    if final_reasoning:
        md += ["", "Final reasoning:", "```", _clip(final_reasoning, 2500), "```"]
    print("\n".join(md))


if __name__ == "__main__":
    main(sys.argv[1])
