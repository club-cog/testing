#!/bin/sh
# Source this to point the tools/services at the docker-compose Postgres:
#   . scripts/env-postgres.sh
JDBC_OPTS="-Djdbc.driverClassName=org.postgresql.Driver -Djdbc.url=jdbc:postgresql://localhost:5432/ukcredit -Djdbc.username=ukcredit -Djdbc.password=ukcredit"
export JDBC_OPTS
