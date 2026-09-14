# Atlas planning session

Read AGENTS.md, CLAUDE.md, .atlas/backlog.md, and .atlas/guardrails.md when present.
Interview the user using the provider's available question tool, or concise plain
questions when no question tool exists. Resolve routine choices from the project.
Record requirements, acceptance criteria, constraints, technical decisions,
out-of-scope work, and interview answers in the specified feature spec.

Add dependency-ordered vertical tasks under TODO. Include implementation and
its verification in the same task. Keep existing tasks and all other sections.
Use unique task IDs and this format:

### TASK-001: Task title
- **Spec:** .atlas/specs/spec-example.md
- **Description:** Concrete outcome
- **Acceptance:** Observable evidence that proves completion

Keep exactly one TODO, IN_PROGRESS, DONE, and DELAYED section. Do not change the
state of existing tasks. Do not implement code, alter Atlas runtime/configuration,
or run Git mutations. Finish by reporting the spec path and tasks added.
