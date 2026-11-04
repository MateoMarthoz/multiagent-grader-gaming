#!/usr/bin/env bash
# Overnight job queue for the training-stage experiments on the silver GPU.
# Usage (from anywhere): nohup redwood_titanic/stage/worker.sh > logs/stage-queue/worker.log 2>&1 &
#
# Jobs are bash files in logs/stage-queue/pending/, run in name order (e.g. 010-o32-sft-cap5-1.sh).
# Each job sets REPO (HF repo), optionally REV (default main) and SERVE (extra vllm serve args,
# e.g. "--quantization fp8_per_tensor"), and defines job() which runs one or more episodes.
# The worker sources common.sh first, so jobs can use its arrays and prompts.
# Before a job, the worker makes sure silver serves REPO@REV with SERVE (restarting vLLM only when
# that changes) and that the SSH tunnel is up. Jobs move pending/ -> running/ -> done/ (or failed/).
# Add, reorder or delete pending jobs at any time. Touch logs/stage-queue/STOP to stop after the
# current job.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
cd "$ROOT"
Q=logs/stage-queue
mkdir -p "$Q"/{pending,running,done,failed}
CURRENT=""   # REPO@REV|SERVE currently served (empty: unknown, so the first job restarts)

log() { echo "$(date -u +%H:%M:%S) $*"; }

tunnel_up() {
  local key; key=$(cat $Q/.silver_key 2>/dev/null)
  curl -sf -m 10 -H "Authorization: Bearer $key" http://127.0.0.1:18000/v1/models >/dev/null
}

ensure_tunnel() {
  ss -ltn | grep -q '127.0.0.1:18000 ' && return 0
  log "starting tunnel"
  nohup ssh -N -o BatchMode=yes -o ServerAliveInterval=30 -o ServerAliveCountMax=3 \
    -o ExitOnForwardFailure=yes -o LogLevel=ERROR -L 127.0.0.1:18000:127.0.0.1:8000 arena9-silver \
    >> "$Q/tunnel.log" 2>&1 &
  sleep 5
}

ensure_server() {  # $1 repo, $2 rev, $3 serve args
  local want="$1@$2|$3"
  ensure_tunnel
  if [ "$CURRENT" = "$want" ] && tunnel_up; then return 0; fi
  log "restarting silver: $1@$2 ($3)"
  if ssh -o BatchMode=yes -o LogLevel=ERROR -o ServerAliveInterval=30 arena9-silver \
      "cd /root/stage-ckpt && EXTRA_ARGS='$3' ./restart.sh '$1' '$2'"; then
    CURRENT=$want
    ensure_tunnel
    for _ in $(seq 1 10); do tunnel_up && return 0; sleep 3; done
    log "server up but tunnel check failed"; return 1
  fi
  CURRENT=""; return 1
}

ssh -o BatchMode=yes -o LogLevel=ERROR arena9-silver cat /root/stage-ckpt/api_key > $Q/.silver_key
chmod 600 $Q/.silver_key
export SILVER_API_KEY; SILVER_API_KEY=$(cat $Q/.silver_key)

log "worker started (pid $$)"
while true; do
  if [ -e "$Q/STOP" ]; then log "STOP file found; exiting"; rm -f "$Q/STOP"; exit 0; fi
  JOB=$(ls "$Q/pending" 2>/dev/null | grep '\.sh$' | sort | head -1)
  if [ -z "$JOB" ]; then sleep 30; continue; fi
  mv "$Q/pending/$JOB" "$Q/running/$JOB"
  (
    REPO=""; REV=main; SERVE=""
    source redwood_titanic/stage/common.sh
    source "$Q/running/$JOB"
    [ -n "$REPO" ] || { log "$JOB: no REPO"; exit 2; }
    ensure_server "$REPO" "$REV" "$SERVE" || { log "$JOB: server failed"; exit 3; }
    log "$JOB: start ($REPO@$REV)"
    job
  ) >> "$Q/worker-jobs.log" 2>&1
  STATUS=$?
  # the subshell can't update CURRENT, so re-read what silver serves now
  CURRENT=$(ssh -o BatchMode=yes -o LogLevel=ERROR arena9-silver \
    "head -1 \$(ls -t /root/stage-ckpt/logs/serve-*.log | head -1)" 2>/dev/null \
    | sed -E 's/^serving ([^ ]+) template=.* extra=(.*)$/\1|\2/')
  if [ $STATUS -eq 0 ]; then mv "$Q/running/$JOB" "$Q/done/$JOB"; log "$JOB: done"
  else mv "$Q/running/$JOB" "$Q/failed/$JOB"; log "$JOB: FAILED (exit $STATUS)"; fi
done
