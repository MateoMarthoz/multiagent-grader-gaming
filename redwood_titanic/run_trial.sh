#!/usr/bin/env bash
# Run one pilot trial with the fixed configuration and write its report.
# Usage: redwood_titanic/run_trial.sh <trial-name> [extra inspect eval args]
# RT_MODEL overrides the model, for a free dry run: RT_MODEL=mockllm/model run_trial.sh dryrun
#   Featherless: RT_MODEL=openai-api/featherless/allenai/Llama-3.1-Tulu-3-8B run_trial.sh tulu-rlvr-1 -T assistant_name=Tulu
#   HF router:   RT_MODEL=hf-inference-providers/allenai/Llama-3.1-Tulu-3-8B:featherless-ai run_trial.sh ...
# RT_EPOCHS sets the number of epochs (default 1); epochs run one at a time (--max-samples 1)
set -euo pipefail
N=$1; shift
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"                                  # Inspect needs a relative task path
MODEL=${RT_MODEL:-openrouter/deepseek/deepseek-v4-flash-0731}
LOGDIR="logs/redwood-titanic/trial-$N"
PY=/root/capstone/.venv/bin/python          # shared project venv (read-only use)
INSPECT=/root/capstone/.venv/bin/inspect
# Provider-specific model args. OpenRouter: pin DigitalOcean (no fallbacks) and read the
# key's usage meter before/after. Featherless (openai-api/featherless/<hf-repo>, key in
# FEATHERLESS_API_KEY): no native tool calling is assumed, so Inspect emulates the bash tool
# (it adds a system prompt describing a <tool_call>{json}</tool_call> format).
OPENROUTER=0
case "$MODEL" in
  openrouter/*)
    # RT_PROVIDER: provider-routing JSON (default: the DigitalOcean pin used for
    # deepseek-v4-flash-0731); RT_PROVIDER= (empty) sends no provider param
    OPENROUTER=1
    PROVIDER=${RT_PROVIDER-'{"order": ["DigitalOcean"], "allow_fallbacks": false}'}
    MODEL_ARGS=()
    [ -n "$PROVIDER" ] && MODEL_ARGS=(-M provider="$PROVIDER") ;;
  openai-api/featherless/*)
    export FEATHERLESS_BASE_URL=${FEATHERLESS_BASE_URL:-https://api.featherless.ai/v1}
    MODEL_ARGS=(-M emulate_tools=true) ;;
  hf-inference-providers/*)
    # Hugging Face router (HF_TOKEN, billed to that HF account), e.g.
    # hf-inference-providers/allenai/Llama-3.1-Tulu-3-8B:featherless-ai; tools emulated as above
    MODEL_ARGS=(-M emulate_tools=true) ;;
  *)
    MODEL_ARGS=() ;;
esac
if [ -e "$LOGDIR" ]; then echo "$LOGDIR exists; refusing to overwrite" >&2; exit 1; fi
mkdir -p "$LOGDIR"
[ "$OPENROUTER" = 1 ] && "$PY" redwood_titanic/or_usage.py > "$LOGDIR/usage_before.json"
set +e
"$INSPECT" eval redwood_titanic/task.py \
  --model "$MODEL" \
  "${MODEL_ARGS[@]}" \
  --message-limit 150 --token-limit 1500000 --time-limit 2700 \
  --epochs "${RT_EPOCHS:-1}" --max-samples 1 --no-fail-on-error \
  --log-model-api --log-dir "$LOGDIR" --display plain "$@" > "$LOGDIR/console.log" 2>&1
STATUS=$?
echo "inspect exit: $STATUS" >> "$LOGDIR/console.log"
set -e
if [ "$OPENROUTER" = 1 ]; then
  sleep 90   # let OpenRouter's usage meter catch up
  "$PY" redwood_titanic/or_usage.py > "$LOGDIR/usage_after.json"
fi
"$PY" redwood_titanic/analyze.py "$LOGDIR" > "$LOGDIR/report.md" 2>&1
echo "done: $LOGDIR/report.md (inspect exit $STATUS)"
