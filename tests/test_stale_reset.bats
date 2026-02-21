#!/usr/bin/env bats

# Stale task reset tests

load test_helpers

setup() {
    setup_test_dir
    cp "$FIXTURES_DIR/backlog-sample.md" "$TEST_DIR/.atlas/backlog.md"
}

teardown() {
    teardown_test_dir
}

@test "stale reset moves IN_PROGRESS tasks to TODO" {
    # Create an old run log (simulate staleness)
    echo "old log" > "$TEST_DIR/.atlas/runs/run-old.log"
    touch -t 202501010000 "$TEST_DIR/.atlas/runs/run-old.log"

    cd "$TEST_DIR"
    BACKLOG_FILE=".atlas/backlog.md"
    RUNS_DIR=".atlas/runs"
    STALE_SECONDS=60
    ACTIVITY_LOG=".atlas/activity.log"
    echo "" > "$ACTIVITY_LOG"
    log_activity() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$ACTIVITY_LOG"; }

    # Source reset_stale_tasks from atlas.sh
    eval "$(sed -n '/^reset_stale_tasks()/,/^}/p' "$ATLAS_HOME/atlas.sh")"
    reset_stale_tasks

    # Verify IN_PROGRESS is now empty
    result=$(count_tasks "$BACKLOG_FILE")
    ip_count=$(echo "$result" | awk '{print $2}')
    [ "$ip_count" -eq 0 ]
}

@test "stale reset respects STARTED timestamp" {
    cd "$TEST_DIR"
    # Set a recent STARTED timestamp
    cat > ".atlas/backlog.md" <<'EOF'
## TODO

## IN_PROGRESS
### T-001: Active task
- **Started:** 2099-01-01T00:00:00

## DONE

## DELAYED
EOF

    BACKLOG_FILE=".atlas/backlog.md"
    RUNS_DIR=".atlas/runs"
    STALE_SECONDS=60
    ACTIVITY_LOG=".atlas/activity.log"
    echo "" > "$ACTIVITY_LOG"
    log_activity() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$ACTIVITY_LOG"; }

    eval "$(sed -n '/^reset_stale_tasks()/,/^}/p' "$ATLAS_HOME/atlas.sh")"
    reset_stale_tasks

    # Task should still be in IN_PROGRESS (future timestamp = not stale)
    result=$(count_tasks ".atlas/backlog.md")
    ip_count=$(echo "$result" | awk '{print $2}')
    [ "$ip_count" -eq 1 ]
}
