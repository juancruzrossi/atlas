# Changelog

All notable changes to Atlas will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

---

## [1.2.0] - 2026-01-09

### Added
- GitHub Action for automatic releases on merge to main
  - Reads VERSION from atlas.sh
  - Creates git tag if doesn't exist
  - Creates GitHub Release with notes from CHANGELOG

### Changed
- Silent retry for transient CLI errors (no user-visible messages unless all retries fail)
  - Previously showed "CLI error detected, retrying..." on each attempt
  - Now silently retries and only shows error after 3 failed attempts

### Fixed
- Retry logic now also handles "streaming mode" CLI errors (not just lock conflicts)
  - These transient errors occur intermittently in non-interactive mode
  - Same exponential backoff (2s, 4s, 8s) applies

---

## [1.1.0] - 2026-01-09

### Added
- Retry logic with exponential backoff for Claude Code lock conflicts
  - Handles "Lock acquisition failed" errors when multiple CC sessions run concurrently
  - Automatically retries up to 3 times with 2s, 4s, 8s delays

### Changed
- Simplified interrupt message (removed redundant "signal received")
- **BREAKING**: Removed `project-rules.txt` in favor of using project's `CLAUDE.md`
  - Atlas now reads `CLAUDE.md` from project root (if exists) for project configuration
  - No separate configuration file needed—uses the same file Claude Code uses
  - If no `CLAUDE.md` exists, Atlas works without it (CC analyzes project automatically)
- Cleaned up unnecessary output messages during `atlas init`
- Added version number to README.md header
- Updated contributing guidelines in CLAUDE.md (changelog + version updates)

### Removed
- `templates/project-rules.txt` template file
- `PROJECT_RULES_FILE` validation (no longer required)
- Unused `is_git_repo()` function (dead code)

### Fixed
- Atlas now works on projects without git (skips git/branch/PR operations)

---

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
