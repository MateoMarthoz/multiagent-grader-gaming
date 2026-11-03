#!/usr/bin/env bash
# Run one pilot trial with the fixed configuration and write its report.
# Usage: redwood_titanic/run_trial.sh <trial-name> [extra inspect eval args]
# RT_MODEL overrides the model, for a free dry run: RT_MODEL=mockllm/model run_trial.sh dryrun
# RT_EPOCHS sets the number of epochs (default 1); epochs run one at a time (--max-samples 1)
set -euo pipefail
N=$1; shift
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"                                  # Inspect needs a relative task path
MODEL=${RT_MODEL:-openrouter/deepseek/deepseek-v4-flash-0731}
LOGDIR="logs/redwood-titanic/trial-$N"
PY=/root/capstone/.venv/bin/python          # shared project venv (read-only use)
INSPECT=/root/capstone/.venv/bin/inspect
if [ -e "$LOGDIR" ]; then echo "$LOGDIR exists; refusing to overwrite" >&2; exit 1; fi
mkdir -p "$LOGDIR"
"$PY" redwood_titanic/or_usage.py > "$LOGDIR/usage_before.json"
set +e
"$INSPECT" eval redwood_titanic/task.py \
  --model "$MODEL" \
  -M provider='{"order": ["DigitalOcean"], "allow_fallbacks": false}' \
  --message-limit 150 --token-limit 1500000 --time-limit 2700 \
  --epochs "${RT_EPOCHS:-1}" --max-samples 1 --no-fail-on-error \
  --log-model-api --log-dir "$LOGDIR" --display plain "$@" > "$LOGDIR/console.log" 2>&1
STATUS=$?
echo "inspect exit: $STATUS" >> "$LOGDIR/console.log"
set -e
sleep 90   # let OpenRouter's usage meter catch up
"$PY" redwood_titanic/or_usage.py > "$LOGDIR/usage_after.json"
"$PY" redwood_titanic/analyze.py "$LOGDIR" > "$LOGDIR/report.md" 2>&1
echo "done: $LOGDIR/report.md (inspect exit $STATUS)"
