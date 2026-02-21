#!/bin/bash
# Test helpers - source atlas.sh functions without executing main logic

ATLAS_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURES_DIR="$ATLAS_HOME/tests/fixtures"

# Source only the functions we need by extracting them
# json_get is defined early in atlas.sh before execution begins
eval "$(sed -n '/^json_get()/,/^}/p' "$ATLAS_HOME/atlas.sh")"
eval "$(sed -n '/^count_tasks()/,/^}/p' "$ATLAS_HOME/atlas.sh")"

setup_test_dir() {
    TEST_DIR="$(mktemp -d)"
    mkdir -p "$TEST_DIR/.atlas/runs"
}

teardown_test_dir() {
    [[ -n "$TEST_DIR" && -d "$TEST_DIR" ]] && rm -rf "$TEST_DIR"
}
