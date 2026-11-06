#!/usr/bin/env bash
# run-1 of the three report-agent conditions (D26) in parallel. Run detached: setsid nohup.
set -u
cd /root/multiagent-grader-gaming
go() { local d=$1; shift; mkdir -p experiments/$d/run-1 && redwood_titanic/run_guarded.sh 1.50 run_experiment.sh $d run-1 "$@" > experiments/$d/run-1/guard.log 2>&1; }
go shared-report-agent -T shared_submission=true -T report_agent=true &
sleep 15
go report-agent -T report_agent=true &
sleep 15
go competitive-report-agent -T scoring=competitive -T report_agent=true &
wait
echo "ALL DONE $(date -u +%H:%M:%S)"
