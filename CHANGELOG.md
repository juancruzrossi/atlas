# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.6.1] - 2026-01-16

### Fixed
- `atlas update` shows "already up to date" when on latest version

## [1.6.0] - 2026-01-16

### Changed
- Prompt architecture: reference files instead of injecting content
- Context files listed in CONTEXT_FILES_TO_READ variable for selective reading
- Smaller initial prompt size, more scalable as files grow
- Agent reads files on-demand using Read tool (parallel reads for efficiency)

### Technical
- atlas.sh builds dynamic file list based on which files exist
- prompt.md updated with mandatory file reading instructions
- Variables exposed: BACKLOG_FILE, GUARDRAILS_FILE, PROGRESS_FILE, ERRORS_LOG, SPEC_FILE

## [1.5.1] - 2026-01-16

### Fixed
- Telegram notification emoji now uses pattern matching for statuses with extra info (e.g., "SKIPPED (already fixed)" now correctly shows ⏭️ instead of ⏳)

## [1.5.0] - 2026-01-16

### Fixed
- ATLAS_HOME now always points to ~/.atlas (binary can be anywhere)
- Plan mode runs interactively (no -p flag) so AskUserQuestionTool works
- Plan mode includes --dangerously-skip-permissions
- Version grep skips Unreleased section, shows actual version number

### Changed
- Plan prompt simplified: references files instead of embedding content
- Update output simplified: just shows "v1.4.0 → v1.5.0"
- CLAUDE.md: must ask user about versioning before merging PRs

## [1.4.0] - 2026-01-16

### Added
- `atlas plan "..."` command for interactive feature planning
- Planning mode uses `AskUserQuestionTool` to interview user about requirements
- Feature specs generated in `.atlas/specs/` directory
- Tasks from planning include `**Spec:**` field for integral view
- Main loop auto-loads spec file when task has `**Spec:**` field
- `PLAN_PROMPT.md` with interview, spec generation, and task decomposition phases

### Changed
- Documentation updated: README, CLAUDE.md, CONTEXT_ENGINEERING.md
- `atlas update` now includes PLAN_PROMPT.md

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
