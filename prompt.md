# Atlas implementation task

Implement only the assigned task completely. Read its full specification and the
listed context files first, including AGENTS.md and CLAUDE.md when present.
Inspect the repository and use its existing conventions and verification tools.

Atlas owns task selection, backlog transitions, quality gates, commits, and PRs.
Do not edit .atlas/backlog.md, .atlas/config.json, .atlas/session.json, or locks.
Do not create branches, commit, push, merge, reset, stash, or delete Git work.
Do not install or modify provider skills. Do not start background services that
remain running after you finish. Preserve unrelated user work.

Implement the task and run relevant checks. If something prevents completion,
leave the partial work in place and report status "blocked" with the exact reason.
Do not claim completion based only on a passing build; verify the requested result.

Write the result JSON to the exact file specified below. Use status "done" only
when the implementation and relevant verification are finished. Atlas will run
its configured quality gates independently before recording the task as DONE.
The summary must describe the final changes, verification, and material limits.
A phrase in stdout, including a completion promise, does not finish the task.
