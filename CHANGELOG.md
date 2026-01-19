# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.12.0] - 2026-01-19

### Added
- **Integration branch workflow**: All Atlas work now goes to an integration branch, not main
  - Step 0 in algorithm: auto-creates `integration/atlas-YYYYMMDD-HHMMSS` branch
  - Creates draft PR to main automatically (for human review)
  - `.claude/integration-session.json` tracks active session state
  - All feature PRs target integration branch
- **Atlas Skills**: Modular knowledge installed to `~/.claude/skills/`
  - `atlas-integration-flow`: Integration branch workflow details
  - `atlas-branching`: Branch naming, conventional commits, squash merge
  - `atlas-guardrails`: Signs format, error handling, learning from failures
  - `atlas-state`: backlog.md structure, progress.txt format, state transitions
- Skills auto-installed on `atlas init` and `atlas update`

### Changed
- Feature branches now created from integration branch (not main)
- PRs merged with squash to integration branch
- `atlas.sh` passes `integration-session.json` as context file
- `atlas.sh` downloads and installs skills from GitHub on update

## [1.11.0] - 2026-01-19

### Added
- Local mode: Atlas now works without git repositories
- Automatic detection of .git/ directory
- GIT_MODE variable passed to prompt (true/false)

### Changed
- Algorithm conditionally skips git operations when GIT_MODE=false
- No branches, commits, or PRs created in local mode
- Progress.txt PR field optional in local mode

## [1.10.0] - 2026-01-18

### Added
- Security scanning as quality gate before PR creation
- Secret detection: gitleaks, trufflehog, git-secrets (tries available tools)
- Vulnerability scanning: semgrep (30+ languages), plus language-specific fallbacks
- Language-agnostic approach: adapts to Node.js, Python, Go, Ruby, Java, etc.
- New guardrail Sign: "Security Scan Before PR"

### Changed
- Quality gates now split into: a) project gates, b) security scan
- Behavior is "best effort": warns if tools not installed, never blocks on missing tools

## [1.9.1] - 2026-01-18

### Changed
- Variables in prompt.md and plan_prompt.md now use explicit `envsubst` substitution
- Previously Claude had to mentally connect `ITERATION=2` with `$ITERATION` in text
- Now Claude receives fully processed text: "Iteration 2 of run..." directly
- More robust and less dependent on Claude's inference

## [1.9.0] - 2026-01-18

### Fixed
- Output capture reliability: Changed from pipe+tee to variable capture to avoid TTY buffering issues
- ~38% of iteration logs were previously empty due to stdout buffering when not connected to TTY
- Telegram notifications now show "Output not captured" instead of "No task" when logs are empty

### Added
- Boundaries section in prompt.md with explicit NEVER/ALWAYS rules
- Prevents Claude from creating unexpected files (like ARCHITECTURE_REVIEW.md)
- Warning message when no output is captured from Claude
- UNKNOWN status emoji (❓) in Telegram notifications for capture failures

### Changed
- Output capture now uses variable assignment instead of tee pipe (more reliable)
- Telegram notification handles empty summaries gracefully

## [1.8.2] - 2026-01-18

### Fixed
- Ctrl+C now exits the iteration loop gracefully

## [1.8.1] - 2026-01-18

### Fixed
- Unknown commands now show error instead of starting iteration loop
- Update removes old PLAN_PROMPT.md file to prevent 404 errors

## [1.8.0] - 2026-01-17

### Added
- Boundaries section in guardrails template with Always/Never rules
- Clear guidelines for safe autonomous operation across any language/stack

## [1.7.0] - 2026-01-16

### Changed
- Minimal initial prompt: only variables and file references (~10 lines vs ~100)
- prompt.md now referenced via PROMPT_FILE instead of injected
- Agent reads instructions from file like any other context file
- More scalable: prompt size no longer grows with instruction changes

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
