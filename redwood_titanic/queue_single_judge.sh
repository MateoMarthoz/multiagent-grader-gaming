#!/usr/bin/env bash
# Wait for experiments/single-judge/run-1 to finish, check it worked, then start run-2..run-5 in parallel
# (each under run_guarded.sh). If run-1 didn't work, start nothing and say why. Run from a terminal
# with OPENROUTER_API_KEY set:
#   nohup redwood_titanic/queue_single_judge.sh > experiments/single-judge/queue.log 2>&1 &
# The guards share one key meter, so each $CAP is a cap on the whole batch's spend.
set -uo pipefail
cd "$(dirname "$0")/.."
: "${OPENROUTER_API_KEY:?set OPENROUTER_API_KEY first}"
AXIS=single-judge; FIRST=experiments/$AXIS/run-1; CAP=${CAP:-0.60}
PY=/root/capstone/.venv/bin/python
echo "$(date -u +%H:%M:%S) waiting for $FIRST"
for _ in $(seq 1 120); do   # up to 60 min
  grep -q "finished $AXIS" "$FIRST/guard.log" 2>/dev/null && break
  sleep 30
done
if ! grep -q "finished $AXIS" "$FIRST/guard.log" 2>/dev/null; then
  echo "$(date -u +%H:%M:%S) NOT starting: $FIRST didn't finish within 60 min"; exit 1
fi
if ! "$PY" redwood_titanic/check_single_run.py "$FIRST"; then
  echo "$(date -u +%H:%M:%S) NOT starting runs 2-5: run-1 failed the check above"; exit 1
fi
for n in 2 3 4 5; do
  mkdir -p "experiments/$AXIS/run-$n"
  redwood_titanic/run_guarded.sh "$CAP" run_single_experiment.sh "$AXIS" "run-$n" -T judge=true \
    > "experiments/$AXIS/run-$n/guard.log" 2>&1 &
  echo "$(date -u +%H:%M:%S) started run-$n"
  sleep 5
done
wait
echo "$(date -u +%H:%M:%S) all done"
for n in 2 3 4 5; do tail -1 "experiments/$AXIS/run-$n/guard.log"; done
