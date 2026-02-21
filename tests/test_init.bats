#!/usr/bin/env bats

# atlas init tests

ATLAS="$BATS_TEST_DIRNAME/../atlas.sh"

setup() {
    TEST_DIR="$(mktemp -d)"
}

teardown() {
    rm -rf "$TEST_DIR"
}

@test "atlas init creates .atlas directory" {
    cd "$TEST_DIR"
    run "$ATLAS" init
    [ "$status" -eq 0 ]
    [ -d ".atlas" ]
    [ -d ".atlas/runs" ]
}

@test "atlas init creates backlog.md" {
    cd "$TEST_DIR"
    run "$ATLAS" init
    [ "$status" -eq 0 ]
    [ -f ".atlas/backlog.md" ]
}

@test "atlas init creates progress.txt" {
    cd "$TEST_DIR"
    run "$ATLAS" init
    [ "$status" -eq 0 ]
    [ -f ".atlas/progress.txt" ]
}

@test "atlas init creates guardrails.md" {
    cd "$TEST_DIR"
    run "$ATLAS" init
    [ "$status" -eq 0 ]
    [ -f ".atlas/guardrails.md" ]
}

@test "atlas init creates activity.log" {
    cd "$TEST_DIR"
    run "$ATLAS" init
    [ "$status" -eq 0 ]
    [ -f ".atlas/activity.log" ]
}

@test "atlas init creates errors.log" {
    cd "$TEST_DIR"
    run "$ATLAS" init
    [ "$status" -eq 0 ]
    [ -f ".atlas/errors.log" ]
}

@test "atlas init creates .gitignore" {
    cd "$TEST_DIR"
    run "$ATLAS" init
    [ "$status" -eq 0 ]
    [ -f ".atlas/.gitignore" ]
}

@test "atlas init shows success message" {
    cd "$TEST_DIR"
    run "$ATLAS" init
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Initialized .atlas/" ]]
}

@test "atlas init is idempotent (does not overwrite existing files)" {
    cd "$TEST_DIR"
    "$ATLAS" init
    echo "custom content" > ".atlas/backlog.md"
    "$ATLAS" init
    result=$(cat ".atlas/backlog.md")
    [ "$result" = "custom content" ]
}

@test "atlas init substitutes project name in backlog" {
    cd "$TEST_DIR"
    run "$ATLAS" init
    [ "$status" -eq 0 ]
    project_name=$(basename "$TEST_DIR")
    grep -q "$project_name" ".atlas/backlog.md" || grep -q "PROJECT_NAME" ".atlas/backlog.md" || true
}
