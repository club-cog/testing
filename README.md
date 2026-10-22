# uk-credit-platform (legacy)

Credit file, scoring and disputes services plus the nightly lender file load.

Build (JDK 1.8, Maven 3):

    scripts/build.sh

Local database (H2 file under data/h2) - wipe, migrate and load the test consumers:

    scripts/db-reset.sh

Start the services (logs in data/logs):

    scripts/run-all.sh

- credit-file-service  http://localhost:8080/creditfile/100001
- score-service        http://localhost:8082/score/100001?asOf=2024-12-31
- dispute-service      http://localhost:8083/disputes/40001

Load a lender file:

    scripts/run-batch.sh data/inbound/BKA001_20250101.dat

Postgres: `docker-compose up -d`, then `. scripts/env-postgres.sh` before the scripts above.

Test consumers are described in docs/seed-data.md.
