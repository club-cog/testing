#!/bin/sh
# Records score-service responses for every seeded consumer, so legacy (8082) and
# score-service-boot (9082) can be compared byte for byte on the same freshly reset DB.
#
#   scripts/score-parity.sh capture http://localhost:8082 data/parity/legacy
#   scripts/score-parity.sh capture http://localhost:9082 data/parity/boot
#   scripts/score-parity.sh compare data/parity/legacy data/parity/boot
#
# capture writes SCORE_HISTORY rows (POST .../recalculate), so run scripts/db-reset.sh
# before each capture. Consumers default to the seeded range 100001-100256 plus an
# unknown id; override with FIRST_ID / LAST_ID / ASOF.
cd "$(dirname "$0")/.." || exit 1
FIRST_ID=${FIRST_ID:-100001}
LAST_ID=${LAST_ID:-100256}
UNKNOWN_ID=${UNKNOWN_ID:-999999}
ASOF=${ASOF:-2024-12-31}

call() { # method url outfile -> appends "status<TAB>name" to status.tsv
    code=$(curl -s -X "$1" -o "$3" -w '%{http_code}' "$2")
    printf '%s\t%s\n' "$code" "$(basename "$3")" >> "$OUT/status.tsv"
}

capture() {
    BASE=$1
    OUT=$2
    rm -rf "$OUT"
    mkdir -p "$OUT/get" "$OUT/get-today" "$OUT/recalc" "$OUT/recalc-trigger" "$OUT/history"
    : > "$OUT/status.tsv"
    for id in $(seq "$FIRST_ID" "$LAST_ID") "$UNKNOWN_ID"; do
        call GET "$BASE/score/$id?asOf=$ASOF" "$OUT/get/$id.json"
        call GET "$BASE/score/$id" "$OUT/get-today/$id.json"
        call POST "$BASE/score/$id/recalculate?asOf=$ASOF" "$OUT/recalc/$id.json"
        call POST "$BASE/score/$id/recalculate?asOf=$ASOF&trigger=BATCH" "$OUT/recalc-trigger/$id.json"
        call GET "$BASE/score/$id/history" "$OUT/history/$id.json"
    done
    echo "captured $(wc -l < "$OUT/status.tsv") responses from $BASE into $OUT"
}

compare() {
    A=$1
    B=$2
    rc=0
    for ep in get get-today recalc recalc-trigger history; do
        total=$(ls "$A/$ep" | wc -l)
        diffs=0
        for f in "$A/$ep"/*.json; do
            n=$(basename "$f")
            if ! cmp -s "$f" "$B/$ep/$n"; then
                diffs=$((diffs + 1))
                echo "DIFF $ep/$n"
            fi
        done
        printf '%-16s %4d compared, %4d identical, %4d different\n' "$ep" "$total" $((total - diffs)) "$diffs"
        [ "$diffs" -eq 0 ] || rc=1
    done
    if cmp -s "$A/status.tsv" "$B/status.tsv"; then
        echo "status codes     identical ($(cut -f1 "$A/status.tsv" | sort | uniq -c | tr -s ' ' | tr '\n' ',' | sed 's/,$//'))"
    else
        echo "status codes     DIFFERENT"
        diff "$A/status.tsv" "$B/status.tsv" | head -20
        rc=1
    fi
    return $rc
}

case "$1" in
    capture) capture "$2" "$3" ;;
    compare) compare "$2" "$3" ;;
    *) echo "usage: $0 capture <base-url> <out-dir> | compare <dir-a> <dir-b>" >&2; exit 2 ;;
esac
