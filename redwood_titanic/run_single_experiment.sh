#!/usr/bin/env bash
# Single-agent version of the experiments-main default (single_experiment.py), with analyze.py's report.
# Usage: redwood_titanic/run_single_experiment.sh <run-name> [-T flag=value ...]
# RT_EPOCHS (default 1) epochs, all in parallel. RT_MODEL=mockllm/model for a free dry run.
set -euo pipefail
N=$1; shift
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"                                  # Inspect needs a relative task path
MODEL=${RT_MODEL:-openrouter/deepseek/deepseek-v4-flash-0731}
PROVIDER=${RT_PROVIDER-'{"order": ["DigitalOcean"], "allow_fallbacks": false}'}
PROVIDER_ARGS=()
[ -n "$PROVIDER" ] && [ "$MODEL" != mockllm/model ] && PROVIDER_ARGS=(-M provider="$PROVIDER")
EPOCHS=${RT_EPOCHS:-1}
LOGDIR="logs/experiments/single-$N"
PY=/root/capstone/.venv/bin/python
INSPECT=/root/capstone/.venv/bin/inspect
if [ -e "$LOGDIR" ]; then echo "$LOGDIR exists; refusing to overwrite" >&2; exit 1; fi
mkdir -p "$LOGDIR"
[ "$MODEL" = mockllm/model ] || "$PY" redwood_titanic/or_usage.py > "$LOGDIR/usage_before.json"
set +e
"$INSPECT" eval redwood_titanic/single_experiment.py@redwood_titanic_single_experiment \
  --model "$MODEL" \
  "${PROVIDER_ARGS[@]}" \
  --epochs "$EPOCHS" --max-samples "$EPOCHS" --no-fail-on-error \
  --log-model-api --log-dir "$LOGDIR" --display plain "$@" > "$LOGDIR/console.log" 2>&1
STATUS=$?
echo "inspect exit: $STATUS" >> "$LOGDIR/console.log"
set -e
if [ "$MODEL" != mockllm/model ]; then
  sleep 90   # let OpenRouter's usage meter catch up
  "$PY" redwood_titanic/or_usage.py > "$LOGDIR/usage_after.json"
fi
"$PY" redwood_titanic/analyze.py "$LOGDIR" > "$LOGDIR/report.md" 2>&1
echo "done: $LOGDIR/report.md (inspect exit $STATUS)"
