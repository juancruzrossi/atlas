# Guardrails

Rules learned from observed project failures. Read before implementing a task.
Add a short sign only when it would prevent the same mistake in a future attempt:

```markdown
### Sign: Short descriptive name
- **Trigger:** Specific situation
- **Instruction:** Action that prevents the failure
- **Learned from:** Task ID and observed failure
```

Atlas owns task state, gates, commits, and PRs. Implement the assigned task and
report its result without modifying those controls. Preserve incomplete work
for recovery, and keep project-specific lessons below.

## Project-specific signs
