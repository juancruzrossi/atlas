#!/usr/bin/env bats

# atlas logs command tests

ATLAS="$BATS_TEST_DIRNAME/../atlas.sh"

setup() {
    TEST_DIR="$(mktemp -d)"
    cd "$TEST_DIR"
    "$ATLAS" init

    # Create sample run logs with summaries
    mkdir -p ".atlas/runs"

    cat > ".atlas/runs/run-20260101-120000-1-iter-1.log" <<'EOF'
Some iteration output...

=== SUMMARY ===
Task: HIGH-001 Add auth
Status: DONE
Loop: CONTINUE
EOF

    cat > ".atlas/runs/run-20260102-120000-2-iter-1.log" <<'EOF'
Some iteration output...

=== SUMMARY ===
Task: HIGH-002 Fix bug
Status: FAILED
Loop: CONTINUE
EOF

    cat > ".atlas/runs/run-20260103-120000-3-iter-1.log" <<'EOF'
Error encountered during compilation

=== SUMMARY ===
Task: MED-003 Refactor
Status: SKIPPED
Loop: CONTINUE
EOF

    # Ensure file order by touching with different times
    touch -t 202601010000 ".atlas/runs/run-20260101-120000-1-iter-1.log"
    touch -t 202601020000 ".atlas/runs/run-20260102-120000-2-iter-1.log"
    touch -t 202601030000 ".atlas/runs/run-20260103-120000-3-iter-1.log"
}

teardown() {
    rm -rf "$TEST_DIR"
}

@test "atlas logs shows entries" {
    run "$ATLAS" logs
    [ "$status" -eq 0 ]
    [[ "$output" =~ "3 of 3 logs shown" ]]
}

@test "atlas logs --tail limits output" {
    run "$ATLAS" logs --tail 2
    [ "$status" -eq 0 ]
    [[ "$output" =~ "2 of 3 logs shown" ]]
}

@test "atlas logs --failed shows only failures" {
    run "$ATLAS" logs --failed
    [ "$status" -eq 0 ]
    [[ "$output" =~ "FAIL" ]] || [[ "$output" =~ "SKIP" ]]
    # Should not include DONE entry
    ! [[ "$output" =~ "HIGH-001" ]]
}

@test "atlas logs --search filters by pattern" {
    run "$ATLAS" logs --search "compilation"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "MED-003" ]]
    [[ "$output" =~ "1 of 3 logs shown" ]]
}

@test "atlas logs without .atlas shows error" {
    tmpdir=$(mktemp -d)
    cd "$tmpdir"
    run "$ATLAS" logs
    [ "$status" -eq 1 ]
    [[ "$output" =~ ".atlas/ not found" ]]
    rm -rf "$tmpdir"
}

@test "atlas logs with no run files shows message" {
    rm -f .atlas/runs/*.log
    run "$ATLAS" logs
    [ "$status" -eq 0 ]
    [[ "$output" =~ "No iteration logs" ]]
}

@test "atlas logs help text in help command" {
    run "$ATLAS" help
    [ "$status" -eq 0 ]
    [[ "$output" =~ "atlas logs" ]]
}
