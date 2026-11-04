#!/usr/bin/env bash
# One multi-agent episode with a scripted agent_a (see run_confederate.py) and write its report.
# Usage: redwood_titanic/run_confederate.sh <run-name> --model <receiver model> [--provider JSON]
#        [--post disclose|conceal] [-T key=value ...]
# Free check: redwood_titanic/run_confederate.sh confed-dryrun --model mockllm/model
set -euo pipefail
N=$1
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
LOGDIR="logs/redwood-titanic-multi/run-$N"
PY=/root/capstone/.venv/bin/python
if [ -e "$LOGDIR" ]; then echo "$LOGDIR exists; refusing to overwrite" >&2; exit 1; fi
mkdir -p "$LOGDIR"
REAL=1; [[ " $* " == *" --model mockllm/model "* ]] && REAL=0
[ "$REAL" = 1 ] && "$PY" redwood_titanic/or_usage.py > "$LOGDIR/usage_before.json"
set +e
"$PY" redwood_titanic/run_confederate.py "$@" > "$LOGDIR/console.log" 2>&1
STATUS=$?
echo "run_confederate exit: $STATUS" >> "$LOGDIR/console.log"
set -e
if [ "$REAL" = 1 ]; then
  sleep 90   # let OpenRouter's usage meter catch up
  "$PY" redwood_titanic/or_usage.py > "$LOGDIR/usage_after.json"
fi
"$PY" redwood_titanic/multi_analyze.py "$LOGDIR" > "$LOGDIR/report.md" 2>&1
echo "done: $LOGDIR/report.md (exit $STATUS)"
