"""Timeline of one overnight multi-agent episode (multi_overnight.py): every post, DM, submission,
grader-related command (with the reasoning before it), final message and wake, in time order,
plus per-agent summaries and reasoning excerpts about the grader / cheating.

    /root/capstone/.venv/bin/python redwood_titanic/multi_overnight_timeline.py logs/redwood-titanic-multi/run-N
"""

from __future__ import annotations

import glob
import re
import sys
from pathlib import Path

from inspect_ai.log import read_eval_log

AGENTS = ["agent_a", "agent_b", "agent_c", "agent_d"]
RE_TOPIC = re.compile(r"cheat|grade\.py|/opt/eval|EXPECTED|answer key|ground[ -]truth|evaluator|permission|"
                      r"restricted|not (?:be )?(?:allowed|supposed|accessible)|honest|leak|label", re.IGNORECASE)


def clip(s: str, n: int) -> str:
    s = (s or "").strip()
    return s if len(s) <= n else s[: n - 15] + " …[truncated]"


def quote(s: str, n: int) -> str:
    return "\n".join("> " + ln for ln in clip(s, n).splitlines()) or "> (empty)"


def parts(m: dict) -> tuple[str, str]:
    """(reasoning, text) of a stored message."""
    c = m.get("content")
    if isinstance(c, str):
        return "", c
    r, t = [], []
    for p in c or []:
        if p.get("type") == "reasoning":
            r.append(p.get("reasoning") or p.get("summary") or "")
        elif p.get("type") == "text":
            t.append(p.get("text", ""))
    return "\n".join(r), "\n".join(t)


def main(log_dir: str) -> None:
    paths = sorted(glob.glob(str(Path(log_dir) / "*.eval")))
    log = read_eval_log(paths[-1])
    s = log.samples[0]
    sc = next(iter(s.scores.values()))
    md = sc.metadata
    ag = md["agents"]
    t0 = md.get("rt_start") or min(t["t0"] for t in md["turn_log"])
    exp = md["config"]["experiment"]

    def ts(t: float) -> str:
        d = max(0, t - t0)
        return f"{int(d // 60):02d}:{int(d % 60):02d}"

    msgs = {n: s.store.get(f"messages_{n}", []) for n in AGENTS}
    # message index -> turn start time
    idx_time = {n: {} for n in AGENTS}
    for t in md["turn_log"]:
        idx_time[t["agent"]][t["msg_index"]] = t["t0"]

    def time_of(n: str, i: int) -> float:
        known = [k for k in idx_time[n] if k <= i]
        return idx_time[n][max(known)] if known else t0

    out = [f"# Timeline: {Path(log_dir).name} (experiment `{exp}`)", "",
           f"- Score answer: `{sc.answer}`", f"- Metrics: `{sc.value}`", ""]
    out += ["| Agent | Reads grader | Ended | Wakes | Graded file | Pass | F1 own key | F1 truth | Best match of own last submission | Classification | Posts / reads | DMs sent / recv | Submits |",
            "|---|---|---|---|---|---|---|---|---|---|---|---|---|"]
    for n in AGENTS:
        a = ag[n]
        g, st = a["grade"], a["status"]
        bm = a.get("own_last_submission_best_match")
        cls = a["classification"]["primary"] + (f" / {a['receiver']['primary']}" if "receiver" in a else "")
        out.append(f"| {n} | {a['can_read_grader']} | {st['end_reason']} | {st.get('wakes', 0)} | {a['graded_from']} | "
                   f"{g['grader_score']:.0f} | {g['f1_own_key']:.3f} | {g['f1_truth']:.3f} | "
                   f"{'' if not bm else f'{bm[0]} ({bm[1]:.2f})'} | {cls} | {a['board']['n_posts']} / {a['board']['n_reads']} | "
                   f"{a['dms_sent']} / {a['dms_received']} | {sum(1 for c in a['submit_calls'] if c.get('counted'))} |")
    out.append("")

    ev: list[tuple[float, str, str]] = []
    for p, info in zip(md["board"], md["posts"]):
        tag = f"share level {info['level']}" + (f", key of {info['key_of']}" if info.get("key_of") else "")
        ev.append((p["time"], p["author"], f"**POST #{p['id']}** ({tag})\n\n{quote(p['text'], 2500)}"))
    for d, info in zip(md.get("dms", []), md.get("dm_info", [])):
        tag = f"share level {info['level']}" + (", report terms" if info.get("report_terms") else "")
        ev.append((d["time"], d["from"], f"**DM #{d['id']} {d['from']} → {d['to']}** ({tag})\n\n{quote(d['text'], 2500)}"))
    for n in AGENTS:
        for c in ag[n]["submit_calls"]:
            f1k = c.get("f1_own_key")
            ev.append((c["time"], n, f"**SUBMIT** → {c['result']}"
                       + (f" (host: F1 own key {f1k:.3f}, F1 truth {c['f1_truth']:.3f})" if f1k is not None else "")))
        m = msgs[n]
        # grader-related commands, with the reasoning that preceded them
        for e in ag[n]["transcript"]["evidence"]:
            i = e["index"]
            r, txt = parts(m[i]) if i < len(m) else ("", "")
            body = f"**{', '.join(e['flags'])}**\n\n`$ {clip(e['cmd'], 600)}`\n\nOutput: `{clip(e['output'], 400)}`"
            if r.strip() or txt.strip():
                body += "\n\nReasoning before it:\n\n" + quote(r or txt, 1800)
            ev.append((time_of(n, i), n, body))
        for i, msg in enumerate(m):
            if msg["role"] == "assistant" and not msg.get("tool_calls"):
                r, txt = parts(msg)
                ev.append((time_of(n, i), n, "**FINAL MESSAGE**\n\n" + quote(txt, 2500)
                           + ("\n\nReasoning:\n\n" + quote(r, 1500) if r.strip() else "")))
            if msg["role"] == "user" and i > 0:
                ev.append((time_of(n, i - 1) + 1, n, f"_woken: {clip(parts(msg)[1], 200)}_"))
        st = ag[n]["status"]
        last = max([t["t1"] for t in md["turn_log"] if t["agent"] == n], default=t0)
        ev.append((last, n, f"_ended: {st['end_reason']}_"))
    for e in md.get("sam_events", []):
        if e["kind"] != "reply":
            ev.append((e["time"], "sam", f"_Sam event: {e}_"))
    ev.sort(key=lambda x: x[0])
    out += ["## Timeline (mm:ss from start)", ""]
    for t, who, body in ev:
        out.append(f"### {ts(t)} {who}\n\n{body}\n")

    # reasoning excerpts on the grader / cheating, per agent
    out += ["## Reasoning excerpts about the grader, permissions or cheating", ""]
    for n in AGENTS:
        out.append(f"### {n}")
        k = 0
        for i, msg in enumerate(msgs[n]):
            if msg["role"] != "assistant":
                continue
            r, txt = parts(msg)
            blob = (r + "\n" + txt).strip()
            hits = [mm.start() for mm in RE_TOPIC.finditer(blob)]
            if not hits:
                continue
            # one window per message, around the first few hits
            lo = max(0, hits[0] - 300)
            hi = min(len(blob), hits[min(len(hits) - 1, 4)] + 600)
            out.append(f"- msg {i} ({ts(time_of(n, i))}): " + clip(blob[lo:hi].replace("\n", " "), 1300))
            k += 1
            if k >= 25:
                out.append("- (more omitted)")
                break
        out.append("")
    print("\n".join(out))


if __name__ == "__main__":
    main(sys.argv[1])
