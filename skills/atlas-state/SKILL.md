---
name: atlas-state
description: Explain Atlas 4 task state and result contracts while implementing an assigned Atlas task or diagnosing an interrupted session.
---

# Atlas state contract

Atlas owns `.atlas/backlog.md`, `.atlas/config.json`, `.atlas/session.json`, and
`runtime.lock`. Do not change them during an implementation attempt. Planning may
add tasks under TODO without changing existing task states.

The runtime selects IN_PROGRESS before TODO, invokes one task, validates its JSON
result, runs configured gates, and records DONE and progress. It retains partial
work on failure. Do not move tasks yourself or use completion promises to end a run.

Write the result only to the attempt-specific file in the task prompt:
`{"taskId":"assigned ID","status":"done or blocked","summary":"changes, evidence, limits"}`.
Use blocked for unfinished work and explain the concrete blocker. A successful
result still needs runtime verification before the task is complete.

For user-requested recovery, inspect `atlas status`, `atlas logs --failed`, and
`atlas doctor`. Use `atlas resume` after resolving the reported failure. Do not
reset tasks because a timestamp is old or discard work to make the state appear clean.
