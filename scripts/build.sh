#!/bin/sh
# Full build. Needs JDK 1.8 + Maven 3.
cd "$(dirname "$0")/.." || exit 1
mvn -B clean install "$@"
