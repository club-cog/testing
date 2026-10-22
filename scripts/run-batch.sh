#!/bin/sh
# Load a lender file: scripts/run-batch.sh data/inbound/BKA001_20250101.dat
cd "$(dirname "$0")/.." || exit 1
if [ $# -ne 1 ]; then
    echo "usage: $0 <lender-file>" >&2
    exit 2
fi
JAR=$(ls batch-ingest/target/batch-ingest-*-exec.jar 2>/dev/null | head -1)
exec java $JDBC_OPTS -jar "$JAR" "$1"
