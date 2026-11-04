#!/usr/bin/env bash
# Run one overnight multi-agent episode (multi_overnight.py) and write its report and timeline.
# Usage: redwood_titanic/run_overnight.sh <run-name> -T experiment=<one_grader|conflicting|one_grader_dms|conflicting_team>
# RT_MODEL=mockllm/model for a free dry run.
set -euo pipefail
N=$1; shift
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"                                  # Inspect needs a relative task path
MODEL=${RT_MODEL:-openrouter/deepseek/deepseek-v4-flash-0731}
LOGDIR="logs/redwood-titanic-multi/run-$N"
PY=/root/capstone/.venv/bin/python
INSPECT=/root/capstone/.venv/bin/inspect
if [ -e "$LOGDIR" ]; then echo "$LOGDIR exists; refusing to overwrite" >&2; exit 1; fi
mkdir -p "$LOGDIR"
[ "$MODEL" = mockllm/model ] || "$PY" redwood_titanic/or_usage.py > "$LOGDIR/usage_before.json"
set +e
# Per-agent limits (150 messages, 3M tokens, as the single-agent default preset), 45-minute
# episode limit and 360 s per bash command are task defaults in multi_overnight.py.
"$INSPECT" eval redwood_titanic/multi_overnight.py@redwood_titanic_overnight \
  --model "$MODEL" \
  -M provider='{"order": ["DigitalOcean"], "allow_fallbacks": false}' \
  --epochs 1 --max-samples 1 --no-fail-on-error \
  --log-model-api --log-dir "$LOGDIR" --display plain "$@" > "$LOGDIR/console.log" 2>&1
STATUS=$?
echo "inspect exit: $STATUS" >> "$LOGDIR/console.log"
set -e
if [ "$MODEL" != mockllm/model ]; then
  sleep 90   # let OpenRouter's usage meter catch up
  "$PY" redwood_titanic/or_usage.py > "$LOGDIR/usage_after.json"
fi
"$PY" redwood_titanic/multi_analyze.py "$LOGDIR" > "$LOGDIR/report.md" 2>&1 || true
[ -f redwood_titanic/multi_overnight_timeline.py ] && "$PY" redwood_titanic/multi_overnight_timeline.py "$LOGDIR" > "$LOGDIR/timeline.md" 2>&1 || true
echo "done: $LOGDIR (inspect exit $STATUS)"
