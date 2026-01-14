#!/usr/bin/env bats

# Test file for run.sh

# Note: Function unit tests are skipped since functions are internal.
# Tests focus on script behavior via command line.

@test "run.sh shows help when no flags" {
    run ./run.sh
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Usage: ./run.sh" ]]
}

@test "run.sh errors on unknown option" {
    run ./run.sh --unknown
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Unknown option: --unknown" ]]
}

@test "run.sh validates version format" {
    run ./run.sh --version "10.3a" --list
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Invalid version format '10.3a'" ]]
}

@test "run.sh accepts valid version" {
    # This will fail later due to Docker/data issues, but version validation should pass
    run ./run.sh --version "10.3" --list
    # If Docker/data fails, status !=1, but version validation passed if it reaches Docker check
    [[ "$output" != *"Invalid version format"* ]]
}

@test "run.sh validates recovery level" {
    # Invalid recovery, should set to default 0 with warning
    run ./run.sh --recovery 7 --list 2>&1
    [[ "$output" =~ "InnoDB force recovery level must be an integer between 0 and 6" ]]
}

@test "run.sh validates table format" {
    run ./run.sh --table "invalid.table.name" --list
    [[ "$output" =~ "Table must be in format 'db.table'" ]]
}

@test "run.sh errors on --database and --table together" {
    run ./run.sh --database test --table test.table --list
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Cannot use --database and --table together" ]]
}

@test "run.sh errors on --list and --table together" {
    run ./run.sh --list --table test.table
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Cannot use --list and --table together" ]]
}

@test "run.sh errors on --list and --run together" {
    run ./run.sh --list --run
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Cannot use --list and --run together" ]]
}

@test "run.sh warns on --skip-tables without --database" {
    run ./run.sh --skip-tables table1 --list
    [[ "$output" =~ "Warning: --skip-tables only applies with --database" ]]
}

@test "run.sh sanitizes data-dir path" {
    run ./run.sh --data-dir "." --list
    # Should not error on path, proceed to other checks
    [ "$status" -ne 1 ] || [[ "$output" != *"Invalid path"* ]]
}

# Note: Docker checks and full runs require Docker to be running and data to be present.
# Integration tests would go here if we mock Docker or use real data.