#!/bin/sh
# Run a command against a throwaway PostgreSQL server holding the database
# postgres_scanner's suite expects, loaded as its create-postgres-tables.sh does.
# The server's whole life is this one process: started on its own, it would
# inherit port's pipes and hold the test phase open.
#
# Usage: postgres-test.sh PGBIN DUCKDB_BUILD SCANNER_SRC PGDIR COMMAND...
set -e
pgbin=$1 build=$2 src=$3 pgdir=$4
shift 4

rm -rf "$pgdir"
mkdir -m 0700 "$pgdir"
"$pgbin/initdb" -D "$pgdir/data" -U postgres -A trust --locale=C -E UTF8 >/dev/null
"$pgbin/pg_ctl" -D "$pgdir/data" -l "$pgdir/log" -w \
    -o "-k '$pgdir' -p 54329 -c listen_addresses=''" start >/dev/null
trap '"$pgbin/pg_ctl" -D "$pgdir/data" -m fast -w stop >/dev/null' EXIT
export PGHOST="$pgdir" PGPORT=54329 PGUSER=postgres

# TPC-H and TPC-DS at scale 0.01, from the loadable-only tpch and tpcds.
"$build/duckdb" -unsigned >/dev/null <<EOF
LOAD '$build/extension/tpch/tpch.duckdb_extension';
LOAD '$build/extension/tpcds/tpcds.duckdb_extension';
CREATE SCHEMA tpch;
CREATE SCHEMA tpcds;
CALL dbgen(sf=0.01, schema='tpch');
CALL dsdgen(sf=0.01, schema='tpcds');
EXPORT DATABASE '$pgdir/export';
EOF
"$pgbin/createdb" postgresscanner
for sql in "$pgdir/export/schema.sql" "$pgdir/export/load.sql" \
           "$src/test/all_pg_types.sql" "$src/test/decimals.sql" "$src/test/other.sql"; do
    "$pgbin/psql" -q -v ON_ERROR_STOP=1 -d postgresscanner -f "$sql" >/dev/null
done

POSTGRES_TEST_DATABASE_AVAILABLE=1 "$@"
