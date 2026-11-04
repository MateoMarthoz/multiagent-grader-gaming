#!/usr/bin/env bash
# Run one trial/episode under a spend cap. Polls the OpenRouter key meter every 60 s; if this
# run's spend (meter delta, which also counts anything else on the same key, so it errs high)
# passes CAP_USD, sends SIGINT to the eval so Inspect stops and writes its log, and the runner
# then writes the report as usual. Refuses to start if the key's remaining limit minus CAP_USD
# would fall below RT_FLOOR_USD (default 2).
# Usage: redwood_titanic/run_guarded.sh <cap-usd> <run_experiment.sh|run_multi.sh|run_trial.sh|run_confederate.sh> <runner args...>
#   (run_experiment.sh takes <axis-folder> <run-name>; the others take <run-name>)
#   RT_MODEL=openrouter/qwen/qwen3-235b-a22b-2507 RT_PROVIDER='{"order":["Venice"],"allow_fallbacks":false}' \
#     redwood_titanic/run_guarded.sh 1.00 run_multi.sh qwen-instruct-cap5-thr -T assistant_name=Qwen ...
set -uo pipefail
CAP=$1; RUNNER=$2; shift 2
cd "$(dirname "$0")/.."
: "${OPENROUTER_API_KEY:?set OPENROUTER_API_KEY first}"
PY=/root/capstone/.venv/bin/python
FLOOR=${RT_FLOOR_USD:-2}
meter() { "$PY" redwood_titanic/or_usage.py | "$PY" -c "import json,sys; d=json.load(sys.stdin); print(d['usage'], d['limit_remaining'])"; }
read -r START REMAINING < <(meter)
if ! "$PY" -c "float('$START')" 2>/dev/null; then
  echo "$(date -u +%H:%M:%S) refusing: couldn't read the key's spend meter (got '$START')"; exit 3
fi
if [ "$REMAINING" = "None" ]; then
  # a key without a spending limit reports no remaining amount: nothing to keep a floor under
  echo "$(date -u +%H:%M:%S) key has no spending limit: skipping the floor check (the \$$CAP cap still applies)"
elif "$PY" -c "import sys; sys.exit(0 if $REMAINING - $CAP >= $FLOOR else 1)"; then :; else
  echo "$(date -u +%H:%M:%S) refusing: remaining \$$REMAINING - cap \$$CAP < floor \$$FLOOR"; exit 3
fi
case "$RUNNER" in
  run_multi.sh) PATTERN="inspect eval redwood_titanic/multi_task.py" ;;
  run_experiment.sh) PATTERN="inspect eval redwood_titanic/experiment.py" ;;
  run_trial.sh) PATTERN="inspect eval redwood_titanic/task.py" ;;
  run_confederate.sh) PATTERN="redwood_titanic/run_confederate.py" ;;
  *) echo "unknown runner $RUNNER"; exit 2 ;;
esac
echo "$(date -u +%H:%M:%S) start $RUNNER $1 (cap \$$CAP, meter \$$START, remaining \$$REMAINING)"
redwood_titanic/"$RUNNER" "$@" &
RUN_PID=$!
(
  while sleep 60; do
    read -r NOW _ < <(meter) || continue
    SPENT=$("$PY" -c "print(round($NOW - $START, 4))")
    echo "$(date -u +%H:%M:%S) spent \$$SPENT"
    if "$PY" -c "import sys; sys.exit(0 if $NOW - $START > $CAP else 1)"; then
      echo "$(date -u +%H:%M:%S) cap \$$CAP passed: stopping the eval"
      pkill -INT -f "$PATTERN"
      # Inspect lets in-flight model calls and bash commands (up to 360 s) finish after the
      # first SIGINT; run 19 ran 4 more minutes and nearly doubled its spend. Escalate.
      sleep 20; pgrep -f "$PATTERN" >/dev/null && { echo "$(date -u +%H:%M:%S) still running: second SIGINT"; pkill -INT -f "$PATTERN"; }
      sleep 40; pgrep -f "$PATTERN" >/dev/null && { echo "$(date -u +%H:%M:%S) still running: SIGTERM"; pkill -TERM -f "$PATTERN"; }
      break
    fi
  done
) &
GUARD_PID=$!
wait "$RUN_PID"; STATUS=$?
kill "$GUARD_PID" 2>/dev/null
read -r END REMAINING < <(meter)
echo "$(date -u +%H:%M:%S) finished $1 (runner exit $STATUS): meter delta \$$("$PY" -c "print(round($END - $START, 4))"), remaining \$$REMAINING"
exit $STATUS
