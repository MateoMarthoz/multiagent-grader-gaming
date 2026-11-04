#!/usr/bin/env bash
# Usage: download.sh <hf-repo> [revision]   (whole repo into /root/stage-ckpt/hf)
set -euo pipefail
export HF_HOME=/root/stage-ckpt/hf
/root/stage-ckpt/.venv/bin/hf download "$1" --revision "${2:-main}" --max-workers 16
