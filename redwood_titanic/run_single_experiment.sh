#!/usr/bin/env bash
# Single-agent version of the experiments-main default (single_experiment.py), with analyze.py's report.
# Usage: redwood_titanic/run_single_experiment.sh <axis-folder> <run-name> [-T flag=value ...]
#   Final runs go to experiments/<axis-folder>/<run-name>/ (tracked in git), e.g.
#        redwood_titanic/run_single_experiment.sh single-default run-1
#        redwood_titanic/run_single_experiment.sh single-judge run-1 -T judge=true
#   Test runs that shouldn't be kept: RT_RUNS_DIR=logs/experiments (gitignored). Mock-model dry runs
#   (RT_MODEL=mockllm/model) go there automatically.
# Run it in the background with a spend cap so the terminal stays free:
#   mkdir -p experiments/single-judge/run-1
#   nohup redwood_titanic/run_guarded.sh 0.30 run_single_experiment.sh single-judge run-1 -T judge=true \
#     > experiments/single-judge/run-1/guard.log 2>&1 &
# RT_EPOCHS (default 1) epochs, all in parallel. RT_PROVIDER: OpenRouter provider-routing JSON (default:
# DigitalOcean only, the pin used for deepseek-v4-flash-0731); RT_PROVIDER= (empty) sends no provider param
set -euo pipefail
if [ $# -lt 2 ] || [[ "$1" == -* ]] || [[ "$2" == -* ]]; then
  echo "usage: $0 <axis-folder> <run-name> [-T flag=value ...]   (e.g. single-judge run-1 -T judge=true)" >&2; exit 2
fi
AXIS=$1; N=$2; shift 2
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"                                  # Inspect needs a relative task path
MODEL=${RT_MODEL:-openrouter/deepseek/deepseek-v4-flash-0731}
DEFAULT_RUNS=experiments
[ "$MODEL" = mockllm/model ] && DEFAULT_RUNS=logs/experiments
RUNS=${RT_RUNS_DIR:-$DEFAULT_RUNS}
PROVIDER=${RT_PROVIDER-'{"order": ["DigitalOcean"], "allow_fallbacks": false}'}
PROVIDER_ARGS=()
[ -n "$PROVIDER" ] && [ "$MODEL" != mockllm/model ] && PROVIDER_ARGS=(-M provider="$PROVIDER")
EPOCHS=${RT_EPOCHS:-1}
LOGDIR="$RUNS/$AXIS/$N"
PY=/root/capstone/.venv/bin/python
INSPECT=/root/capstone/.venv/bin/inspect
# the folder may already exist (e.g. made for the guard log), but must not hold a finished run
if compgen -G "$LOGDIR/*.eval" >/dev/null || [ -e "$LOGDIR/report.md" ]; then
  echo "$LOGDIR already has a run; refusing to overwrite" >&2; exit 1
fi
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
