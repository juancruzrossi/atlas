---
name: atlas-guardrails
description: Record a concrete lesson from an Atlas task failure in the project's guardrails when it would prevent the same mistake in later tasks.
---

# Atlas guardrails

Read `.atlas/guardrails.md` before implementation. Add a rule only when a concrete
failure or verified project constraint justifies it. Keep it narrow and actionable:

```markdown
### Sign: Short name
- **Trigger:** Specific situation
- **Instruction:** Action that prevents the error
- **Learned from:** Task ID and observed failure
```

Guardrails guide implementation; they do not authorize changes outside the assigned
task or override Atlas ownership of backlog, configuration, session, or Git.
Do not turn a temporary limitation into a universal rule. If completion is blocked,
report the reason in the task result and preserve the partial work for recovery.
