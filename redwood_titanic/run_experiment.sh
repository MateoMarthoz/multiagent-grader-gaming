#!/usr/bin/env bash
# Run one episode of the main experiment (experiment.py: the experiments-main default, one -T flag
# per axis) and write its report.
# Usage: redwood_titanic/run_experiment.sh <run-name> [-T flag=value ...] [other inspect eval args]
#   e.g. redwood_titanic/run_experiment.sh default-1
#        redwood_titanic/run_experiment.sh nothr-1 -T threshold=false
# Run it in the background so the terminal stays free:
#   nohup redwood_titanic/run_experiment.sh default-1 > /dev/null 2>&1 &   (log: logs/experiments/run-default-1/)
# Spend cap: redwood_titanic/run_guarded.sh <cap-usd> run_experiment.sh <run-name> [...]
# RT_MODEL overrides the model, for a free dry run: RT_MODEL=mockllm/model run_experiment.sh dryrun
# RT_PROVIDER: OpenRouter provider-routing JSON (default: DigitalOcean only, the pin used for
# deepseek-v4-flash-0731); RT_PROVIDER= (empty) sends no provider param
set -euo pipefail
N=$1; shift
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"                                  # Inspect needs a relative task path
MODEL=${RT_MODEL:-openrouter/deepseek/deepseek-v4-flash-0731}
PROVIDER=${RT_PROVIDER-'{"order": ["DigitalOcean"], "allow_fallbacks": false}'}
PROVIDER_ARGS=()
[ -n "$PROVIDER" ] && [ "$MODEL" != mockllm/model ] && PROVIDER_ARGS=(-M provider="$PROVIDER")
LOGDIR="logs/experiments/run-$N"
PY=/root/capstone/.venv/bin/python
INSPECT=/root/capstone/.venv/bin/inspect
if [ -e "$LOGDIR" ]; then echo "$LOGDIR exists; refusing to overwrite" >&2; exit 1; fi
mkdir -p "$LOGDIR"
[ "$MODEL" = mockllm/model ] || "$PY" redwood_titanic/or_usage.py > "$LOGDIR/usage_before.json"
set +e
# Per-agent limits (2M tokens, no message cap), the 30-minute episode limit and 360 s per bash
# command are defaults of experiment.py; don't add CLI limits here, they would override them.
"$INSPECT" eval redwood_titanic/experiment.py \
  --model "$MODEL" \
  "${PROVIDER_ARGS[@]}" \
  --epochs 1 --max-samples 1 --no-fail-on-error \
  --log-model-api --log-dir "$LOGDIR" --display plain "$@" > "$LOGDIR/console.log" 2>&1
STATUS=$?
echo "inspect exit: $STATUS" >> "$LOGDIR/console.log"
set -e
if [ "$MODEL" != mockllm/model ]; then
  sleep 90   # let OpenRouter's usage meter catch up
  "$PY" redwood_titanic/or_usage.py > "$LOGDIR/usage_after.json"
fi
"$PY" redwood_titanic/multi_analyze.py "$LOGDIR" > "$LOGDIR/report.md" 2>&1
echo "done: $LOGDIR/report.md (inspect exit $STATUS)"
