#!/bin/sh
# Reset the seeded DB, start one credit-file implementation plus the legacy score/dispute services
# pointed at it, then run the parity cases.
#
#   run-parity.sh legacy capture      -> fixtures/legacy-baseline.json
#   run-parity.sh boot compare        -> fixtures/boot-actual.json + parity-report.md
#
# Env: JAVA8 / JAVA21 (java binaries), JDBC_OPTS (see scripts/env-postgres.sh), DB_SHELL (override the
# command used for the DB checks), FIXTURES (baseline file), REPORT (markdown output). Run scripts/build.sh (JDK 8) and
# mvn -f credit-file-service-boot/pom.xml package (JDK 21) first.
set -e
TARGET=${1:?legacy|boot}
MODE=${2:?capture|compare}
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
cd "$ROOT"
JAVA8=${JAVA8:-/usr/lib/jvm/java-8-openjdk-amd64/bin/java}
JAVA21=${JAVA21:-/usr/lib/jvm/java-21-openjdk-amd64/bin/java}
FIXTURES=${FIXTURES:-$HERE/fixtures/legacy-baseline.json}
REPORT=${REPORT:-$HERE/parity-report.md}
LOGS=data/logs/parity
mkdir -p "$LOGS" "$HERE/fixtures"

stop_all() {
    for f in "$LOGS"/*.pid; do
        [ -f "$f" ] && kill "$(cat "$f")" 2>/dev/null || true
        rm -f "$f"
    done
}
wait_port() {
    i=0
    until curl -s -o /dev/null "http://localhost:$1$2"; do
        i=$((i + 1)); [ $i -gt 60 ] && { echo "port $1 did not come up" >&2; exit 1; }; sleep 1
    done
}
start() { # name port cmd...
    name=$1; port=$2; shift 2
    nohup "$@" > "$LOGS/$name.log" 2>&1 &
    echo $! > "$LOGS/$name.pid"
    wait_port "$port" /
    echo "started $name on $port"
}
trap stop_all EXIT
stop_all

PATH=$(dirname "$JAVA8"):$PATH scripts/db-reset.sh > "$LOGS/db-reset.log" 2>&1

case $TARGET in
legacy)
    CF_PORT=8081
    start credit-file-service $CF_PORT "$JAVA8" $JDBC_OPTS -jar credit-file-service/target/credit-file-service-*-exec.jar ;;
boot)
    CF_PORT=9081
    start credit-file-service-boot $CF_PORT "$JAVA21" $JDBC_OPTS -jar credit-file-service-boot/target/credit-file-service-boot.jar ;;
*)
    echo "unknown target $TARGET" >&2; exit 2 ;;
esac
CF_URL=http://localhost:$CF_PORT
start score-service 8082 "$JAVA8" $JDBC_OPTS -Dcreditfile.url=$CF_URL -jar score-service/target/score-service-*-exec.jar
start dispute-service 8083 "$JAVA8" $JDBC_OPTS -Dcreditfile.url=$CF_URL -Dscore.url=http://localhost:8082 \
    -jar dispute-service/target/dispute-service-*-exec.jar

if [ -z "$DB_SHELL" ]; then
    TOOLS=$(ls shared-db/target/shared-db-*-tools.jar | head -1)
    DB_SHELL="$JAVA8 -cp $TOOLS org.h2.tools.Shell -url jdbc:h2:file:./data/h2/ukcredit;MODE=PostgreSQL;AUTO_SERVER=TRUE -user ukcredit -password ukcredit -sql"
fi

if [ "$MODE" = capture ]; then
    python3 "$HERE/parity.py" capture --cases "$HERE/cases.json" --cf $CF_URL --db-shell "$DB_SHELL" --out "$FIXTURES"
else
    python3 "$HERE/parity.py" compare --cases "$HERE/cases.json" --cf $CF_URL --db-shell "$DB_SHELL" \
        --fixtures "$FIXTURES" --actual-out "$HERE/fixtures/$TARGET-actual.json" --report "$REPORT"
fi
