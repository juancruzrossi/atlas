# Atlas

**Autonomous Task Loop Agent System.** Atlas works through your Markdown backlog
on its own: one task at a time, a fresh agent for each, verified, committed, and
pushed to a single PR for your review. Works with Claude Code, Codex, and OpenCode.

## Install

Requirements: Node.js 18+, Git, and an installed, authenticated provider, on
Linux or macOS. PR publication also needs an `origin` remote and an
authenticated GitHub CLI (`gh`).

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

Atlas creates `atlas/<timestamp>` from the current branch (or reuses it if you
are already on one) and commits `.atlas/` changes there itself; you do not
commit them yourself first.

## How a run works

Each iteration:

1. Picks the IN_PROGRESS task, or the first TODO otherwise.
2. Starts a fresh agent invocation with the task, its spec, and the previous
   attempt's error, if any; Atlas does not resume prior conversations.
3. Requires a JSON result (`status: "done"` or `"blocked"`) and every
   configured gate to pass, if any; a completion phrase in the output alone
   never advances the queue.
4. On failure, retries with the error fed back, up to `retries` attempts.
5. DONE: records progress and commits. Exhausted: discards uncommitted
   changes, moves the task to DELAYED with a `Reason`, and commits that.
6. Pushes and opens or updates the PR, if `origin` exists.
7. Repeats with the next task until none remain or the iteration limit hits.

Rerunning `atlas` on the same `atlas/*` branch resumes where it stopped.
Ctrl+C or SIGTERM stops the current attempt immediately: exit 130, work kept
in place, task still IN_PROGRESS.

## Configuration

| Source | Key | Default | Notes |
| --- | --- | --- | --- |
| `.atlas/config.json` | `provider` | `claudecode` | or `codex`, `opencode` |
| `.atlas/config.json` | `gates` | `[]` | optional; shell commands run from the project root; empty means no gates run |
| `.atlas/config.json` | `iterations` | `25` | a positional argument overrides it |
| `.atlas/config.json` | `timeout` | `1200` | seconds, per agent invocation and per gate |
| `.atlas/config.json` | `retries` | `3` | attempts per task before it moves to DELAYED |
| `.atlas/config.json` | `base` | Git fallback: `origin/HEAD`, else `main` | target branch for the PR |
| CLI | `--cli <provider>` | - | sets `provider` for this run and saves it to `config.json` for later runs |
| CLI | positional `N` (`atlas [run] N`) | - | overrides `iterations` for this run |
| Environment | `ATLAS_TELEGRAM_BOT`, `ATLAS_TELEGRAM_CHAT` | unset | both required to send a Telegram message when a run ends normally |

Example `config.json`:

```json
{ "provider": "codex", "iterations": 25, "timeout": 1200, "retries": 3, "gates": ["npm test"] }
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
guardrails.md                      Lessons from observed failures
progress.txt                       Verified task summaries
specs/                             Feature specifications
runtime.lock                       Active run ownership (gitignored)
runs/<ID>-<attempt>.prompt.md      Prompt sent for that attempt (gitignored)
runs/<ID>-<attempt>.log            Streamed provider/gate output (gitignored)
runs/<ID>-<attempt>.result.json    Provider's JSON result (gitignored)
```

Track everything except `runtime.lock` and `runs/` in Git.

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
