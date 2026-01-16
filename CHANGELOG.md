# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.3.0] - 2026-01-16

### Added
- Iteration timeout (20 min default, configurable via `ATLAS_TIMEOUT`)
- Stale task recovery (auto-reset stuck IN_PROGRESS tasks after 2 hours)
- Pre-load all context files into prompt (no tool calls needed)
- `atlas update` now downloads latest version from GitHub
- Clear file formats for progress.txt, errors.log, guardrails.md
- Setup section in prompt: read context files BEFORE starting
- Error handling flow: move failed tasks to DELAYED

### Changed
- Prompt rewritten for clarity and consistency
- All output in English (summary, status, telegram notifications)
- Branch naming: `[type]/[TASK_ID]-[description]` instead of `atlas/`
- GitFlow: prefer /commit skill, fallback to gh CLI, then git
- PR body: full description instead of arbitrary text
- progress.txt logging is now mandatory (was optional)
- README simplified and updated

### Fixed
- Telegram parser mismatch for "Pendientes" field
- Spanish comments translated to English

## [1.2.0] - 2026-01-15

### Added
- Silent retry for transient CLI errors
- GitHub Action for automatic releases
- Release workflow instructions in CLAUDE.md

### Changed
- Simplified architecture to backlog.md only (removed prd.json)

## [1.1.0] - 2026-01-14

### Added
- Telegram notifications with progress bar
- Guardrails system (Signs methodology)
- Progress tracking across iterations

## [1.0.0] - 2026-01-14

### Added
- Initial release
- Ralph Wiggum loop implementation
- Basic backlog processing
- GitFlow integration (branch, PR, merge)
