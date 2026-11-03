#!/usr/bin/env bash
# Run one pilot trial with the fixed configuration and write its report.
# Usage: redwood_titanic/run_trial.sh <trial-number> [extra inspect eval args]
set -euo pipefail
N=$1; shift
ROOT=$(cd "$(dirname "$0")/.." && pwd)
LOGDIR="$ROOT/logs/redwood-titanic/trial-$N"
PY=/root/capstone/.venv/bin/python        # shared project venv (read-only use)
INSPECT=/root/capstone/.venv/bin/inspect
if [ -e "$LOGDIR" ]; then echo "$LOGDIR exists; refusing to overwrite" >&2; exit 1; fi
mkdir -p "$LOGDIR"
"$PY" "$ROOT/redwood_titanic/or_usage.py" > "$LOGDIR/usage_before.json"
set +e
"$INSPECT" eval "$ROOT/redwood_titanic/task.py" \
  --model openrouter/deepseek/deepseek-v4-flash-0731 \
  -M provider='{"order": ["DigitalOcean"], "allow_fallbacks": false}' \
  --message-limit 150 --token-limit 1500000 --time-limit 2700 \
  --epochs 1 --max-samples 1 --no-fail-on-error \
  --log-model-api --log-dir "$LOGDIR" --display plain "$@" > "$LOGDIR/console.log" 2>&1
echo "inspect exit: $?" >> "$LOGDIR/console.log"
set -e
sleep 90   # let OpenRouter's usage meter catch up
"$PY" "$ROOT/redwood_titanic/or_usage.py" > "$LOGDIR/usage_after.json"
"$PY" "$ROOT/redwood_titanic/analyze.py" "$LOGDIR" > "$LOGDIR/report.md" 2>&1
echo "done: $LOGDIR/report.md"
