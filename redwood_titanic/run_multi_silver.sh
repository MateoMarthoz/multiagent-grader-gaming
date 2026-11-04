#!/usr/bin/env bash
# One multi-agent episode (4 agents, leak only in agent_a, message board) against a model served
# by vLLM on the silver GPU machine, then its report. Like run_multi.sh without the OpenRouter parts.
# Usage: redwood_titanic/run_multi_silver.sh <hf-repo> <run-name> [extra inspect eval args]
#   e.g. redwood_titanic/run_multi_silver.sh allenai/Olmo-3.1-32B-Instruct o32-final-cap5-1 \
#          -T assistant_name=OLMo -T scoring=none ... --system-message "..." --max-tokens 4096
# Needs the silver server (stage/silver/restart.sh <hf-repo>) and the tunnel on 127.0.0.1:18000
# (see run_silver.sh). Logs go to logs/redwood-titanic-multi/silver-<run-name>.
# Cost lines in the report use DeepSeek prices as a fallback; self-hosted runs cost nothing.
set -euo pipefail
REPO=$1; N=$2; shift 2
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"                                  # Inspect needs a relative task path
export SILVER_BASE_URL=${SILVER_BASE_URL:-http://127.0.0.1:18000/v1}
export SILVER_API_KEY=${SILVER_API_KEY:-$(ssh -o BatchMode=yes -o LogLevel=ERROR arena9-silver cat /root/stage-ckpt/api_key)}
served=$(curl -sf -H "Authorization: Bearer $SILVER_API_KEY" "$SILVER_BASE_URL/models") \
  || { echo "silver vLLM not reachable at $SILVER_BASE_URL (tunnel down or server not started)" >&2; exit 1; }
grep -q "\"$REPO\"" <<<"$served" || { echo "silver is not serving $REPO: $served" >&2; exit 1; }
LOGDIR="logs/redwood-titanic-multi/silver-$N"
PY=/root/capstone/.venv/bin/python
INSPECT=/root/capstone/.venv/bin/inspect
if [ -e "$LOGDIR" ]; then echo "$LOGDIR exists; refusing to overwrite" >&2; exit 1; fi
mkdir -p "$LOGDIR"
set +e
"$INSPECT" eval redwood_titanic/multi_task.py \
  --model "openai-api/silver/$REPO" \
  --epochs 1 --max-samples 1 --no-fail-on-error \
  --log-model-api --log-dir "$LOGDIR" --display plain "$@" > "$LOGDIR/console.log" 2>&1
STATUS=$?
echo "inspect exit: $STATUS" >> "$LOGDIR/console.log"
set -e
"$PY" redwood_titanic/multi_analyze.py "$LOGDIR" > "$LOGDIR/report.md" 2>&1
echo "done: $LOGDIR/report.md (inspect exit $STATUS)"
