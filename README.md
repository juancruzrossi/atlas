# Atlas

Atlas runs a **Ralph loop** over a Markdown backlog: start a coding agent with
fresh context, implement one task, verify the result, save progress, and repeat.
It supports Claude Code, OpenCode, and Codex, in projects with or without Git.

Atlas 4.0.0 owns the loop, task state, verification, and delivery. In Git projects
with an `origin` remote, verified work becomes a single PR left open for review.

## The Ralph loop

The core idea comes from [Geoffrey Huntley's Ralph technique](https://ghuntley.com/ralph/):
repeated coding-agent invocations, fresh context each time, persistent project
files, and tests that provide feedback on generated changes.

Atlas applies that idea with an explicit backlog and a bounded loop:

```text
Select IN_PROGRESS, otherwise the first TODO
  -> Build context from the task, specification, and project files
  -> Start a fresh agent invocation to implement that task
  -> Validate the result and run the project's quality gates
  -> Record DONE and progress; commit in Git mode
  -> Repeat with the next task

Stop when no runnable tasks remain or the iteration limit is reached.
On failure, preserve work and stop; continue explicitly with atlas resume.
```

Each iteration starts a new provider invocation. Atlas does not resume the
previous conversation. It includes the assigned task and its full specification
in the prompt, and asks the agent to read existing project instructions,
guardrails, progress, and recent errors. Source files, `.atlas/` state, and Git
history carry work and lessons between iterations.

The agent implements; Atlas decides when a task is complete. A successful process
exit, a matching JSON result with status `done`, and every configured quality gate
must all pass. A completion phrase in the agent's output cannot advance the queue.
The strength of verification depends on the gates you configure.

Atlas repeats successful iterations automatically, up to the configured limit.
A blocked task, invalid result, failed gate, timeout, or delivery error stops the
run. There is no automatic retry after failure. Recovery uses saved task and
session state through `atlas resume`.

## Install

Requirements: Node.js 18 or newer, Bash, and an installed, authenticated provider.
Supported platforms are Linux and macOS. PR publication also requires Git, an
`origin` remote, and authenticated GitHub CLI (`gh`).

```bash
npm install -g @jxtools/atlas
cd my-project
atlas init
```

`atlas init` creates missing project files without overwriting your backlog or
installing skills in your home directory. The npm installation installs bundled
skills for available providers. It preserves customized skill files and writes
incoming updates alongside them with a `.new` suffix.

This README describes Atlas 4.0.0. For existing installations, see
[Migration from Atlas 3](#migration-from-atlas-3).

## First run

Set the project's real verification commands in `.atlas/config.json`:

```json
{
  "provider": "codex",
  "iterations": 25,
  "timeout": 1200,
  "gateTimeout": 1200,
  "gates": ["npm test", "npm run build"]
}
```

Use commands appropriate to your project. Atlas requires at least one explicit
quality gate to execute tasks and independently runs all gates after each
implementation. Gate commands run sequentially with `/bin/sh` from the project
root. Timeouts are in seconds, per agent invocation and per gate respectively.

Plan tasks in an interactive terminal, or edit the backlog by hand:

```bash
atlas plan "Add authentication"
```

For a Git project, start on your chosen base branch and commit the configuration,
backlog, and any other changes before running Atlas. If `origin` exists, synchronize
that branch with its remote counterpart. For example, after planning on your base:

```bash
git add .atlas/
git commit -m "chore: configure Atlas tasks"
git push origin HEAD
atlas 5
```

Omit the push when there is no remote. In a project without Git, run `atlas 5`
directly after planning. Claude Code remains the default provider; select another
with `--cli claudecode|opencode|codex` or the configuration above.

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
to an existing specification inside the project. Planning creates specifications
and links its tasks automatically. Code fences and HTML comments do not count as
tasks. The legacy `IN PROGRESS` heading is also supported.

Atlas resumes IN_PROGRESS before selecting the first TODO. DELAYED tasks are
reported separately and are not executed. Keep tasks small enough for one agent
invocation, with acceptance criteria that your verification can demonstrate.

## Commands

| Command | Behavior |
| --- | --- |
| `atlas init` | Create missing configuration and state files |
| `atlas plan "..."` | Run an interactive interview, write a specification, and add tasks |
| `atlas [run] [N]` | Run up to N implementation iterations; default 25 |
| `atlas resume [N]` | Resume a saved local or Git session |
| `atlas status [--json]` | Show task counts and session state; JSON also includes lock details |
| `atlas logs [--tail N]` | Summarize recent attempts; default 10 |
| `atlas logs --failed` | Filter recorded unsuccessful attempts |
| `atlas logs --search "text"` | Search logs for literal text, ignoring case |
| `atlas review [--dry-run]` | Run read-only diagnostics without invoking a model |
| `atlas doctor [--json]` | Check configuration, provider availability, and recovery state |
| `atlas clean [--all]` | Remove runtime logs when no unfinished session exists |
| `atlas update` | Print the npm update command |

`status`, `logs`, `doctor`, and `review` support `--json` for automation and can
inspect a project while a run holds its lock. `clean --all` also clears activity
and error history. Cleanup preserves the backlog and session recovery data.

## Git and delivery

Atlas validates configuration and task state, then locks the project against
concurrent runs. A new Git session requires an initial commit, a clean working
tree, and the base branch already checked out. Atlas creates
`integration/atlas-...` from that base. With `origin`, the local base must match
the fetched remote branch before work starts.

Base selection uses `ATLAS_DEFAULT_BRANCH`, `defaultBranch` in configuration,
`origin/HEAD`, or the current branch, in that order. Run Atlas from the repository
root. Git worktrees are supported. Git repositories without `origin` receive
local commits without PR publication; projects without Git keep file changes only.

Atlas commits each verified task. When the loop finishes or reaches its iteration
limit, it pushes completed work and creates or updates one integration PR.
Resuming the session reuses that PR. **Atlas never merges PRs automatically.**

The integration branch stays checked out after completion or failure. Atlas does
not reset, stash, delete branches, or return to the base branch. Review and merge
through your normal workflow, then switch to and synchronize your base before
starting a new session. Atlas refuses a new session while the previous session's
PR is still open.

## Failures and recovery

```bash
atlas status
atlas logs --failed
atlas resume 5
```

An error stops execution and preserves changes. If implementation or verification
failed, the task stays IN_PROGRESS. Resolve the cause, then use `resume` for a fresh
agent attempt and independent verification. In Git mode, resume from the saved
integration branch; Atlas checks its identity and HEAD instead of switching branches.

An interruption during finalization uses the saved checkpoint and reruns gates.
A commit journal supports recovery around `git commit` without duplicating a
completed commit. If only publication failed, resume retries delivery without
running already completed tasks again.

During autonomous execution, Ctrl+C, SIGTERM, and timeouts stop the provider and
its process group. Providers must not leave detached services running. An abrupt
shutdown or SIGKILL can leave a lock behind: `atlas doctor` reports its PID and
host. Confirm that the owner has stopped before removing `.atlas/runtime.lock`.
Interactive planning uses the provider's terminal session, without the autonomous
execution timeout.

| Exit code | Meaning |
| --- | --- |
| `0` | No runnable tasks remain; DELAYED is reported separately |
| `1` | Invalid configuration, state, result, or delivery |
| `2` | Iteration limit reached with pending tasks |
| `124` | Timeout |
| `130` | Interruption |
| Other nonzero code | Provider or gate failure |

Provider and gate exit codes are preserved, including codes listed above. Use
`status` and attempt metadata in `logs` to distinguish failure from a budget pause.

## Configuration and files

```text
.atlas/
  config.json       Provider, limits, and executable gates
  backlog.md        Editable task queue
  guardrails.md     Lessons from observed failures
  progress.txt      Verified task summaries
  specs/            Feature specifications
  session.json      Local session and publication recovery
  runtime.lock      Active run ownership
  activity.log      One JSON event per line
  errors.log        Failure summaries
  runs/             Output, results, and metadata for each attempt
```

Track the backlog, configuration, guardrails, progress, and specifications in Git.
`atlas init` adds exclusions for session, lock, and runtime output in
`.atlas/.gitignore`.

| Setting | Precedence, highest first |
| --- | --- |
| Provider | `--cli`, `ATLAS_CLI`, `provider`, `claudecode` |
| Iterations | Command argument N, `ATLAS_MAX_ITERATIONS`, `iterations`, `25` |
| Agent timeout | `ATLAS_TIMEOUT`, `timeout`, `1200` |
| Gate timeout | `gateTimeout`, `ATLAS_TIMEOUT`, `timeout`, `1200` |
| Base branch | `ATLAS_DEFAULT_BRANCH`, `defaultBranch`, Git fallback described above |
| Quality gates | `gates` in `.atlas/config.json`; required for task execution |

Limits must be positive integers. Unknown configuration keys are rejected.
Telegram notifications require `ATLAS_NOTIFY_TELEGRAM=true`, `ATLAS_TELEGRAM_BOT`,
and `ATLAS_TELEGRAM_CHAT`. They are sent after a run completes or pauses at its
iteration limit, not as failure alerts.

Autonomous providers use broad permissions, as in Atlas 3. Use trusted projects
and environments. Locks and state checks protect coordination; they do not isolate
a malicious agent. Planning retains the provider's interactive permissions.

## Migration from Atlas 3

Atlas 4 changes task and Git ownership and requires explicit migration of active
legacy sessions:

1. Finish or archive your 3.x session's work and integration PR.
2. Keep a copy of `integration-session.json` outside `.atlas/` if you need its
   history, then remove that file from active state.
3. Run `atlas init` to add missing configuration and runtime exclusions. Existing
   backlog, guardrails, and progress are preserved.
4. Configure `gates`, check backlog IDs and sections, and commit changes in Git.
5. Run `atlas doctor`, then `atlas` from the prepared base branch.

Deliberate changes: one integration PR replaces per-task PRs and automatic merges
into integration; `review` diagnoses without model-driven repairs; tasks are never
reset by age; notifications are opt-in; exhausting the iteration limit with pending
tasks returns 2. `ATLAS_STALE_SECONDS` and `ATLAS_SLEEP_BETWEEN` are no longer used.
Gates must be configured explicitly instead of inferred from CLAUDE.md prose.
The agent still reads AGENTS.md and CLAUDE.md for project instructions.

## Development

The runtime uses CommonJS modules and the Node standard library, with no production
dependencies or build step. `atlas.sh` preserves the npm entry point and resolves
symlinks. Modules under `lib/` separate CLI, configuration, backlog, process
supervision, providers, Git, and execution.

```bash
npm ci --ignore-scripts
npm test
npm run check
npm pack --dry-run
```

Tests use simulated providers and temporary local repositories. They cover CLI
execution, failures, timeouts, signals, recovery, PR delivery, and package installation.
They do not use real provider credentials, paid agent calls, or real notifications.
CI runs on Linux and macOS with Node 18 and 24.

Keep public repository content, including documentation, examples, commit messages,
and PR titles and descriptions, in English. Keep this README consistent with the
runtime when behavior changes. See [AGENTS.md](AGENTS.md) for contribution rules and
[context and ownership](references/CONTEXT_ENGINEERING.md) for persistent state roles.

ISC license.
