#!/usr/bin/env bash
# Verify migrations + isolation suite on a plain Postgres.
# Usage: PGHOST=... PGPORT=... PGUSER=postgres ./tests/run_local.sh
set -euo pipefail
cd "$(dirname "$0")/.."
P="psql -v ON_ERROR_STOP=1 -q -o /dev/null"
$P -d postgres -c "drop database if exists lovebird_test" -c "create database lovebird_test"
$P -d lovebird_test -f tests/local_supabase_stubs.sql
for f in migrations/*.sql; do $P -d lovebird_test -f "$f"; done
$P -d lovebird_test -f tests/isolation.sql
