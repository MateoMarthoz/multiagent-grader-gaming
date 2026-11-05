#!/usr/bin/env bash
# Run one episode of duel_task.py (one AI agent against a confederate; D24) and write its report.
# Same as run_experiment.sh, plus the confederate (Dana/Orion), played by RT_CONFEDERATE (default:
# the same model as the subject, DeepSeek V4 Flash). -T other=human|agent picks the condition.
# Usage: redwood_titanic/run_duel.sh <folder> <run-name> -T other=human|agent [other inspect eval args]
#   e.g. redwood_titanic/run_duel.sh conflict-duel-human run-1 -T other=human
#   Test runs: RT_RUNS_DIR=logs/experiments; mock dry runs (RT_MODEL=mockllm/model) go there automatically.
#   With a spend cap: nohup redwood_titanic/run_guarded.sh 3.00 run_duel.sh <folder> <run> -T ... > <dir>/guard.log 2>&1 &
# RT_PROVIDER: OpenRouter provider-routing JSON (default: DigitalOcean only, the pin used for
# deepseek-v4-flash-0731); RT_PROVIDER= (empty) sends no provider param
set -euo pipefail
if [ $# -lt 2 ] || [[ "$1" == -* ]] || [[ "$2" == -* ]]; then
  echo "usage: $0 <axis-folder> <run-name> [-T flag=value ...]   (e.g. default run-1)" >&2; exit 2
fi
AXIS=$1; N=$2; shift 2
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"                                  # Inspect needs a relative task path
MODEL=${RT_MODEL:-openrouter/deepseek/deepseek-v4-flash-0731}
# final runs: experiments/ (tracked); mock dry runs default to the gitignored logs/experiments
DEFAULT_RUNS=experiments
[ "$MODEL" = mockllm/model ] && DEFAULT_RUNS=logs/experiments
RUNS=${RT_RUNS_DIR:-$DEFAULT_RUNS}
CONFEDERATE=${RT_CONFEDERATE:-$MODEL}   # same model as the subject by default
PROVIDER=${RT_PROVIDER-'{"order": ["DigitalOcean"], "allow_fallbacks": false}'}
PROVIDER_ARGS=()
# the confederate role gets its own model + the same provider pin (a -M provider=... reaches only
# the primary model); as a JSON role config so the pin applies to the confederate too
if [ "$MODEL" = mockllm/model ]; then
  ROLE="confederate=$CONFEDERATE"
elif [ -n "$PROVIDER" ]; then
  PROVIDER_ARGS=(-M provider="$PROVIDER")
  ROLE="confederate={\"model\": \"$CONFEDERATE\", \"extra_body\": {\"provider\": $PROVIDER}}"
else
  ROLE="confederate=$CONFEDERATE"
fi
LOGDIR="$RUNS/$AXIS/$N"
VENV=${RT_VENV:-$( [ -d /root/capstone/.venv ] && echo /root/capstone/.venv || echo /root/ARENA_materials/.venv )}
PY=$VENV/bin/python
INSPECT=$VENV/bin/inspect
# the folder may already exist (e.g. made for the guard log), but must not hold a finished run
if compgen -G "$LOGDIR/*.eval" >/dev/null || [ -e "$LOGDIR/report.md" ]; then
  echo "$LOGDIR already has a run; refusing to overwrite" >&2; exit 1
fi
mkdir -p "$LOGDIR"
[ "$MODEL" = mockllm/model ] || "$PY" redwood_titanic/or_usage.py > "$LOGDIR/usage_before.json"
set +e
# Token limits, the 30-minute episode limit and 360 s per bash command are defaults of duel_task.py; don't add CLI limits here, they would override them.
"$INSPECT" eval redwood_titanic/duel_task.py \
  --model "$MODEL" --model-role "$ROLE" \
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
"$PY" redwood_titanic/duel_report.py "$LOGDIR" > "$LOGDIR/report.md" 2>&1
echo "done: $LOGDIR/report.md (inspect exit $STATUS)"
