'use strict'
const { execFileSync } = require('node:child_process')

function run(cwd, bin, args) {
  try {
    return execFileSync(bin, args, { cwd, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }).trim()
  } catch (error) {
    throw new Error(`${bin} ${args[0]} failed: ${error.stderr?.toString().trim() || error.message}`)
  }
}

function git(cwd, ...args) { return run(cwd, 'git', args) }
function gh(cwd, ...args) { return run(cwd, 'gh', args) }
// Returns null instead of throwing, for commands whose failure is an answer.
function attempt(fn) { try { return fn() } catch { return null } }

function currentBranch(cwd) { return git(cwd, 'branch', '--show-current') }

// True when every pending change is inside .atlas/ (or there is none at all).
// Porcelain lines start with a significant leading space, so read the raw
// status output instead of the trimmed helper above.
function cleanOutsideAtlas(cwd) {
  const raw = execFileSync('git', ['status', '--porcelain'], { cwd, encoding: 'utf8' })
  const lines = raw.split('\n').filter(Boolean)
  return lines.every(line => line.slice(3).startsWith('.atlas'))
}

function hasStagedChanges(cwd) {
  return attempt(() => git(cwd, 'diff', '--cached', '--quiet')) === null
}

function baseBranch(cwd, config) {
  const remoteHead = attempt(() => git(cwd, 'symbolic-ref', '--short', 'refs/remotes/origin/HEAD'))
  return config.base || remoteHead?.replace(/^origin\//, '') || 'main'
}

function commitAll(cwd, message) {
  git(cwd, 'add', '-A')
  if (hasStagedChanges(cwd)) git(cwd, 'commit', '-m', message)
}

// Ignored paths such as .atlas/runs/ are left alone by `git clean` without -x.
function discardChanges(cwd) {
  git(cwd, 'reset', '--hard', 'HEAD')
  git(cwd, 'clean', '-fd')
}

// Reuse the current run when already on one of its task branches, otherwise
// start a new one from the current (clean-outside-.atlas) branch.
function currentRun(cwd, config) {
  const branch = currentBranch(cwd)
  const base = baseBranch(cwd, config)
  const match = branch.match(/^atlas\/([^/]+)\//)
  if (match) return { run: match[1], top: branch, base }
  if (!cleanOutsideAtlas(cwd)) throw new Error('Commit or stash your changes before running Atlas.')
  const stamp = new Date().toISOString().replace(/[-:]/g, '').replace(/T(\d{2})(\d{2}).*/, '-$1$2')
  return { run: stamp, top: branch, base }
}

// lowercase, non-alphanumeric -> '-', trimmed, cut at a '-' boundary near 40 chars.
function slug(title) {
  const clean = title.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '')
  if (clean.length <= 40) return clean
  const cut = clean.slice(0, 40)
  const lastDash = cut.lastIndexOf('-')
  return lastDash > 0 ? cut.slice(0, lastDash) : cut
}

function taskBranch(run, task) {
  return `atlas/${run}/${task.id}-${slug(task.title)}`
}

// Bottom-to-top branches of the run's stack, derived from commit ancestry
// (no state file: each branch is built on top of the previous one).
function stackBranches(cwd, run, base) {
  const refs = attempt(() => git(cwd, 'for-each-ref', '--format=%(refname:short)', `refs/heads/atlas/${run}/`)) || ''
  const branches = refs.split('\n').filter(Boolean)
  return branches
    .map(branch => ({ branch, depth: Number(git(cwd, 'rev-list', '--count', `${base}..${branch}`)) }))
    .sort((a, b) => a.depth - b.depth)
    .map(b => b.branch)
}

// The task ID and title from a stack branch's own `feat(<ID>): <title>`
// commit; a later `chore(...)` (Q6) may sit on top of it, so search history
// instead of assuming it is the branch tip.
function branchTask(cwd, branch) {
  const subject = git(cwd, 'log', branch, '--grep=^feat(', '-1', '--format=%s')
  const match = subject.match(/^feat\(([^)]+)\):\s*(.+)$/)
  if (!match) throw new Error(`Stack branch ${branch} has no feat() commit: ${subject}`)
  return { id: match[1], title: match[2] }
}

function ensureGhStack(cwd) {
  const list = attempt(() => gh(cwd, 'extension', 'list')) || ''
  if (!list.includes('gh-stack')) gh(cwd, 'extension', 'install', 'github/gh-stack')
}

function prNumber(cwd, branch) {
  return attempt(() => JSON.parse(gh(cwd, 'pr', 'view', branch, '--json', 'number')).number)
}

// Create the PR if none is open yet, otherwise refresh its body.
function publishPr(cwd, branch, base, title, bodyFile) {
  const state = attempt(() => JSON.parse(gh(cwd, 'pr', 'view', branch, '--json', 'state')).state)
  if (state === 'OPEN') gh(cwd, 'pr', 'edit', branch, '--body-file', bodyFile)
  else gh(cwd, 'pr', 'create', '--base', base, '--head', branch, '--title', title, '--body-file', bodyFile)
}

function stackLink(cwd, branches) {
  try {
    gh(cwd, 'stack', 'link', ...branches)
  } catch (error) {
    console.warn(`stack link failed; PRs are still chained: ${error.message}`)
  }
}

module.exports = {
  git, gh, attempt, currentBranch, cleanOutsideAtlas, baseBranch, commitAll, discardChanges,
  currentRun, slug, taskBranch, stackBranches, branchTask, ensureGhStack, prNumber, publishPr, stackLink,
}
