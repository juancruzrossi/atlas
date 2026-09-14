# Atlas context and ownership

Each attempt receives a fresh context. Persistent project files connect attempts:

| File | Purpose | Writer |
| --- | --- | --- |
| backlog.md | Task order and lifecycle | Atlas runtime; planner adds TODO tasks |
| config.json | Provider, limits, executable gates | Project owner |
| progress.txt | Verified task summaries | Atlas runtime |
| guardrails.md | Concrete lessons from failures | Implementation agent |
| errors.log | Failure summaries | Atlas runtime |
| activity.log | Structured execution events | Atlas runtime |
| session.json | Finalization, commit, and PR recovery | Atlas runtime |
| specs/ | Feature requirements and acceptance criteria | Interactive planner |

The runtime selects IN_PROGRESS before TODO and includes the assigned task and
its full specification in the prompt. The agent reads project rules, guardrails,
progress, and recent errors; implements that task; and writes a structured result.

A result alone does not finish the task. Atlas verifies process success, task ID,
result status, protected state, and configured gates before finalizing. Summaries
should identify observable evidence and unresolved limits, so later attempts do
not mistake an earlier claim for verification.

Keep guardrails specific to observed failures. Do not accumulate generic policies
or broaden the task based on incidental findings. Report unrelated work separately
in the result summary so the user can decide whether to add it to the backlog.
