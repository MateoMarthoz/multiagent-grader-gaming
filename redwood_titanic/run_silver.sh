#!/usr/bin/env bash
# Run one single-agent trial against a model self-hosted with vLLM on the silver GPU machine.
# Usage: redwood_titanic/run_silver.sh <hf-repo> <trial-name> [extra inspect eval args]
#   e.g. redwood_titanic/run_silver.sh allenai/Olmo-3-7B-Instruct olmo3-7b-instruct-1 -T assistant_name=OLMo
# Needs: vLLM serving <hf-repo> on silver (/root/stage-ckpt/serve.sh <hf-repo>) and the tunnel
#   ssh -N -L 127.0.0.1:18000:127.0.0.1:8000 arena9-silver
# SILVER_API_KEY defaults to silver's /root/stage-ckpt/api_key. Native tool calling (vLLM's
# olmo3 parser), so no tool emulation and no added system prompt beyond the model's own template.
# Cost lines in the report use DeepSeek prices as a fallback; self-hosted runs cost nothing.
set -euo pipefail
REPO=$1; shift
export SILVER_BASE_URL=${SILVER_BASE_URL:-http://127.0.0.1:18000/v1}
export SILVER_API_KEY=${SILVER_API_KEY:-$(ssh -o BatchMode=yes -o LogLevel=ERROR arena9-silver cat /root/stage-ckpt/api_key)}
served=$(curl -sf -H "Authorization: Bearer $SILVER_API_KEY" "$SILVER_BASE_URL/models") \
  || { echo "silver vLLM not reachable at $SILVER_BASE_URL (tunnel down or server not started)" >&2; exit 1; }
grep -q "\"$REPO\"" <<<"$served" || { echo "silver is not serving $REPO: $served" >&2; exit 1; }
RT_MODEL="openai-api/silver/$REPO" exec "$(dirname "$0")/run_trial.sh" "$@"
