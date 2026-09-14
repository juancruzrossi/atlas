---
name: atlas-integration-flow
description: Describe Atlas 4 integration delivery and troubleshoot a session PR or publication failure when the user asks to recover Atlas work.
---

# Atlas integration delivery

A session has one integration branch and one PR. Atlas publishes only committed,
verified tasks and leaves the PR open. It does not create per-task PRs or merge
anything automatically. The current integration branch remains checked out.

`atlas resume` verifies the branch, HEAD, and existing PR state. If publication
failed after completed tasks were committed, it resumes publication without
running those tasks again. A commit journal resolves interrupted Git commits.

Use status, logs, and doctor to inspect errors before recovery. A closed, merged,
or retargeted PR requires user review. Legacy integration-session.json is not
silently converted: finish or archive the legacy session before starting Atlas 4.

When running as the implementation agent, do not operate this delivery workflow;
write the assigned task result and let Atlas finalize it.
