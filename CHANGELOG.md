# Changelog

All notable changes to Atlas will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed
- Terminal focus reporting artifacts (`^[[O^[[I^[`) after Claude execution

### Planned
- `--verbose` flag for real-time Claude output
- Automatic retry on Claude CLI streaming errors
- GitHub Actions for CI
- Automated tests with bats

---

## [1.0.0] - 2026-01-09

### Added
- **Autonomous task processing** from markdown backlog
- **Two execution modes**:
  - Backlog mode: auto-select tasks from TODO section
  - Prompt mode: natural language task selection
- **GitFlow integration**: branches, conventional commits, PRs, squash merge
- **Quality checks** before marking tasks ready to merge
- **Session continuity**: iterations 2+ use `--continue` to maintain context
- **Prompt optimization**: subsequent iterations skip re-sending @files
- **Model selection**: finalize phase uses Sonnet for faster execution
- **Resumable sessions**: interrupt with Ctrl+C and resume with `--resume`
- **`atlas init`**: initialize Atlas in any project
- **`atlas create-backlog`**: analyze codebase and auto-generate backlog
- **`atlas update`**: self-update from git repository
- **`atlas --status`**: show backlog progress with visual indicators
- **`atlas --dry-run`**: preview mode without execution
- **Template detection**: warns about placeholder tasks with `[...]`
- **Clean TUI**: clear screen interface for all commands
- **Iteration timing**: shows duration for each iteration

### Notes
- Requires Claude Code CLI, GitHub CLI, and Git
- Tested on macOS and Linux
