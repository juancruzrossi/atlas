#!/usr/bin/env bats

# CLI parsing and command routing tests

ATLAS="$BATS_TEST_DIRNAME/../atlas.sh"

@test "atlas --version shows version" {
    run "$ATLAS" --version
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^Atlas\ v[0-9]+\.[0-9]+\.[0-9]+ ]]
}

@test "atlas -v shows version" {
    run "$ATLAS" -v
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^Atlas\ v ]]
}

@test "atlas help shows usage" {
    run "$ATLAS" help
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Usage: atlas" ]]
}

@test "atlas --help shows usage" {
    run "$ATLAS" --help
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Usage: atlas" ]]
}

@test "atlas -h shows usage" {
    run "$ATLAS" -h
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Usage: atlas" ]]
}

@test "help lists all commands" {
    run "$ATLAS" help
    [ "$status" -eq 0 ]
    [[ "$output" =~ "atlas init" ]]
    [[ "$output" =~ "atlas plan" ]]
    [[ "$output" =~ "atlas review" ]]
    [[ "$output" =~ "atlas resume" ]]
    [[ "$output" =~ "atlas clean" ]]
    [[ "$output" =~ "atlas status" ]]
    [[ "$output" =~ "atlas doctor" ]]
    [[ "$output" =~ "atlas update" ]]
}

@test "unknown command shows error" {
    run "$ATLAS" foobar
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Unknown command" ]]
}

@test "--dry-run without review shows error" {
    run "$ATLAS" --dry-run init
    [ "$status" -eq 1 ]
    [[ "$output" =~ "--dry-run is only valid" ]]
}

@test "--all without clean shows error" {
    run "$ATLAS" --all init
    [ "$status" -eq 1 ]
    [[ "$output" =~ "--all is only valid" ]]
}

@test "update shows npm instructions" {
    run "$ATLAS" update
    [ "$status" -eq 0 ]
    [[ "$output" =~ "npm update -g @jxtools/atlas" ]]
}

@test "--cli without argument shows error" {
    run "$ATLAS" --cli
    [ "$status" -eq 1 ]
    [[ "$output" =~ "requires an argument" ]]
}

@test "--cli with invalid provider shows error" {
    run "$ATLAS" --cli invalid help
    [ "$status" -eq 1 ]
    [[ "$output" =~ "requires 'claudecode'" ]]
}

@test "plan without arguments shows usage" {
    run "$ATLAS" plan
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Usage: atlas plan" ]]
}
