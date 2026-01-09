# Changelog

All notable changes to Atlas will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.1] - 2026-01-09

### Fixed
- Terminal focus reporting artifacts (`^[[O^[[I^[`) after Claude execution

### Changed
- Installer now supports `curl | bash` installation
- Installer downloads from GitHub instead of requiring local clone
- `atlas update` downloads from GitHub instead of requiring git repo
- Symlink falls back to `~/bin` if `/usr/local/bin` requires sudo

---

## [1.0.0] - 2026-01-09

### Added
- Autonomous task processing from markdown backlog
- Two execution modes: backlog (auto-select) and prompt (natural language)
- GitFlow integration: branches, conventional commits, PRs, squash merge
- Quality checks before marking tasks ready to merge
- Session continuity: iterations 2+ use `--continue` for context
- Prompt optimization: subsequent iterations skip re-sending @files
- Model selection: finalize phase uses Sonnet for faster execution
- Resumable sessions: Ctrl+C saves state, `--resume` continues
- `atlas init`: initialize Atlas in any project
- `atlas create-backlog`: analyze codebase and auto-generate backlog
- `atlas update`: self-update from GitHub
- `atlas --status`: show backlog progress
- `atlas --dry-run`: preview mode without execution
- Template detection: warns about placeholder tasks
- Iteration timing: shows duration for each iteration
