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
persists the result, then repeats, retrying failures before giving up on a task.
It supports Claude Code, OpenCode, or Codex and leaves one PR open for human review.
The default provider remains claudecode.

- `lib/cli.js`: argument parsing, config loading, the runtime lock, and commands
  (`init`, `plan`, `run`, `status`, `help`). Also the npm `bin` entry point.
- `lib/backlog.js`: Markdown parsing, task selection, validated atomic transitions.
- `lib/agent.js`: the provider table (Claude Code, Codex, OpenCode) and the process
  supervisor used for both provider invocations and quality gates.
- `lib/git.js`: branch-as-state helpers, commits, and single open PR publication.
- `lib/loop.js`: the retry loop that ties backlog, agent, and git together.
- `prompt.md`, `plan_prompt.md`: implementation and interactive planning contracts.

The runtime uses Node standard-library modules with no production dependencies or
build step. Support Node >=18 on Linux and macOS. Bash is only needed for the
Telegram script and shell gates; no envsubst or GNU utilities required.

## Runtime invariants

1. Markdown is the task source of truth; there is no session JSON. The current
   Git branch (`atlas/*`) is the only run state Atlas keeps.
2. Exactly one task can be IN_PROGRESS. It is selected before any TODO task.
3. Atlas owns backlog, config, Git commits, and PRs. Providers implement tasks
   and write a structured result to a per-attempt path.
4. DONE requires a valid matching result, successful provider exit, and passing
   independently executed gates. Never trust stdout completion markers.
5. A failed attempt is retried up to `retries` times with the previous error fed
   back to the next attempt. Once exhausted, discard the task's uncommitted
   changes and move it to DELAYED with a `Reason`; the loop continues.
6. Respect task timeouts and cancellation (SIGINT/SIGTERM stop immediately and
   keep work, exit 130), reap provider descendants, and release locks. Do not
   leave background processes after tests or development work.
7. Keep main unchanged; use one `atlas/*` branch and one open PR per run, pushed
   after every commit. Never merge PRs in the runtime.
8. `status` must remain read-only and work while locked.
9. Tests must use isolated HOME, fake providers, and temporary Git remotes. Never
   invoke paid agents or send messages to real recipients as a test.

## State and commands

`.atlas/` contains config.json, backlog.md, guardrails.md, progress.txt, specs/,
runtime.lock, and runs/. Runtime files are ignored by Git.

Commands: init, plan, run (also bare numeric iterations), status, help. JSON
output is supported for status.

Config priority: CLI flags > .atlas/config.json > defaults. Keys: provider,
gates, iterations, timeout, retries, base. Keep provider differences isolated
in lib/agent.js. Prompt, README, and loop contracts must agree whenever
execution behavior changes.

## Verification and delivery

```bash
npm ci --ignore-scripts
npm test
npm run check
npm pack --dry-run
```

Node tests exercise actual CLI invocations, state transitions, signals, and Git
delivery using isolated fixtures with fake providers. CI runs Linux/macOS on
Node 18/24.

Create a branch, implement and verify changes, update version/changelog, push,
and create a PR using gh. Stop at the open PR unless merging is authorized.
GitHub Actions publishes a new package version automatically after merge to main.
