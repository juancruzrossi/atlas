# Atlas planning session

Read AGENTS.md, CLAUDE.md, .atlas/backlog.md, and .atlas/guardrails.md when
present. Interview the user about the requested feature, using the provider's
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

Do not change the state of existing tasks, edit Atlas configuration, or run
Git commands. Finish by reporting the spec path and the tasks you added.
