"""Report for a duel_task.py run: result, then one timeline of board posts, submits, team-server
changes and both parties' bash commands (minutes from the start).

    python redwood_titanic/duel_report.py <run-dir>     (uses the newest .eval in it)
"""

from __future__ import annotations

import sys
from pathlib import Path

from inspect_ai.log import read_eval_log


def short(s: str, n: int = 300) -> str:
    s = " ".join(str(s).split())
    return s if len(s) <= n else s[:n] + " ..."


def main(run_dir: str) -> None:
    logs = sorted(Path(run_dir).glob("*.eval"))
    if not logs:
        print(f"no .eval in {run_dir}")
        return
    log = read_eval_log(str(logs[-1]))
    print(f"# {run_dir}\n\nlog: {logs[-1].name}  status: {log.status}")
    if not log.samples or not log.samples[0].scores:
        print("no scored sample")
        if log.error:
            print(log.error.message)
        return
    s = log.samples[0]
    sc = next(iter(s.scores.values()))
    md = sc.metadata
    conf = md["confederate"]
    t0 = s.store.get("rt_t0")
    print(f"\n**{sc.answer}**  ({sc.explanation})\n")
    print("values:", sc.value)
    print("confederate rule (a) flags:", md["confederate_rule_a_flags"] or "none")
    print("killed at end:", len(md["team_killed_at_end"] or []), "processes")
    usage = log.stats.model_usage if log.stats else {}
    for m, u in usage.items():
        print(f"usage {m}: in {u.input_tokens} out {u.output_tokens}")

    ev = []
    for p in md["board"]:
        ev.append((p["time"], f"POST {p['author']}: {short(p['text'], 600)}"))
    for x in md["submit_calls"]:
        ev.append((x["time"], f"SUBMIT {x['agent']} {'ok' if x.get('accepted') else 'FAILED ' + short(x.get('error', ''), 120)}"))
    for c in md["score_checks"]:
        ev.append((c["time"], f"CHECK {c['agent']} {c['target']} f1={c['f1']} by={c.get('shared_by')}"))
    for e in md["team_events"]:
        if "baseline" in e:
            continue
        for a in e.get("added", []):
            ev.append((e["time"], f"TEAM + {short(a, 200)}"))
    for v in md["team_submission_versions"]:
        ev.append((v["time"], f"FILE sha={v.get('sha')} key_of={v.get('key_of')}"))
    # bash commands, attributed to a party through the span tree (each turn runs in span(name))
    spans = {e.id: (e.parent_id, e.name) for e in s.events if getattr(e, "event", None) == "span_begin"}

    def owner(span_id):
        while span_id in spans:
            parent, name = spans[span_id]
            if name in md["parties"]:
                return name
            span_id = parent
        return "?"

    def resolve(v):
        # Inspect stores large tool args as attachment://<hash> references
        if isinstance(v, str) and v.startswith("attachment://"):
            return (s.attachments or {}).get(v[len("attachment://"):], v)
        return v

    for e in s.events:
        if getattr(e, "event", None) == "tool" and e.function == "bash":
            ev.append((e.timestamp.timestamp(), f"BASH {owner(e.span_id)}: {short(resolve(e.arguments.get('command', '')), 400)}"))
    print("\n## Timeline\n")
    for t, line in sorted(ev):
        print(f"{(t - t0) / 60:6.2f}  {line}")


if __name__ == "__main__":
    main(sys.argv[1])
