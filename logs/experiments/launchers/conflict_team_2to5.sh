#!/usr/bin/env bash
# conflict-team runs 2-5 in two parallel pairs; run detached (setsid nohup) so it survives the Claude session.
set -u
cd /root/multiagent-grader-gaming
FLAGS=(-T grader_conflict=true -T shared_submission=true -T team_server=true)
run() { mkdir -p experiments/conflict-team/run-$1 && redwood_titanic/run_guarded.sh 1.00 run_experiment.sh conflict-team run-$1 "${FLAGS[@]}" > experiments/conflict-team/run-$1/guard.log 2>&1; }
run 2 & sleep 20; run 3 & wait
run 4 & sleep 20; run 5 & wait
echo "ALL DONE $(date -u +%H:%M:%S)"
