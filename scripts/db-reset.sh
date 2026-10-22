#!/bin/sh
# Drop everything, re-run the migrations and reload the test consumers.
# Also rewrites the sample lender file under data/inbound.
cd "$(dirname "$0")/.." || exit 1
TOOLS=$(ls shared-db/target/shared-db-*-tools.jar 2>/dev/null | head -1)
if [ -z "$TOOLS" ]; then
    echo "shared-db tools jar not found - run scripts/build.sh first" >&2
    exit 1
fi
java $JDBC_OPTS -cp "$TOOLS" com.ukcredit.db.DbMigrate clean || exit 1
java $JDBC_OPTS -cp "$TOOLS" com.ukcredit.db.SeedDataGenerator data/inbound/BKA001_20250101.dat
