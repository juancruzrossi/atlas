'use strict'
const fs = require('node:fs')
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
  try {
    execFileSync('git', ['diff', '--cached', '--quiet'], { cwd, stdio: 'ignore' })
    return false
  } catch {
    return true
  }
}

// Reuse the current atlas/* branch, or create a new one from a clean tree.
function prepareBranch(cwd) {
  try {
    git(cwd, 'rev-parse', 'HEAD')
  } catch {
    throw new Error('Atlas needs a Git repository with at least one commit.')
  }
  const branch = currentBranch(cwd)
  if (branch.startsWith('atlas/')) return branch
  if (!cleanOutsideAtlas(cwd)) throw new Error('Commit or stash your changes before running Atlas.')
  const stamp = new Date().toISOString().replace(/[-:]/g, '').replace(/T(\d{2})(\d{2}).*/, '-$1$2')
  const created = `atlas/${stamp}`
  git(cwd, 'switch', '-c', created)
  git(cwd, 'add', '-A', '.atlas')
  if (hasStagedChanges(cwd)) git(cwd, 'commit', '-m', 'chore: update Atlas backlog')
  return created
}

function baseBranch(cwd, config) {
  if (config.base) return config.base
  try {
    return git(cwd, 'symbolic-ref', '--short', 'refs/remotes/origin/HEAD').replace(/^origin\//, '')
  } catch {
    return 'main'
  }
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

function hasRemote(cwd) {
  try {
    git(cwd, 'remote', 'get-url', 'origin')
    return true
  } catch {
    return false
  }
}

// Push the branch and open or update its PR. Never throws: publishing is
// best-effort and retried after the next task on failure.
function publish(cwd, branch, base, body) {
  if (!hasRemote(cwd)) return null
  try {
    git(cwd, 'push', '-u', 'origin', branch)
    const bodyFile = `${cwd}/.atlas/runs/pr-body.md`
    fs.writeFileSync(bodyFile, body)
    let existing = null
    try {
      existing = JSON.parse(gh(cwd, 'pr', 'view', branch, '--json', 'url,state'))
    } catch {
      existing = null
    }
    if (!existing || existing.state !== 'OPEN') {
      gh(cwd, 'pr', 'create', '--base', base, '--head', branch, '--title', `feat: Atlas run ${branch.replace(/^atlas\//, '')}`, '--body-file', bodyFile)
      existing = JSON.parse(gh(cwd, 'pr', 'view', branch, '--json', 'url,state'))
    } else {
      gh(cwd, 'pr', 'edit', branch, '--body-file', bodyFile)
    }
    return existing.url
  } catch (error) {
    console.warn(`Publish failed: ${error.message}; will retry after the next task.`)
    return null
  }
}

module.exports = { git, gh, currentBranch, cleanOutsideAtlas, prepareBranch, baseBranch, commitAll, discardChanges, hasRemote, publish }
