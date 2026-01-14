#!/usr/bin/env bats

# Integration tests for Offline MariaDB Dump Tool
# Tests auto-detection and dumping with real fixtures

VERSION=${TEST_MARIADB_VERSION:-10.6}

setup() {
    # Create output directory for tests
    mkdir -p output
    # Ensure fixture exists
    if [[ ! -f "$BATS_TEST_DIRNAME/fixtures/mariadb-$VERSION.tar.gz" ]]; then
        "$BATS_TEST_DIRNAME/create_fixture.sh" "$VERSION"
    fi
}

teardown() {
    # Clean up output and temp data dir
    rm -rf output
    rm -rf "$TEST_DATA_DIR"
    # Clean up any leftover temp dirs in fixtures
    rm -rf "$BATS_TEST_DIRNAME/fixtures/temp-"*
}

@test "MariaDB $VERSION: auto-detect version with --list" {
    TEMP_DATA_DIR=$(mktemp -d "$BATS_TEST_DIRNAME/fixtures/temp-XXXXXX")
    tar -xzf "$BATS_TEST_DIRNAME/fixtures/mariadb-$VERSION.tar.gz" -C "$TEMP_DATA_DIR"
    export TEST_DATA_DIR="$TEMP_DATA_DIR"
    run "${BATS_TEST_DIRNAME}/../run.sh" --data-dir "$TEST_DATA_DIR" --list
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Auto-detected compatible MariaDB tag: $VERSION" ]]
    [[ "$output" =~ "testdb" ]]
}

@test "MariaDB $VERSION: full dump" {
    TEMP_DATA_DIR=$(mktemp -d "$BATS_TEST_DIRNAME/fixtures/temp-XXXXXX")
    tar -xzf "$BATS_TEST_DIRNAME/fixtures/mariadb-$VERSION.tar.gz" -C "$TEMP_DATA_DIR"
    export TEST_DATA_DIR="$TEMP_DATA_DIR"
    run "${BATS_TEST_DIRNAME}/../run.sh" --data-dir "$TEST_DATA_DIR" --dumps-dir "$BATS_TEST_DIRNAME/output" --version "$VERSION" --run
    [ "$status" -eq 0 ]
    [ -f "$BATS_TEST_DIRNAME/output/testdb.sql.gz" ]
    [ -s "$BATS_TEST_DIRNAME/output/testdb.sql.gz" ]
}

@test "MariaDB $VERSION: specific database dump" {
    TEMP_DATA_DIR=$(mktemp -d "$BATS_TEST_DIRNAME/fixtures/temp-XXXXXX")
    tar -xzf "$BATS_TEST_DIRNAME/fixtures/mariadb-$VERSION.tar.gz" -C "$TEMP_DATA_DIR"
    export TEST_DATA_DIR="$TEMP_DATA_DIR"
    run "${BATS_TEST_DIRNAME}/../run.sh" --data-dir "$TEST_DATA_DIR" --dumps-dir "$BATS_TEST_DIRNAME/output" --version "$VERSION" --database testdb --run
    [ "$status" -eq 0 ]
    [ -f "$BATS_TEST_DIRNAME/output/testdb.sql.gz" ]
    [ -s "$BATS_TEST_DIRNAME/output/testdb.sql.gz" ]
}

@test "MariaDB $VERSION: specific table dump" {
    TEMP_DATA_DIR=$(mktemp -d "$BATS_TEST_DIRNAME/fixtures/temp-XXXXXX")
    tar -xzf "$BATS_TEST_DIRNAME/fixtures/mariadb-$VERSION.tar.gz" -C "$TEMP_DATA_DIR"
    export TEST_DATA_DIR="$TEMP_DATA_DIR"
    run "${BATS_TEST_DIRNAME}/../run.sh" --data-dir "$TEST_DATA_DIR" --dumps-dir "$BATS_TEST_DIRNAME/output" --version "$VERSION" --table testdb.users --run
    [ "$status" -eq 0 ]
    [ -f "$BATS_TEST_DIRNAME/output/testdb.users.sql.gz" ]
    [ -s "$BATS_TEST_DIRNAME/output/testdb.users.sql.gz" ]
}


@test "MariaDB $VERSION: skip tables" {
    TEMP_DATA_DIR=$(mktemp -d "$BATS_TEST_DIRNAME/fixtures/temp-XXXXXX")
    tar -xzf "$BATS_TEST_DIRNAME/fixtures/mariadb-$VERSION.tar.gz" -C "$TEMP_DATA_DIR"
    export TEST_DATA_DIR="$TEMP_DATA_DIR"
    run "${BATS_TEST_DIRNAME}/../run.sh" --data-dir "$TEST_DATA_DIR" --dumps-dir "$BATS_TEST_DIRNAME/output" --version "$VERSION" --database testdb --skip-tables products --run
    [ "$status" -eq 0 ]
    [ -f "$BATS_TEST_DIRNAME/output/testdb.sql.gz" ]
    [ -s "$BATS_TEST_DIRNAME/output/testdb.sql.gz" ]
}