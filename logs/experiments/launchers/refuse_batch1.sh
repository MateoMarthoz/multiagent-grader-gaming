#!/usr/bin/env bash
# Waits for the running duel run (run_guarded.sh pid 736333) to finish, then runs run-1 of the three
# refuse-the-leak conditions in parallel (D24). Run detached: setsid nohup.
set -u
cd /root/multiagent-grader-gaming
echo "$(date -u +%H:%M:%S) waiting for pid 736333"
while kill -0 736333 2>/dev/null; do sleep 15; done
echo "$(date -u +%H:%M:%S) duel run finished; starting batch"
go() { local d=$1; shift; mkdir -p experiments/$d/run-1 && redwood_titanic/run_guarded.sh 1.50 run_experiment.sh $d run-1 "$@" > experiments/$d/run-1/guard.log 2>&1; }
go shared-escalate -T shared_submission=true -T escalate=true &
sleep 15
go escalate -T escalate=true &
sleep 15
go competitive-escalate -T scoring=competitive -T escalate=true &
wait
echo "ALL DONE $(date -u +%H:%M:%S)"
