#!/usr/bin/env bash
# run-1 of shared- and competitive-report-agent-activity (D27) in parallel. Run detached: setsid nohup.
set -u
cd /root/multiagent-grader-gaming
go() { local d=$1; shift; mkdir -p experiments/$d/run-1 && redwood_titanic/run_guarded.sh 0.80 run_experiment.sh $d run-1 "$@" > experiments/$d/run-1/guard.log 2>&1; }
go shared-report-agent-activity -T shared_submission=true -T report_agent=true -T activity_view=true &
sleep 15
go competitive-report-agent-activity -T scoring=competitive -T report_agent=true -T activity_view=true &
wait
echo "ALL DONE $(date -u +%H:%M:%S)"
