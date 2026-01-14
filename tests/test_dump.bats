#!/usr/bin/env bats

# Test file for dump.sh

@test "dump.sh has correct shebang" {
    run head -1 "$(dirname "$BATS_TEST_DIRNAME")/dump.sh"
    [ "$output" = "#!/bin/sh" ]
}

@test "dump.sh is executable" {
    [ -x "$(dirname "$BATS_TEST_DIRNAME")/dump.sh" ]
}

@test "dump.sh contains MariaDB startup" {
    run grep "docker-entrypoint.sh" "$(dirname "$BATS_TEST_DIRNAME")/dump.sh"
    [ "$status" -eq 0 ]
}

@test "dump.sh has list mode logic" {
    run grep "LIST_MODE" "$(dirname "$BATS_TEST_DIRNAME")/dump.sh"
    [ "$status" -eq 0 ]
}

@test "dump.sh has compression logic" {
    run grep "NOCOMPRESS" "$(dirname "$BATS_TEST_DIRNAME")/dump.sh"
    [ "$status" -eq 0 ]
}

# Note: Full functional tests for dump.sh require running in Docker with MariaDB data,
# which is tested via integration in test_run.bats (e.g., --list with sample data)