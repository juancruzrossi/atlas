#!/usr/bin/env bats

# count_tasks() function tests

load test_helpers

@test "count_tasks with sample backlog" {
    result=$(count_tasks "$FIXTURES_DIR/backlog-sample.md")
    [ "$result" = "2 1 1" ]
}

@test "count_tasks with empty backlog" {
    result=$(count_tasks "$FIXTURES_DIR/backlog-empty.md")
    [ "$result" = "0 0 0" ]
}

@test "count_tasks with missing file" {
    result=$(count_tasks "/tmp/nonexistent-backlog-12345.md")
    [ "$result" = "0 0 0" ]
}

@test "count_tasks handles IN PROGRESS (with space)" {
    tmpfile=$(mktemp)
    cat > "$tmpfile" <<'EOF'
## TODO
### T-001: Task one

## IN PROGRESS
### T-002: Task two

## DONE
### T-003: Task three
### T-004: Task four

## DELAYED
EOF
    result=$(count_tasks "$tmpfile")
    rm -f "$tmpfile"
    [ "$result" = "1 1 2" ]
}
