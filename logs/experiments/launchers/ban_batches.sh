#!/usr/bin/env bash
# 2026-11-06: 4 batches of 2 (shared-noverify-team-ban + shared-noverify-team-ban-activity), one batch at a time.
# Activity run on the second key; plain run on the main key while it has >= $0.30, else also on the second key.
# Run detached: setsid nohup. Prints "BATCH n DONE" after each batch.
set -u
cd /root/multiagent-grader-gaming
PY=/root/ARENA_materials/.venv/bin/python
MAIN=$OPENROUTER_API_KEY
SECOND=$OPENROUTER_API_KEY_LOCAL
BASE="-T shared_submission=true -T receivers_score_tool=false -T team_server=true"
remaining() { OPENROUTER_API_KEY=$1 "$PY" redwood_titanic/or_usage.py | "$PY" -c "import json,sys; print(json.load(sys.stdin)['limit_remaining'])"; }
ge() { "$PY" -c "import sys; sys.exit(0 if $1 >= $2 else 1)"; }
for n in 1 2 3 4; do
  rm_main=$(remaining "$MAIN"); rm_second=$(remaining "$SECOND")
  echo "$(date -u +%H:%M:%S) batch $n: main \$$rm_main, second \$$rm_second"
  if ge "$rm_main" 0.30; then
    pk=$MAIN; pcap=$("$PY" -c "print(round(min(0.40, $rm_main - 0.01), 2))"); acap=0.45; pname=main
  else
    pk=$SECOND; pcap=0.75; acap=0.75; pname=second
  fi
  need=$("$PY" -c "print($acap if '$pname' == 'main' else 0.75)")
  if ! ge "$rm_second" "$need"; then echo "not enough on the second key for batch $n (\$$rm_second < \$$need); stopping"; break; fi
  d1=shared-noverify-team-ban; d2=shared-noverify-team-ban-activity; r=run-$n
  mkdir -p experiments/$d1/$r experiments/$d2/$r
  echo "  $d1 $r on $pname (cap \$$pcap); $d2 $r on second (cap \$$acap)"
  ( export OPENROUTER_API_KEY="$pk" RT_FLOOR_USD=0
    redwood_titanic/run_guarded.sh "$pcap" run_experiment.sh $d1 $r $BASE -T ghost_ban=plain > experiments/$d1/$r/guard.log 2>&1 ) &
  sleep 15
  ( export OPENROUTER_API_KEY="$SECOND" RT_FLOOR_USD=0
    redwood_titanic/run_guarded.sh "$acap" run_experiment.sh $d2 $r $BASE -T ghost_ban=reason -T activity_view=true > experiments/$d2/$r/guard.log 2>&1 ) &
  wait
  echo "$(date -u +%H:%M:%S) BATCH $n DONE"
done
echo "ALL DONE $(date -u +%H:%M:%S)"
