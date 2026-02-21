#!/usr/bin/env bats

# json_get() function tests

load test_helpers

@test "json_get reads string value" {
    result=$(json_get "name" "$FIXTURES_DIR/package-sample.json")
    [ "$result" = "test-pkg" ]
}

@test "json_get reads version string" {
    result=$(json_get "version" "$FIXTURES_DIR/package-sample.json")
    [ "$result" = "1.2.3" ]
}

@test "json_get reads integer value" {
    result=$(json_get "pr_number" "$FIXTURES_DIR/session-sample.json")
    [ "$result" = "42" ]
}

@test "json_get reads string from session" {
    result=$(json_get "branch" "$FIXTURES_DIR/session-sample.json")
    [ "$result" = "integration/atlas-20260101-120000" ]
}

@test "json_get returns empty for missing key" {
    result=$(json_get "nonexistent" "$FIXTURES_DIR/package-sample.json")
    [ -z "$result" ]
}

@test "json_get returns empty for missing file" {
    result=$(json_get "version" "/tmp/nonexistent-file-12345.json")
    [ -z "$result" ]
}

@test "json_get reads real package.json version" {
    result=$(json_get "version" "$ATLAS_HOME/package.json")
    [[ "$result" =~ ^[0-9]+\.[0-9]+\.[0-9]+ ]]
}
