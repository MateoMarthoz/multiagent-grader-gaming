#!/usr/bin/env bash
# Two multi-agent episodes, one after the other: 0.95 threshold on, then off.
# Single grader in agent_a's container, check_score for everyone ("purpose" wording, 5 checks),
# 20-minute stated time limit, 2M tokens per agent, no message cap, no scoring line, wake on post.
# Needs OPENROUTER_API_KEY in the environment. Usage (from anywhere):
#   nohup redwood_titanic/run_cap5.sh > logs/redwood-titanic-multi/cap5-batch.log 2>&1 &
set -uo pipefail
cd "$(dirname "$0")/.."
: "${OPENROUTER_API_KEY:?set OPENROUTER_API_KEY first}"
COMMON=(-T scoring=none -T schedule=async -T wake_on_post=true -T graders=single
        -T score_tool=true -T score_tool_wording=purpose -T score_check_limit=5
        -T time_limit_minutes=20 -T agent_token_limit=2000000 -T agent_message_limit=null)
echo "$(date -u +%H:%M:%S) start cap5-thr"
redwood_titanic/run_multi.sh cap5-thr -T threshold=true "${COMMON[@]}"
echo "$(date -u +%H:%M:%S) start cap5-nothr"
redwood_titanic/run_multi.sh cap5-nothr -T threshold=false "${COMMON[@]}"
echo "$(date -u +%H:%M:%S) both done"
