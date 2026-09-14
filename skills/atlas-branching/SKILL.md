---
name: atlas-branching
description: Explain branch ownership and recovery boundaries during Atlas 4 task execution; does not apply to ordinary Git development outside Atlas.
---

# Atlas branch ownership

Atlas creates an integration branch from the configured base, commits each verified
task, and publishes the session PR. The implementation agent must not create or
switch branches, commit, push, merge, reset, stash, or delete Git work.

Implement the assigned task in the current directory. Leave failures in place and
report blocked. Runtime branch/HEAD validation detects unexpected Git mutations.

For explicitly requested recovery, inspect session.json and current Git state.
Restore the expected branch/HEAD only when the user's authorization and preserved
work make that appropriate. Do not overwrite the session to bypass a mismatch.
