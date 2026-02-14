# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [3.0.0] - 2026-02-13

### Changed
- **NPM distribution**: Atlas is now published as `@jxtools/atlas` on NPM. Install with `npm install -g @jxtools/atlas`
- **Dynamic ATLAS_HOME**: Script resolves its own location via symlink traversal instead of hardcoded `~/.atlas`
- **`atlas update` command**: Now shows NPM update instructions instead of downloading from GitHub
- **GitHub Action**: Now publishes to NPM registry on new versions (requires `NPM_TOKEN` secret)
- **Error messages**: Updated references from `atlas update` to `npm update -g @jxtools/atlas`

### Removed
- **`install.sh`**: Replaced by `npm install -g @jxtools/atlas`
- **curl-based update**: No longer downloads files from GitHub raw URLs
- **`~/.atlas` directory**: Package files now live inside npm's global `node_modules`

### Added
- **`package.json`**: NPM package configuration with `@jxtools/atlas` scope
- **`scripts/postinstall.js`**: Automatically installs Atlas skills to detected AI providers on `npm install`

## [2.6.0] - 2026-02-12

### Changed
- **`atlas init` output simplified**: Now shows only `✓ Initialized .atlas/ in <path>` instead of listing every created file and installed skill

## [2.5.0] - 2026-02-10

### Added
- **`atlas status` command**: Shows task counts (TODO/IN_PROGRESS/DONE), active session info, and current git branch
- **`atlas doctor` command**: Diagnostic check for AI CLI, prompt files, envsubst, git, and gh CLI availability
- **Warning for `atlas plan` with non-interactive providers**: Shows confirmation prompt when using opencode or codex (which lack interactive interview support)

### Fixed
- **JSON parsing for integers**: New `json_get()` helper handles both string and integer JSON values (fixes `pr_number` extraction)
- **`atlas resume` now respects iteration count**: `atlas resume 5` correctly limits to 5 iterations instead of ignoring the argument
- **Removed broken symlink**: Cleaned up `atlas` symlink pointing to non-existent Ubuntu path
- **`prompt.md` validation**: Fails early with clear message if prompt.md is missing instead of cryptic envsubst error
- **`jq` removed from skills**: `atlas-integration-flow` skill now uses grep/sed instead of requiring jq
- **Telegram pending count**: Fixed `head -1` → `tail -1` to read bash-verified count instead of first line

### Changed
- **Simplified Step 0 in prompt.md**: Removed duplicated logic already handled by atlas.sh (~10 lines saved)
- **DRY skills installation**: New `install_skills()` function auto-detects available providers (~39 lines saved)
- **Centralized provider invocation**: New `run_provider()` function for plan/review commands (~20 lines saved)
- **Robust stale task reset**: Block-based awk state machine handles `IN_PROGRESS` and `IN PROGRESS` variants
- **Housekeeping**: Fixed CLI comment, cleaned .gitignore, removed dead sed, added CLAUDE.md/AGENTS.md sync note

## [2.4.1] - 2026-02-04

### Fixed
- **Codex review output is now fully non-interactive in Atlas Review**:
  - `atlas review --cli codex` no longer streams Codex session chatter to console
  - Codex output is captured in `.atlas/runs/review-*.log`
  - Console now shows a clean status message and log location

### Documentation
- Clarified README command syntax for provider flag usage (`command or iterations`)
- Clarified that `.atlas/specs/` is created by `atlas plan` (not by `atlas init`)

## [2.4.0] - 2026-02-04

### Added
- New `atlas clean` command:
  - `atlas clean`: Removes runtime logs (`.atlas/runs/*.log`) and temp files (`.atlas/*.tmp`)
  - `atlas clean --all`: Also resets `.atlas/activity.log`, `.atlas/errors.log`, and stale integration session metadata

### Fixed
- **Global flag parsing is now position-independent**:
  - `--cli` now works before or after command tokens (e.g. `atlas review --cli opencode`)
  - Commands now reject invalid mixed arguments consistently (`plan`, `resume`, `review`, `run`)
- **`atlas review --dry-run` now works**:
  - Enables report-only review mode with strict no-mutation instructions in the review prompt
  - Works consistently with any provider and argument order
- **Installer/update consistency fixes**:
  - `install.sh` now downloads `review_prompt.md` (required by `atlas review`)
  - Critical file checks now include `review_prompt.md` (install + update)
  - Skills are now downloaded once and copied to all available CLIs (Claude/OpenCode/Codex) even if Claude is not installed
- Fixed default branch detection in resume mode when `ATLAS_DEFAULT_BRANCH` is set

## [2.3.0] - 2026-02-04

### Changed
- **BREAKING: `atlas review` now uses AI** for intelligent auditing and repair
  - Replaces bash-only checks with AI-powered analysis
  - Loads full context (backlog, guardrails, progress, CLAUDE.md, git state)
  - Enforces ALL Atlas directives (from prompt.md, guardrails.md, CLAUDE.md)
  - Fixes inconsistencies automatically where possible
  - Reports what cannot be auto-fixed with clear reasoning
  - Respects `ATLAS_CLI` setting (codex/claude/opencode)
- New `review_prompt.md` with comprehensive audit checklist

### Fixed
- Review now properly audits directive compliance (quality gates, state transitions, etc.)
- Review can intelligently assess if tasks are truly complete
- Review understands context and makes smart decisions (not just mechanical checks)

## [2.2.1] - 2026-02-04

### Fixed
- **Codex flag syntax**: Changed from incorrect `--full-auto` to `--yolo` (official bypass flag)
- Codex now runs with full permission bypass in both plan and execution modes

## [2.2.0] - 2026-02-04

### Added
- **Codex (OpenAI) support**: New AI provider option
  - Use `--cli codex` or `ATLAS_CLI=codex`
  - Works in all commands: plan, execution, resume
  - Runs with `codex exec --full-auto` for non-interactive mode
  - Skills installed to `~/.codex/skills/` when codex CLI available

## [2.1.1] - 2026-02-04

### Changed
- **Removed jq dependency**: `atlas resume` now uses bash-native `awk` for JSON parsing
- No external dependencies required beyond core Unix tools (awk is POSIX standard)
- Integration session cleanup also uses awk instead of jq

## [2.1.0] - 2026-02-04

### Added
- **`atlas resume` command**: Resume interrupted integration sessions
  - Detects active session from `.atlas/integration-session.json`
  - Verifies PR not merged/closed before resuming
  - Switches to integration branch and continues iteration loop
  - Clear error messages for each failure scenario

## [2.0.2] - 2026-02-03

### Fixed
- **CRITICAL: Backlog update enforcement** - Tasks were being completed (PRs merged) but not moved to DONE in backlog.md, causing state drift
- Step 7 (Finalize) now marked as CRITICAL with explicit verification requirement
- Added "CRITICAL: Update Backlog After Merge" section to `atlas-integration-flow` skill
- Added verification rules to `atlas-state` skill: must confirm task in DONE before starting next task
- Root cause: Model was merging PRs but skipping the backlog update step, leaving completed tasks in TODO

## [2.0.1] - 2026-02-02

### Fixed
- **OpenCode invocation syntax** - Fixed "You must provide a message or a command" error by passing prompt content as argument instead of using `--file` flag

## [2.0.0] - 2026-02-02

### Added
- **Multi-provider AI support** - Atlas now supports both Claude Code and OpenCode
- **`--cli <provider>` flag** - Switch AI provider per command (claudecode | opencode)
- **`ATLAS_CLI` environment variable** - Set default provider for all sessions
- **Skills installation to OpenCode** - Atlas skills now installed to both `~/.claude/skills/` and `~/.config/opencode/skills/` (via `atlas init`, `atlas update`, and `install.sh`)
- **Provider validation** - Clear error messages if selected CLI is not installed, with installation instructions
- **Version flag** - `atlas --version` now displays current version (2.0.0)
- **Provider display** - Header now shows which AI provider is being used

### Changed
- Default provider remains Claude Code for backward compatibility
- `atlas plan` works with both providers (Claude Code recommended for best interactive experience)
- Improved error handling for missing AI CLIs
- Enhanced help documentation with examples for both providers

## [1.17.1] - 2026-02-02

### Fixed
- **macOS compatibility** - Fixed `timeout: command not found` error on macOS by using cross-platform timeout detection

## [1.17.0] - 2026-02-02

### Added
- **`atlas plan` now accepts args without quotes** - Both `atlas plan foo bar` and `atlas plan "foo bar"` work

### Fixed
- **plan_prompt.md deletion on case-insensitive filesystems** - macOS users can now run `atlas update` without breaking `atlas plan`
- Download validation in `atlas update` and `install.sh` - clearer error messages when downloads fail

### Changed
- Removed unnecessary comments from `atlas.sh` and `install.sh` for cleaner code

## [1.16.3] - 2026-01-23

### Fixed
- **Integration PR now Ready for Review** instead of Draft - allows immediate review when ready
- **Task movement rules enforced**: Only ONE task can be in IN_PROGRESS at a time
- Tasks must stay in TODO until work begins, then move to IN_PROGRESS one at a time
- Corrected atlas-guardrails skill: errors move to TODO (retry), not DELAYED

### Changed
- All Atlas skills updated to v1.1.0 with clearer invocation guidance
- Skills now explicitly document they should be invoked by Atlas specialized agents

## [1.16.2] - 2026-01-21

### Added
- `atlas init` now creates `.atlas/.gitignore` to exclude session logs from git tracking
- Logs (`activity.log`, `errors.log`, `runs/`) stay local for debugging, won't appear as uncommitted changes

## [1.16.1] - 2026-01-21

### Fixed
- Git checkout now shows actual error message instead of generic "Failed to checkout"
- Handle uncommitted changes gracefully with clear message and status output
- Handle repos without local default branch (creates from remote if available)
- Handle new repos with no commits yet (skips branch check entirely)

## [1.16.0] - 2026-01-21

### Added
- New skill `write-backlog-tasks` for structured task creation in backlog
- Interview-driven process: gathers requirements, explores codebase, defines scope
- Includes task template, priority guidelines, and anti-patterns to avoid

## [1.15.8] - 2026-01-20

### Fixed
- Error handling: failed tasks now return to TODO (retry), not DELAYED
- DELAYED section is only for tasks explicitly postponed by decision

## [1.15.7] - 2026-01-20

### Added
- Document `ATLAS_DEFAULT_BRANCH` env var in README and CLAUDE.md

## [1.15.6] - 2026-01-20

### Fixed
- **install.sh**: Now installs to `~/.atlas` (was `~/.local/bin`) - fixes "templates not found" on fresh install
- **atlas.sh**: Auto-detect default branch (main/master) instead of hardcoding `main` - supports repos with `master` or custom default
- **atlas.sh**: Check for `jq` before using it to avoid crash when not installed
- **atlas.sh**: Proper whitespace trim for spec paths (was removing all spaces, breaking paths with spaces)
- **notify-telegram.sh**: Guard against division by zero in progress bar

### Added
- New env var `ATLAS_DEFAULT_BRANCH` to override auto-detection

## [1.15.5] - 2026-01-20

### Fixed
- **CRITICAL**: prompt.md had `.claude/integration-session.json` paths instead of `.atlas/` (agent would look in wrong location)
- Removed dead code: `CLAUDE_PID` was never assigned but cleanup tried to use it
- Cleanup now returns to main branch on Ctrl+C interrupt
- Simplified AWK command for better portability across awk implementations
- Made `notify-telegram.sh` executable in repo (was missing +x)

### Changed
- Unified `progress.txt` template format to match prompt.md documentation
- Updated README to reflect integration branch workflow (PRs go to integration, not main)

## [1.15.4] - 2026-01-20

### Fixed
- Standardize section name to `## IN_PROGRESS` (with underscore) across all files
- `reset_stale_tasks()` was searching for `## IN PROGRESS` (with space) but template used underscore - stale detection never worked
- install.sh now downloads `plan_prompt.md` (was missing, `atlas plan` would fail on fresh install)

### Changed
- Updated templates, skills, README, CLAUDE.md, and references for consistency

## [1.15.3] - 2026-01-20

### Fixed
- Spec extraction now reads only from current task (IN_PROGRESS or first TODO), not first spec in entire backlog
- Tasks without `**Spec:**` field no longer load any spec file

## [1.15.2] - 2026-01-20

### Fixed
- **CLI retry logic**: Now performs real retries (3 silent attempts per iteration) instead of consuming iterations
- Telegram notifications only sent after all retries exhausted, not on each attempt
- CLI error notifications now show proper format with task, status, and pending count

## [1.15.1] - 2026-01-20

### Changed
- Move `integration-session.json` from `.claude/` to `.atlas/` for consistency
- All Atlas state files now live in `.atlas/` directory

## [1.15.0] - 2026-01-20

### Added
- Bash-verified pending task counter after each iteration (don't trust model's count)
- Shows pending count in terminal and Telegram notifications
- Logs pending count to activity.log

### Fixed
- **CRITICAL**: Atlas now returns to main branch on exit (COMPLETE or MAX_ITERATIONS)
- Prevents leaving user on integration/feature branch after run completes

### Changed
- CLAUDE.md: Added mandatory development workflow (branch → PR → merge)

## [1.14.0] - 2026-01-20

### Added
- **CRITICAL**: atlas.sh now forces checkout to main before starting iterations
- Automatic cleanup of merged integration sessions in bash (not dependent on model)
- Validates git state before invoking Claude to prevent stale branch issues

### Fixed
- Model no longer needs to follow "checkout main first" instruction - bash enforces it
- Prevents working on already-merged integration branches

## [1.13.0] - 2026-01-20

### Added
- CLI error detection and retry logic in atlas.sh
- Detects "No messages returned", API errors, network errors
- Automatic retry with 10s delay on CLI errors
- Stops after 3 consecutive errors to prevent infinite loops
- Telegram notifications for error states

## [1.12.3] - 2026-01-20

### Fixed
- Emphasized CRITICAL draft PR creation in integration flow algorithm
- PR to main must be created IMMEDIATELY after creating integration branch

## [1.12.2] - 2026-01-19

### Fixed
- Integration session cleanup: now ALWAYS starts from main at each iteration
- Detects merged integration PRs and auto-cleans stale session files
- Removed attempt to commit cleanup to main (which would fail on protected branches)
- Updated `atlas-integration-flow` skill with correct cleanup flow

## [1.12.1] - 2026-01-19

### Fixed
- Plan mode: variables now properly substituted instead of duplicated
- Replaced hardcoded `.atlas/backlog.md` with `$BACKLOG_FILE` variable
- Added Context section with all injected variables for better visibility

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
