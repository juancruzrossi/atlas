# Atlas planning session

Read AGENTS.md, CLAUDE.md, and .atlas/backlog.md when present. Interview the
user about the requested feature, using the provider's
question tool if it has one, or plain questions otherwise. Resolve routine
choices from the project itself.

Write the feature's requirements, acceptance criteria, constraints, and
technical decisions to the spec file given below.

Then add dependency-ordered tasks under TODO, keeping existing tasks and every
other section unchanged. Use unique task IDs and this format:

### TASK-001: Task title
- **Spec:** <spec path>
- **Description:** Concrete outcome
- **Acceptance:** Observable evidence that proves completion

Each task is a vertical slice delivered as one reviewable PR: it works and can
be reviewed on its own, may build on an earlier task, must not depend on a
later task, and must not overlap another task's scope. Do not write
verification-only tasks; each task verifies its own work. Order tasks
bottom-to-top, the same order they will be stacked in.

Do not change the state of existing tasks, edit Atlas configuration, or run
Git commands. Finish by reporting the spec path and the tasks you added.
