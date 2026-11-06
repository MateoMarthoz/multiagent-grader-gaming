#!/usr/bin/env bash
# One paid pilot of report-agent-activity (D27). Run detached: setsid nohup.
set -u
cd /root/multiagent-grader-gaming
mkdir -p experiments/report-agent-activity/run-1
redwood_titanic/run_guarded.sh 0.80 run_experiment.sh report-agent-activity run-1 -T report_agent=true -T activity_view=true > experiments/report-agent-activity/run-1/guard.log 2>&1
echo "ALL DONE $(date -u +%H:%M:%S)"
