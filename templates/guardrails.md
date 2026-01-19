# Guardrails

> Rules learned from errors and gotchas. Atlas reads this at the start of every iteration.

## How to Add Signs

When you encounter an error or learn something the hard way, add a Sign:

```markdown
### Sign: [Descriptive Name]
- **Trigger**: When does this apply?
- **Instruction**: What to do (or NOT do)
- **Type**: Preventive | Corrective | Process | Architecture
- **Learned from**: Task ID or iteration
```

## Core Signs

### Sign: Always Read Before Edit
- **Trigger**: Before modifying any file
- **Instruction**: Always read the current file content before making changes
- **Type**: Preventive
- **Learned from**: Best practice

### Sign: One Task Per Iteration
- **Trigger**: When tempted to do multiple tasks
- **Instruction**: Complete ONE task fully before moving to the next
- **Type**: Process
- **Learned from**: Atlas design principle

### Sign: Verify Build After Changes
- **Trigger**: After any code modification
- **Instruction**: Run build/lint/test commands before marking task complete
- **Type**: Corrective
- **Learned from**: Best practice

### Sign: Security Scan Before PR
- **Trigger**: Before creating a pull request
- **Instruction**: Run available security tools (gitleaks, semgrep, npm audit, etc.) and fix HIGH/CRITICAL issues. Skip with warning if tools not installed.
- **Type**: Preventive
- **Learned from**: Best practice

---

## Boundaries

### ✅ Always
- Run existing tests before committing changes
- Read file contents before making edits
- Use available agents and skills when they fit the task
- Follow project naming conventions and code style
- Verify CI/PR checks pass before requesting merge
- Write clear, conventional commit messages
- Validate changes work before marking task complete

### 🚫 Never
- Commit secrets, credentials, or API keys
- Force push to protected branches without explicit approval
- Delete or skip failing tests without explicit approval
- Bypass quality gates (linter, formatter, type checker, tests)
- Leave temporary debug code in production
- Edit auto-generated files directly (modify the source instead)
- Ignore compiler/linter warnings without justification

---

## Project-Specific Signs

<!-- Add signs learned during this project below -->
