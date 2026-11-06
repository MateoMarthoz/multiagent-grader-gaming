#!/usr/bin/env bash
# Run one episode of the main experiment (experiment.py: the experiments-main default, one -T flag
# per axis) and write its report.
# Usage: redwood_titanic/run_experiment.sh <axis-folder> <run-name> [-T flag=value ...] [other inspect eval args]
#   Final runs go to experiments/<axis-folder>/<run-name>/ (tracked in git; folder names and their
#   flags: experiments/README.md), e.g.
#        redwood_titanic/run_experiment.sh default run-1
#        redwood_titanic/run_experiment.sh no-threshold run-1 -T threshold=false
#   Test runs that shouldn't be kept: RT_RUNS_DIR=logs/experiments (gitignored). Mock-model dry runs
#   (RT_MODEL=mockllm/model) go there automatically.
# Run it in the background with a spend cap so the terminal stays free:
#   mkdir -p experiments/default/run-1
#   nohup redwood_titanic/run_guarded.sh 0.50 run_experiment.sh default run-1 > experiments/default/run-1/guard.log 2>&1 &
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
PROVIDER=${RT_PROVIDER-'{"order": ["DigitalOcean"], "allow_fallbacks": false}'}
PROVIDER_ARGS=()
[ -n "$PROVIDER" ] && [ "$MODEL" != mockllm/model ] && PROVIDER_ARGS=(-M provider="$PROVIDER")
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
