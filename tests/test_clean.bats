#!/usr/bin/env bats

# atlas clean tests

ATLAS="$BATS_TEST_DIRNAME/../atlas.sh"

setup() {
    TEST_DIR="$(mktemp -d)"
    cd "$TEST_DIR"
    "$ATLAS" init
    # Create some run logs and temp files
    echo "log content" > ".atlas/runs/run-test-1.log"
    echo "log content" > ".atlas/runs/run-test-2.log"
    echo "tmp content" > ".atlas/test.tmp"
}

teardown() {
    rm -rf "$TEST_DIR"
}

@test "atlas clean removes run logs" {
    run "$ATLAS" clean
    [ "$status" -eq 0 ]
    [ ! -f ".atlas/runs/run-test-1.log" ]
    [ ! -f ".atlas/runs/run-test-2.log" ]
}

@test "atlas clean removes temp files" {
    run "$ATLAS" clean
    [ "$status" -eq 0 ]
    [ ! -f ".atlas/test.tmp" ]
}

@test "atlas clean preserves backlog" {
    run "$ATLAS" clean
    [ "$status" -eq 0 ]
    [ -f ".atlas/backlog.md" ]
}

@test "atlas clean preserves activity.log" {
    echo "important log" > ".atlas/activity.log"
    run "$ATLAS" clean
    [ "$status" -eq 0 ]
    grep -q "important log" ".atlas/activity.log"
}

@test "atlas clean --all resets activity.log" {
    echo "important log" > ".atlas/activity.log"
    run "$ATLAS" clean --all
    [ "$status" -eq 0 ]
    ! grep -q "important log" ".atlas/activity.log"
}

@test "atlas clean --all resets errors.log" {
    echo "some error" > ".atlas/errors.log"
    run "$ATLAS" clean --all
    [ "$status" -eq 0 ]
    ! grep -q "some error" ".atlas/errors.log"
}

@test "atlas clean shows summary" {
    run "$ATLAS" clean
    [ "$status" -eq 0 ]
    [[ "$output" =~ "clean completed" ]]
    [[ "$output" =~ "Removed run logs:" ]]
}

@test "clean without .atlas shows error" {
    tmpdir=$(mktemp -d)
    cd "$tmpdir"
    run "$ATLAS" clean
    [ "$status" -eq 1 ]
    [[ "$output" =~ ".atlas/ not found" ]]
    rm -rf "$tmpdir"
}
