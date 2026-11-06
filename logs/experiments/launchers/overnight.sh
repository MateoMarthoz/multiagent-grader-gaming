#!/usr/bin/env bash
# Overnight queue (2026-11-06): runs 2-4 of the six report_agent conditions and of shared-noverify-team
# (21 runs), round-robin, 3 in parallel. Drains the main key, then the second key: before each group it
# starts only as many runs as the current key's remaining limit covers at PER_RUN each.
# Run detached: setsid nohup. Uses bash word splitting for the flags (not zsh).
set -u
cd /root/multiagent-grader-gaming
PER_RUN=0.50
PY=/root/ARENA_materials/.venv/bin/python
MAIN=$OPENROUTER_API_KEY
SECOND=$OPENROUTER_API_KEY_LOCAL
R="-T report_agent=true"; A="$R -T activity_view=true"
jobs=()
for n in 2 3 4; do
  jobs+=("shared-report-agent run-$n -T shared_submission=true $R")
  jobs+=("report-agent run-$n $R")
  jobs+=("competitive-report-agent run-$n -T scoring=competitive $R")
  jobs+=("shared-report-agent-activity run-$n -T shared_submission=true $A")
  jobs+=("report-agent-activity run-$n $A")
  jobs+=("competitive-report-agent-activity run-$n -T scoring=competitive $A")
  jobs+=("shared-noverify-team run-$n -T shared_submission=true -T receivers_score_tool=false -T team_server=true")
done
remaining() { OPENROUTER_API_KEY=$1 "$PY" redwood_titanic/or_usage.py | "$PY" -c "import json,sys; print(json.load(sys.stdin)['limit_remaining'])"; }
keyname=(main second); keys=("$MAIN" "$SECOND"); k=0; i=0
while [ $i -lt ${#jobs[@]} ]; do
  rem=$(remaining "${keys[$k]}")
  n=$("$PY" -c "import math; print(max(0, min(3, math.floor(($rem - 0.05) / $PER_RUN))))")
  left=$(( ${#jobs[@]} - i )); [ $n -gt $left ] && n=$left
  if [ "$n" -lt 1 ]; then
    echo "$(date -u +%H:%M:%S) key ${keyname[$k]} has \$$rem left: not enough for a run"
    if [ $k -eq 0 ]; then k=1; continue; else echo "both keys spent; $left jobs not run"; break; fi
  fi
  cap=$("$PY" -c "print(round($PER_RUN * $n, 2))")
  echo "$(date -u +%H:%M:%S) key ${keyname[$k]} (\$$rem left): starting $n run(s), cap \$$cap"
  for ((j = 0; j < n; j++)); do
    set -- ${jobs[$((i + j))]}; d=$1; r=$2; shift 2
    mkdir -p experiments/$d/$r
    echo "  $d $r $*"
    ( export OPENROUTER_API_KEY="${keys[$k]}" RT_FLOOR_USD=0
      redwood_titanic/run_guarded.sh "$cap" run_experiment.sh "$d" "$r" "$@" > experiments/$d/$r/guard.log 2>&1 ) &
    sleep 15
  done
  wait
  i=$((i + n))
  echo "$(date -u +%H:%M:%S) group done ($i/${#jobs[@]})"
done
echo "ALL DONE $(date -u +%H:%M:%S)"
