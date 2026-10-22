#!/bin/sh
# Start credit-file (8081), score (8082) and dispute (8083) in the background.
# Logs and pids go to data/logs. Stop with: kill $(cat data/logs/*.pid)
cd "$(dirname "$0")/.." || exit 1
mkdir -p data/logs
for svc in credit-file-service score-service dispute-service; do
    JAR=$(ls $svc/target/$svc-*-exec.jar 2>/dev/null | head -1)
    if [ -z "$JAR" ]; then
        echo "$svc: no jar, run scripts/build.sh" >&2
        exit 1
    fi
    nohup java $JDBC_OPTS $SVC_OPTS -jar "$JAR" > data/logs/$svc.log 2>&1 &
    echo $! > data/logs/$svc.pid
    echo "started $svc pid $! (data/logs/$svc.log)"
    # credit-file must be up before score/dispute start calling it
    sleep 3
done
