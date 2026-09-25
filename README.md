# Atlas

Atlas runs a **Ralph loop** over a Markdown backlog: start a coding agent with
fresh context, implement one task, verify the result, save progress, and repeat.
It supports Claude Code, OpenCode, and Codex.

Atlas owns the loop, task state, verification, and delivery. It commits every
result to a single `atlas/*` branch and pushes it, opening one PR that stays
open for review.

## The Ralph loop

The core idea comes from [Geoffrey Huntley's Ralph technique](https://ghuntley.com/ralph/):
repeated coding-agent invocations, fresh context each time, persistent project
files, and tests that provide feedback on generated changes.

Atlas applies that idea with an explicit backlog and a bounded, retrying loop:

```text
Select IN_PROGRESS, otherwise the first TODO
  -> Build context from the task, its specification, and the previous error (if any)
  -> Start a fresh agent invocation to implement that task
  -> Validate the result and run the project's quality gates
  -> On failure, retry with the error fed back, up to `retries` attempts
  -> DONE: record progress and commit. Exhausted: discard changes, DELAYED with a Reason
  -> Commit, push, and update the PR
  -> Repeat with the next task

Stop when no runnable tasks remain or the iteration limit is reached.
```

Each iteration starts a new provider invocation; Atlas does not resume the
previous conversation. It includes the assigned task, its specification, and
the previous attempt's error (if any) in the prompt, and asks the agent to read
existing project instructions and guardrails. Source files, `.atlas/` state, and
Git history carry work and lessons between iterations.

The agent implements; Atlas decides when a task is complete. A successful process
exit, a matching JSON result with status `done`, and every configured quality gate
must all pass. A completion phrase in the agent's output cannot advance the queue.
The strength of verification depends on the gates you configure.

A task that keeps failing does not stop the run: after `retries` attempts, Atlas
discards its uncommitted changes, moves it to DELAYED with the failure recorded
as `Reason`, and continues with the next task. This keeps Atlas useful unattended
overnight; review DELAYED tasks afterward with `atlas status`.

## Install

Requirements: Node.js 18 or newer, Git, and an installed, authenticated provider.
Supported platforms are Linux and macOS. PR publication also requires an `origin`
remote and an authenticated GitHub CLI (`gh`).

```bash
npm install -g @jxtools/atlas
cd my-project
atlas init
```

`atlas init` creates missing project files without overwriting your backlog.

## First run

Set the project's real verification commands in `.atlas/config.json`:

```json
{
  "provider": "codex",
  "iterations": 25,
  "timeout": 1200,
  "retries": 3,
  "gates": ["npm test", "npm run build"]
}
```

Atlas requires at least one explicit quality gate and independently runs every
gate after each implementation attempt. Gate commands run sequentially with
`/bin/sh` from the project root; `timeout` is in seconds and applies to both the
agent invocation and each gate.

Plan tasks in an interactive terminal, or edit the backlog by hand:

```bash
atlas plan "Add authentication"
```

Commit the backlog and configuration on your base branch, then start the loop:

```bash
git add .atlas/
git commit -m "chore: configure Atlas tasks"
atlas 5
```

Atlas creates `atlas/<timestamp>` from the current branch (or reuses it if you
are already on one), runs up to 5 iterations, and pushes after every commit if
`origin` exists. Claude Code is the default provider; select another with
`--cli claudecode|opencode|codex` or the `provider` key above.

## Backlog

`.atlas/backlog.md` is the task source of truth:

```markdown
## TODO

### AUTH-001: Add sign-in
- **Description:** Authenticate existing users.
- **Acceptance:** Valid credentials create a session; invalid credentials are rejected.

## IN_PROGRESS

## DONE

## DELAYED
```

Each section must appear once, task IDs must be unique, and at most one task may
be IN_PROGRESS. An optional `- **Spec:** .atlas/specs/auth.md` field links a task
to a specification inside the project; `atlas plan` writes both automatically.
Code fences and HTML comments do not count as tasks. The legacy `IN PROGRESS`
heading is also supported.

Atlas resumes IN_PROGRESS before selecting the first TODO. DELAYED tasks are
reported by `atlas status` and are not retried automatically; move a task back
to TODO by hand once you have addressed its `Reason`. Keep tasks small enough
for one agent invocation, with acceptance criteria your gates can verify.

## Commands

| Command | Behavior |
| --- | --- |
| `atlas init` | Create missing `.atlas/` state and configuration |
| `atlas plan "..."` | Run an interactive interview, write a specification, and add tasks |
| `atlas [run] [N]` | Run up to N implementation iterations; default from config, 25 |
| `atlas status [--json]` | Show task counts, the current branch, and DELAYED reasons |
| `atlas help` | Show usage |

`status` is read-only and works while a run holds the lock.

## Branch and delivery

Atlas needs a Git repository with at least one commit; there is no non-Git mode.
If the current branch already starts with `atlas/`, Atlas resumes it. Otherwise
the working tree must be clean outside `.atlas/`, and Atlas creates
`atlas/<YYYYMMDD-HHMM>` from it; pending changes inside `.atlas/` alone (a fresh
`init` or `plan`) are committed as the branch's first commit.

Atlas commits after every task, DONE or DELAYED, and pushes immediately if
`origin` exists: the PR opens on the first push and its body is updated on every
later push, so finished work survives an interrupted run. **Atlas never merges
PRs.** Without `origin`, Atlas commits locally and skips publishing silently.

The base branch is `base` in `.atlas/config.json`, or `origin/HEAD`, or `main`.

## Interruption

Ctrl+C or SIGTERM stops the current attempt and its process group immediately,
without retrying or discarding anything: exit code 130, work kept in place, the
task stays IN_PROGRESS on the same `atlas/*` branch. Run `atlas` again to
continue where it stopped.

| Exit code | Meaning |
| --- | --- |
| `0` | No runnable tasks remain |
| `1` | Invalid configuration, arguments, or a Git/GitHub error |
| `2` | Iteration limit reached with TODO or IN_PROGRESS tasks pending |
| `130` | Interrupted |

## Configuration

```text
.atlas/
  config.json       Provider, limits, retries, and executable gates
  backlog.md        Editable task queue
  guardrails.md     Lessons from observed failures
  progress.txt      Verified task summaries
  specs/            Feature specifications
  runtime.lock      Active run ownership (gitignored)
  runs/             Prompts, logs, and results for each attempt (gitignored)
```

Track the backlog, configuration, guardrails, progress, and specifications in Git.

| Key | Default | Notes |
| --- | --- | --- |
| `provider` | `claudecode` | or `codex`, `opencode`; `--cli` overrides |
| `gates` | `[]` | required; shell commands run from the project root |
| `iterations` | `25` | a positional argument overrides it |
| `timeout` | `1200` | seconds, per agent invocation and per gate |
| `retries` | `3` | attempts per task before it moves to DELAYED |
| `base` | Git fallback above | target branch for the PR |

Limits must be positive integers; unknown configuration keys are rejected.

## Telegram notifications

Set `ATLAS_TELEGRAM_BOT` and `ATLAS_TELEGRAM_CHAT` to get a message from
`notify-telegram.sh` when a run ends. Both variables are required; without
either one, no network call is made.

## Safety

Providers run with broad, non-interactive permissions (e.g.
`--dangerously-skip-permissions`), as in earlier Atlas versions. Use trusted
projects and environments. The runtime lock and branch checks protect
coordination between Atlas runs; they do not isolate a malicious or misbehaving
agent. Interactive planning keeps the provider's normal interactive permissions.

## Development

The runtime uses CommonJS modules and the Node standard library, with no
production dependencies or build step. `lib/cli.js` is the npm `bin` entry point.

```bash
npm ci --ignore-scripts
npm test
npm run check
npm pack --dry-run
```

Tests use fake providers and temporary local Git repositories and remotes. They
cover CLI parsing, retries, DELAYED, publishing, timeouts, signals, and the
dirty-tree rules. They never use real provider credentials, paid agent calls, or
real notifications. CI runs on Linux and macOS with Node 18 and 24.

Keep public repository content, including documentation, examples, commit
messages, and PR titles and descriptions, in English. Keep this README
consistent with the runtime when behavior changes. See [AGENTS.md](AGENTS.md)
for contribution rules.

ISC license.
