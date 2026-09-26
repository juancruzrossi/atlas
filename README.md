# Atlas

**Autonomous Task Loop Agent System.** Atlas works through your Markdown backlog
on its own: one task at a time, a fresh agent for each, verified, committed, and
delivered as its own PR, chained into a native GitHub stack for your review.
Works with Claude Code, Codex, and OpenCode.

## Install

Requirements: Node.js 18+, Git, and an installed, authenticated provider, on
Linux or macOS. Publishing stacked PRs also needs an `origin` remote and an
authenticated GitHub CLI (`gh`); Atlas installs the `gh-stack` extension itself
the first time it needs it.

```bash
npm install -g @jxtools/atlas
```

## Quick start

Run these from your project, starting on its base branch (`main` or similar):

1. `atlas init` (add `--cli codex` or `--cli opencode` to save a provider other
   than the default `claudecode`).
2. `atlas plan "Add authentication"` (interactive) or edit `.atlas/backlog.md` by hand.
3. `atlas 10` - implement and verify up to 10 tasks.

Set verification commands in `.atlas/config.json` (`gates`), e.g. `["npm test"]`,
if you want Atlas to run them before accepting a task as done; with no gates
Atlas relies on the agent's own result.

Atlas creates one `atlas/<run>/<TASK-ID>-<slug>` branch per task, each built on
top of the previous one, and commits `.atlas/` backlog changes together with
the task's own commit; you do not commit them yourself first.

## How a run works

Each iteration:

1. Picks the IN_PROGRESS task, or the first TODO otherwise.
2. Creates `atlas/<run>/<TASK-ID>-<slug>` on top of the current stack (or
   reuses it, if resuming an interrupted task).
3. Starts a fresh agent invocation with the task, its spec, the other backlog
   tasks (for context only, not to implement), and the previous attempt's
   error, if any; Atlas does not resume prior conversations.
4. Requires a JSON result (`status: "done"` or `"blocked"`, plus a
   `verification` note) and every configured gate to pass, if any; a
   completion phrase in the output alone never advances the queue.
5. On failure, retries with the error fed back, up to `retries` attempts.
6. DONE with changes outside `.atlas/`: commits `feat(<ID>): <title>` on the
   task branch, which becomes the new top of the stack, and pushes and
   opens/updates its PR (fixed title and body, chained into the GitHub stack
   with `gh stack link`), if `origin` exists.
7. DONE with no code changes, or exhausted retries (DELAYED with a `Reason`,
   after discarding uncommitted changes): no branch or PR is created; the
   backlog change rides on the top PR's `## Notes` section instead.
8. Repeats with the next task until none remain or the iteration limit hits.

Rerunning `atlas` on an `atlas/<run>/*` branch resumes that run (the current
branch's `<run>` segment is reused). Ctrl+C or SIGTERM stops the current
attempt immediately: exit 130, work kept in place, task still IN_PROGRESS.

Progress is printed to the terminal as one message per task (project, task
counter and bar, ✅/❌, PR link, pending count) and, when configured, the same
message is sent to Telegram; the agent's own output is never shown, only
logged to `.atlas/runs/*.log`.

## Configuration

| Source | Key | Default | Notes |
| --- | --- | --- | --- |
| `.atlas/config.json` | `provider` | `claudecode` | or `codex`, `opencode` |
| `.atlas/config.json` | `gates` | `[]` | optional; shell commands run from the project root; empty means no gates run |
| `.atlas/config.json` | `iterations` | `25` | a positional argument overrides it |
| `.atlas/config.json` | `timeout` | `3600` | seconds, per agent invocation and per gate |
| `.atlas/config.json` | `retries` | `3` | attempts per task before it moves to DELAYED |
| `.atlas/config.json` | `base` | Git fallback: `origin/HEAD`, else `main` | target branch for the PR |
| CLI | `--cli <provider>` | - | sets `provider` for this run and saves it to `config.json` for later runs |
| CLI | positional `N` (`atlas [run] N`) | - | overrides `iterations` for this run |
| Environment | `ATLAS_TELEGRAM_BOT`, `ATLAS_TELEGRAM_CHAT` | unset | both required; sends the same progress message shown in the terminal, after every task and once at the end |

Example `config.json`:

```json
{ "provider": "codex", "iterations": 25, "timeout": 3600, "retries": 3, "gates": ["npm test"] }
```

Limits must be positive integers; unknown configuration keys are rejected.

## Commands

| Command | Behavior |
| --- | --- |
| `atlas init` | Create missing `.atlas/` state and configuration |
| `atlas plan "..."` | Interactive interview, write a specification, add tasks |
| `atlas [run] [N]` | Run up to N implementation iterations |
| `atlas status [--json]` | Show task counts, current branch, DELAYED reasons |
| `atlas help` | Show usage |

`status` is read-only and works while a run holds the lock.

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

- Each of the four sections must appear exactly once; task IDs must be unique.
- At most one task may be IN_PROGRESS at a time; Atlas resumes it before any TODO.
- An optional `- **Spec:** .atlas/specs/auth.md` field links a task to a
  specification inside the project; `atlas plan` writes both automatically.
- Code fences and HTML comments do not count as tasks.
- DELAYED tasks are not retried automatically; move a task back to TODO by
  hand once you have addressed its `Reason`.

## Files in `.atlas/`

```text
config.json                        Provider, limits, retries, and gates
backlog.md                         Editable task queue
specs/                             Feature specifications
runs/runtime.lock                  Active run ownership (gitignored)
runs/<ID>-<attempt>.prompt.md      Prompt sent for that attempt (gitignored)
runs/<ID>-<attempt>.log            Streamed provider/gate output (gitignored)
runs/<ID>-<attempt>.result.json    Provider's JSON result (gitignored)
runs/pr-<ID>.md                    Rendered PR body for that task (gitignored)
```

Track everything except `runs/` in Git.

## Exit codes

| Code | Meaning |
| --- | --- |
| `0` | No runnable tasks remain |
| `1` | Invalid configuration, arguments, or a Git/GitHub error |
| `2` | Iteration limit reached with TODO or IN_PROGRESS tasks pending |
| `130` | Interrupted |

## Safety

Providers run with broad, non-interactive permissions (e.g.
`--dangerously-skip-permissions`); use trusted projects and environments. The
runtime lock and branch checks coordinate Atlas runs, not isolate a misbehaving agent.

## Development

```bash
npm run check
npm pack --dry-run
```

See [AGENTS.md](AGENTS.md) for contribution rules.

ISC license.
