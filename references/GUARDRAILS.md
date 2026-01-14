# Guardrails Reference

## What Are Guardrails?

Guardrails are rules learned from mistakes. They prevent the agent from repeating errors across iterations.

## The Signs Methodology

Signs are structured guardrails with four components:

1. **Trigger**: The situation that activates this rule
2. **Instruction**: What to do (or avoid)
3. **Type**: Category of the sign
4. **Learned from**: Origin of the learning

### Sign Types

| Type | Purpose | Example |
|------|---------|---------|
| **Preventive** | Stop errors before they happen | "Always check file exists before reading" |
| **Corrective** | Fix common mistakes | "If build fails, check for missing imports first" |
| **Process** | Workflow rules | "Create branch before making changes" |
| **Architecture** | Design decisions | "Use Repository pattern for data access" |

## Why Signs Work

1. **Structured memory**: Each iteration reads guardrails.md first
2. **Prevents loops**: Same mistakes don't repeat across iterations
3. **Accumulates wisdom**: Project-specific knowledge grows over time
4. **Clear triggers**: Agent knows exactly when to apply each rule

## Best Practices

1. **Be specific**: "Don't use `any` type" is better than "Use proper types"
2. **Include context**: Explain why, not just what
3. **One rule per sign**: Keep signs focused and actionable
4. **Update regularly**: Add signs immediately after learning something

## Example Signs

```markdown
### Sign: Check Dependencies Before Import
- **Trigger**: Adding a new import statement
- **Instruction**: Verify the package is in package.json before importing
- **Type**: Preventive
- **Learned from**: US-003 build failure

### Sign: Use Absolute Imports
- **Trigger**: Creating import paths
- **Instruction**: Use @/ prefix for project imports, not relative paths
- **Type**: Architecture
- **Learned from**: Project convention in CLAUDE.md
```
