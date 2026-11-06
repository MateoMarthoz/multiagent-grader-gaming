#!/usr/bin/env bash
# Replacement for competitive-report-agent run-4-grader-no, on what is left of the main key. Detached.
set -u
cd /root/multiagent-grader-gaming
RT_FLOOR_USD=0 redwood_titanic/run_guarded.sh 0.50 run_experiment.sh competitive-report-agent run-5 -T scoring=competitive -T report_agent=true > experiments/competitive-report-agent/run-5/guard.log 2>&1
echo "ALL DONE $(date -u +%H:%M:%S)"
