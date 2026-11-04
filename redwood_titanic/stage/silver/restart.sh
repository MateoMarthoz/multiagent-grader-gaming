#!/usr/bin/env bash
# On silver (/root/stage-ckpt). Usage: restart.sh <hf-repo> [revision]
# Stops any running vLLM server, downloads the model if needed, starts a new server, waits until ready.
# Chat template: the model's own, with one line prepended:
#   {%- set tools = tools | default(none) -%}
# vLLM 0.33's startup probe renders the template without `tools`, which crashes Olmo templates;
# real requests always pass tools, so prompts are unchanged. CHAT_TEMPLATE=<file> overrides.
# Defaults: lenient Olmo tool parser (TOOL_PARSER / TOOL_PLUGIN), GPU_UTIL=0.95.
# EXTRA_ARGS is passed through to vllm serve (e.g. "--quantization fp8_per_tensor").
set -uo pipefail
cd /root/stage-ckpt
REPO=$1; REV=${2:-main}
TAG=$(echo "$REPO${2:+-$2}" | tr '/:' '__')
mkdir -p logs templates
pkill -f "vllm serve"; for _ in $(seq 1 60); do pgrep -f "vllm serve" >/dev/null || break; sleep 2; done
pkill -9 -f "vllm serve" 2>/dev/null; sleep 3
# Disk: before downloading, evict least recently used cached models (never REPO) until
# NEED_GB is free (a 32B checkpoint is 65 GB; the disk holds about two).
# (Weight files link into a shared hf/hub/blobs/ directory, so eviction deletes each link target
# that no other cached repo links to, then the repo directory.)
.venv/bin/python - "$REPO" "${NEED_GB:-75}" <<'PY'
import os, shutil, sys
from pathlib import Path
hub = Path("/root/stage-ckpt/hf/hub")
repo, need = sys.argv[1], float(sys.argv[2]) * 1e9
want = hub / ("models--" + repo.replace("/", "--"))

def targets(d: Path) -> set:
    return {p.resolve() for p in (d / "snapshots").rglob("*") if p.is_symlink()}

def free() -> float:
    return shutil.disk_usage("/").free

if want.exists():  # cached already (maybe another revision): only keep a small margin
    need = min(need, 20e9)

repos = sorted((d for d in hub.glob("models--*") if d.is_dir() and d != want),
               key=lambda d: max((p.lstat().st_atime for p in (d / "snapshots").rglob("*")), default=0))
for d in repos:
    if free() >= need:
        break
    others = set().union(*[targets(o) for o in hub.glob("models--*") if o.is_dir() and o != d])
    mine = targets(d) - others
    size = sum(t.stat().st_size for t in mine if t.exists())
    print(f"evicting {d.name} ({size / 1e9:.1f} GB)")
    for t in mine:
        t.unlink(missing_ok=True)
    shutil.rmtree(d)
print(f"free: {free() / 1e9:.0f} GB")
PY
if ! ./download.sh "$REPO" "$REV" > "logs/dl-$TAG.log" 2>&1; then
  echo "DOWNLOAD FAILED $REPO@$REV"; tail -5 "logs/dl-$TAG.log"; exit 1
fi
SNAP=$(HF_HOME=/root/stage-ckpt/hf .venv/bin/python - "$REPO" "$REV" <<'PY'
import sys
from huggingface_hub import snapshot_download
print(snapshot_download(sys.argv[1], revision=sys.argv[2], local_files_only=True))
PY
)
if [ -z "${CHAT_TEMPLATE+x}" ]; then
  .venv/bin/python - "$SNAP" "templates/$TAG.jinja" <<'PY'
import json, os, sys
snap, out = sys.argv[1], sys.argv[2]
p = os.path.join(snap, "chat_template.jinja")
src = open(p).read() if os.path.exists(p) else json.load(open(os.path.join(snap, "tokenizer_config.json")))["chat_template"]
open(out, "w").write("{%- set tools = tools | default(none) -%}" + src)
PY
  export CHAT_TEMPLATE="templates/$TAG.jinja"
fi
export TOOL_PLUGIN=${TOOL_PLUGIN-plugins/olmo3_lenient_parser.py}
export TOOL_PARSER=${TOOL_PARSER-olmo3_lenient}
export GPU_UTIL=${GPU_UTIL:-0.95}
LOG="logs/serve-$TAG.log"
echo "serving $REPO@$REV template=${CHAT_TEMPLATE:-model default} parser=$TOOL_PARSER extra=${EXTRA_ARGS:-}" > "$LOG"
nohup ./serve.sh "$REPO" "$REV" >> "$LOG" 2>&1 &
for i in $(seq 1 400); do
  if grep -q "Application startup complete" "$LOG"; then
    echo "READY $REPO@$REV after $((i * 3))s; $(grep -o 'GPU KV cache size: [0-9,]* tokens' "$LOG" | tail -1)"; exit 0
  fi
  if ! pgrep -f "vllm serve" >/dev/null; then
    echo "FAILED $REPO@$REV"; grep -E "Error|error" "$LOG" | tail -5; exit 1
  fi
  sleep 3
done
echo "TIMEOUT $REPO@$REV"; exit 1
