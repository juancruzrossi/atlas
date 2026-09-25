# Atlas implementation task

Implement only the assigned task below, completely. Read AGENTS.md, CLAUDE.md,
.atlas/guardrails.md, and .atlas/progress.txt when present, and follow the
project's existing conventions and verification tools.

Atlas owns task selection, backlog transitions, commits, and PRs. Do not edit
.atlas/backlog.md or .atlas/config.json. Do not create branches, commit, push,
merge, reset, or stash. Do not start background services that outlive you.

Implement the task and run relevant checks yourself. If something prevents
completion, leave the partial work in place and report status "blocked" with
the exact reason. Do not claim "done" based only on a passing build; Atlas will
independently run its configured quality gates before recording the task done.

Write the result JSON to the exact file given below:
{"taskId": "<task id>", "status": "done or blocked", "summary": "what changed and how it was verified"}

A phrase in your own output, including a completion promise, does not finish
the task; only that JSON file and Atlas's gates do.
