# Atlas state review

`atlas review` now performs deterministic, read-only diagnostics. It validates
the backlog, configuration, provider installation, quality gates, process lock,
and Git session. It reports concrete recovery instructions and exits nonzero
when a required check fails. `--dry-run` is retained as a compatibility alias.
No AI provider is invoked and no files, branches, or PRs are modified.
