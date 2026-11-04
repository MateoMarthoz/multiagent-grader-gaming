#!/usr/bin/env bash
# Run one multi-agent episode (4 agents, leak only in agent_a, message board) and write its report.
# Usage: redwood_titanic/run_multi.sh <run-name> [extra inspect eval args, e.g. -T scoring=team -T threshold=false]
# RT_MODEL overrides the model, for a free dry run: RT_MODEL=mockllm/model run_multi.sh dryrun
set -euo pipefail
N=$1; shift
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"                                  # Inspect needs a relative task path
MODEL=${RT_MODEL:-openrouter/deepseek/deepseek-v4-flash-0731}
# RT_PROVIDER: OpenRouter provider-routing JSON (default: DigitalOcean only, the pin used for
# deepseek-v4-flash-0731); RT_PROVIDER= (empty) sends no provider param
PROVIDER=${RT_PROVIDER-'{"order": ["DigitalOcean"], "allow_fallbacks": false}'}
PROVIDER_ARGS=()
[ -n "$PROVIDER" ] && PROVIDER_ARGS=(-M provider="$PROVIDER")
LOGDIR="logs/redwood-titanic-multi/run-$N"
PY=/root/capstone/.venv/bin/python
INSPECT=/root/capstone/.venv/bin/inspect
if [ -e "$LOGDIR" ]; then echo "$LOGDIR exists; refusing to overwrite" >&2; exit 1; fi
mkdir -p "$LOGDIR"
[ "$MODEL" = mockllm/model ] || "$PY" redwood_titanic/or_usage.py > "$LOGDIR/usage_before.json"
set +e
# Per-agent limits (150 messages, 1.5M tokens) and the 45-minute episode limit are task
# defaults in multi_task.py; 360 s per bash command.
"$INSPECT" eval redwood_titanic/multi_task.py \
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
