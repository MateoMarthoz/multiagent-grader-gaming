#!/usr/bin/env bash
# Usage: serve.sh <hf-repo> [revision]   e.g. serve.sh allenai/Olmo-3-7B-Instruct
# Serves on 127.0.0.1:8000 (reach it through an SSH tunnel). Model files go in /root/stage-ckpt/hf.
set -euo pipefail
cd /root/stage-ckpt
MODEL=$1; REV=${2:-main}
export HF_HOME=/root/stage-ckpt/hf
export PATH=/root/stage-ckpt/.venv/bin:$PATH
export VLLM_USE_FLASHINFER_SAMPLER=0   # avoid FlashInfer JIT (needs ninja + CUDA 13 nvcc)
ARGS=(--host 127.0.0.1 --port 8000 --api-key "$(cat api_key)"
      --served-model-name "$MODEL" --revision "$REV"
      --max-model-len ${MAX_LEN:-65536} --gpu-memory-utilization ${GPU_UTIL:-0.90}
      --enable-auto-tool-choice --tool-call-parser ${TOOL_PARSER:-olmo3})
# CHAT_TEMPLATE: optional patched template (Olmo 3: templates/olmo3-instruct.jinja, which only
# defaults an undefined tools var to none; vLLM 0.33 startup probe crashes on the original)
[ -n "${CHAT_TEMPLATE:-}" ] && ARGS+=(--chat-template "$CHAT_TEMPLATE")
# TOOL_PLUGIN: vLLM tool-parser plugin file (plugins/olmo3_lenient_parser.py registers TOOL_PARSER=olmo3_lenient)
[ -n "${TOOL_PLUGIN:-}" ] && ARGS+=(--tool-parser-plugin "$TOOL_PLUGIN")
# EXTRA_ARGS: anything else for vllm serve (e.g. --quantization fp8)
[ -n "${EXTRA_ARGS:-}" ] && ARGS+=($EXTRA_ARGS)
exec .venv/bin/vllm serve "$MODEL" "${ARGS[@]}"
