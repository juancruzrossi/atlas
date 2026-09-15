# Atlas development instructions

## Critical rules

- Run `npm test` and `npm run check` before creating a PR; all checks must pass.
- Never commit or push directly to main. Work on a feature/fix branch and use PRs.
- Respond to the user in Spanish. Always write public repository content in English, including documentation, examples, prompts, user-facing messages, commit messages, and PR titles/descriptions.
- Use Conventional Commits in English. Keep README.md consistent with the implementation whenever behavior changes, including the Ralph loop and recovery contract.
- Only merge when requested. Use squash, `--admin`, and `--delete-branch` with `gh pr merge`.
- Before creating a PR, suggest a SemVer version and ask whether to use that version or Unreleased.
- Update package.json, package-lock.json, and CHANGELOG.md together for a release. Every change merged to main needs an appropriate version bump.
- AGENTS.md and CLAUDE.md must remain byte-for-byte identical.
- Code comments should be brief, necessary, and in English.

## Product and architecture

Atlas is distributed as `@jxtools/atlas`. Its core is a bounded Ralph loop: a fresh
agent invocation implements one Markdown backlog task, the runtime verifies and
persists the result, then repeats. Project files carry context between iterations.
It supports Claude Code, OpenCode, or Codex and leaves an integration PR open for
human review.
The default provider remains claudecode.

- `atlas.sh`: small symlink-aware npm entry point, delegates to Node.
- `lib/cli.js`, `lib/commands.js`: argument validation and user commands.
- `lib/config.js`: flags, ATLAS_* environment, and project config precedence.
- `lib/backlog.js`: Markdown parsing, task selection, validated atomic transitions.
- `lib/storage.js`: atomic state files, execution locks, event log.
- `lib/process.js`, `lib/providers.js`: provider adapters and process supervision.
- `lib/runner.js`: task execution, independent gates, finalization, recovery.
- `lib/git.js`: branch/HEAD invariants, commit journal, single open PR publication.
- `prompt.md`, `plan_prompt.md`: implementation and interactive planning contracts.
- `scripts/postinstall.js`: installs bundled skills into available provider directories.

The runtime uses Node standard-library modules with no production dependencies or
build step. Support Node >=18 on Linux and macOS. Bash is only needed for the
entry point, Telegram script, and shell gates; no envsubst or GNU utilities required.

## Runtime invariants

1. Markdown is the task source of truth; config/session JSON never replace it.
2. Exactly one task can be IN_PROGRESS. Resume it before selecting the first TODO.
3. Atlas owns backlog, config, session, Git commits, and PRs. Providers implement
   tasks and write a structured result to a per-attempt path.
4. DONE requires a valid matching result, successful provider exit, and passing
   independently executed gates. Never trust stdout completion markers.
5. Stop and preserve work on failure. Do not retry mutations automatically or
   reset tasks based on timestamps. Recovery must use current state evidence.
6. Respect task timeouts and cancellation, reap provider descendants, and release
   locks. Do not leave background processes after tests or development work.
7. Keep main unchanged; use one integration branch and PR per session. Never merge
   PRs in the runtime. Leave the working branch active on failure and completion.
8. Public status/log/diagnostic commands must remain read-only and work while locked.
9. Tests must use isolated HOME, fake providers, and temporary Git remotes. Never
   invoke paid agents or send messages to real recipients as a test.

## State and commands

`.atlas/` contains config.json, backlog.md, guardrails.md, progress.txt, specs/,
session.json, runtime.lock, runs/, activity.log, and errors.log. Runtime files are
ignored by Git. Legacy integration-session.json requires explicit migration.

Commands: init, plan, run (also bare numeric iterations), resume, review, status,
logs, doctor, clean, update, help. JSON output is supported for status/logs/diagnostics.
review is deterministic and read-only; --dry-run is retained for compatibility.

Config priority: CLI flags > ATLAS_* environment > .atlas/config.json > defaults.
An explicit gateTimeout overrides ATLAS_TIMEOUT for gates; see the README table.
Keep provider differences isolated in lib/providers.js. Prompt, skills, README,
and runner contracts must agree whenever execution behavior changes.

## Verification and delivery

```bash
npm ci --ignore-scripts
npm test
npm run check
npm pack --dry-run
```

Node tests exercise actual CLI invocations, state transitions, signals, Git
recovery, and package installation using isolated fixtures. Bats retains public
CLI regression coverage. CI runs Linux/macOS on Node 18/24.

Create a branch, implement and verify changes, update version/changelog, push,
and create a PR using gh. Stop at the open PR unless merging is authorized.
GitHub Actions publishes a new package version automatically after merge to main.
