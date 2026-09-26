# Atlas development instructions

## Rules

- Work on a branch and open a PR; push to main only when the maintainer asks.
- Before a PR, `npm run check` must pass. Suggest a SemVer version
  and ask whether to use it or Unreleased.
- A release updates package.json, package-lock.json, and CHANGELOG.md together.
- Merge only when asked: `gh pr merge --squash --admin --delete-branch`.
- Write all repository content in English: code, docs, prompts, messages,
  commits (Conventional Commits), and PRs.
- Keep README.md, prompt.md, and plan_prompt.md consistent with the code.
- Keep AGENTS.md and CLAUDE.md byte-for-byte identical.
- Keep code comments brief, necessary, and in English.

## Architecture

Node >=18 on Linux and macOS, standard library only, no build step.

- `lib/cli.js`: commands, config, and the run lock; the npm `bin` entry point.
- `lib/backlog.js`: Markdown backlog parsing and task transitions.
- `lib/agent.js`: provider table and process supervisor. Keep provider
  differences here.
- `lib/git.js`: `atlas/*` task branches, commits, and stacked PR publishing.
- `lib/loop.js`: the task loop.
- `prompt.md`, `plan_prompt.md`: agent contracts.

## Invariants

1. The Markdown backlog is the source of truth; the `atlas/*` branch is the
   only run state.
2. At most one task is IN_PROGRESS, and it runs before any TODO.
3. Atlas owns the backlog, config, commits, and PRs. Agents implement the task
   and write the result JSON.
4. DONE needs a successful agent exit, a valid `done` result, and passing gates
   when configured. Never trust stdout.
5. A failed attempt is retried up to `retries` times with the error fed back.
   Then Atlas discards the changes, moves the task to DELAYED with a `Reason`,
   and continues.
6. SIGINT/SIGTERM stop immediately, keep work, and exit 130. Enforce timeouts,
   reap child processes, and release the lock.
7. One stack per run: one `atlas/<run>/<task>` branch and PR per task with code, pushed after every commit. Never merge.
8. `status` is read-only and works while locked.

## Verify

```bash
npm run check && npm pack --dry-run
```

Pushing to main publishes a new npm version when package.json has one.
