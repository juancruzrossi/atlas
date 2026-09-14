'use strict'
const { execFileSync } = require('node:child_process')
const { writeJson } = require('./storage')
function command(cwd, bin, args, optional = false) {
  try { return execFileSync(bin, args, { cwd, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], timeout: 30000 }).trim() } catch (error) {
    if (optional) return null
    throw new Error(`${bin} ${args[0]} failed: ${error.stderr?.toString().trim() || error.message}`)
  }
}
function git(cwd, args, optional = false) { return command(cwd, 'git', args, optional) }
function inspect(cwd) {
  if (git(cwd, ['rev-parse', '--is-inside-work-tree'], true) !== 'true') return null
  const root = git(cwd, ['rev-parse', '--show-toplevel'])
  if (require('node:fs').realpathSync(root) !== require('node:fs').realpathSync(cwd)) throw new Error(`Run Atlas from the repository root: ${root}`)
  return { branch: git(cwd, ['branch', '--show-current']), head: git(cwd, ['rev-parse', 'HEAD'], true), remote: git(cwd, ['remote', 'get-url', 'origin'], true) }
}
function clean(cwd) { return git(cwd, ['status', '--porcelain']).length === 0 }
function assertHead(cwd, session) {
  if (git(cwd, ['branch', '--show-current']) !== session.branch || git(cwd, ['rev-parse', 'HEAD']) !== session.head) throw new Error('Git branch or HEAD changed outside Atlas. Restore the session branch and HEAD before resuming.')
}
function prState(cwd, session) {
  if (!session.remote) return
  if (!session.pr_number) return
  const pr = JSON.parse(command(cwd, 'gh', ['pr', 'view', String(session.pr_number), '--json', 'state,headRefName,baseRefName']))
  if (pr.state !== 'OPEN' || pr.headRefName !== session.branch || pr.baseRefName !== session.base) throw new Error('Session PR is closed, merged, or targets a different branch. Inspect it before starting another session.')
}
function begin(cwd, id, config) {
  const repo = inspect(cwd)
  if (!repo) return { mode: 'local' }
  if (!repo.head) throw new Error('Create an initial Git commit before running Atlas.')
  if (!clean(cwd)) throw new Error('Commit or stash existing changes before starting Atlas (including .atlas/).')
  const base = config.defaultBranch || git(cwd, ['symbolic-ref', '--short', 'refs/remotes/origin/HEAD'], true)?.replace(/^origin\//, '') || repo.branch
  if (!base || base.startsWith('integration/atlas-')) throw new Error('Set defaultBranch in .atlas/config.json before starting a new session here.')
  git(cwd, ['check-ref-format', '--branch', base])
  if (repo.branch !== base) throw new Error(`Switch to ${base} before starting a new session so its configuration and backlog match the base.`)
  if (repo.remote) {
    command(cwd, 'gh', ['auth', 'status'])
    git(cwd, ['fetch', 'origin', base])
    if (git(cwd, ['rev-parse', base]) !== git(cwd, ['rev-parse', 'FETCH_HEAD'])) throw new Error(`Local ${base} differs from origin. Synchronize it before starting Atlas.`)
  }
  const branch = `integration/atlas-${id}`
  git(cwd, ['switch', '-c', branch, base])
  return { mode: 'git', branch, base, head: git(cwd, ['rev-parse', 'HEAD']), remote: repo.remote }
}
function commit(cwd, session, sessionFile, message) {
  assertHead(cwd, session)
  git(cwd, ['add', '-A'])
  if (git(cwd, ['diff', '--cached', '--quiet'], true) !== null) return
  session.pendingCommit = { parent: session.head, tree: git(cwd, ['write-tree']), message }
  writeJson(sessionFile, session)
  finishCommit(cwd, session, sessionFile)
}
function finishCommit(cwd, session, sessionFile) {
  const pending = session.pendingCommit
  if (!pending) return
  if (git(cwd, ['branch', '--show-current']) !== session.branch) throw new Error('Restore the integration branch before recovering the pending commit.')
  const head = git(cwd, ['rev-parse', 'HEAD'])
  if (head === pending.parent) {
    if (git(cwd, ['write-tree']) !== pending.tree || git(cwd, ['diff', '--quiet'], true) === null || git(cwd, ['ls-files', '--others', '--exclude-standard'])) throw new Error('Files changed during commit recovery. Restore the staged checkpoint before resuming.')
    git(cwd, ['commit', '-m', pending.message])
  } else if (git(cwd, ['rev-parse', 'HEAD^']) !== pending.parent || git(cwd, ['rev-parse', 'HEAD^{tree}']) !== pending.tree) {
    throw new Error('HEAD does not match the pending Atlas commit.')
  }
  session.head = git(cwd, ['rev-parse', 'HEAD'])
  delete session.pendingCommit
  writeJson(sessionFile, session)
}
function publish(cwd, session, sessionFile, bodyFile) {
  if (!session.remote) return
  assertHead(cwd, session)
  if (!clean(cwd)) throw new Error('Uncommitted changes remain; refusing to publish.')
  prState(cwd, session)
  git(cwd, ['push', '-u', 'origin', session.branch])
  if (!session.pr_number) {
    const prs = JSON.parse(command(cwd, 'gh', ['pr', 'list', '--head', session.branch, '--base', session.base, '--state', 'all', '--json', 'number,state']))
    if (prs.some(pr => pr.state !== 'OPEN')) throw new Error('A closed or merged PR already exists for this session.')
    const existing = prs.find(pr => pr.state === 'OPEN')
    if (!existing) command(cwd, 'gh', ['pr', 'create', '--base', session.base, '--head', session.branch, '--title', `feat: Atlas session ${session.id}`, '--body-file', bodyFile])
    const pr = JSON.parse(command(cwd, 'gh', ['pr', 'view', session.branch, '--json', 'number,url']))
    session.pr_number = pr.number
    session.pr_url = pr.url
    writeJson(sessionFile, session)
  } else {
    command(cwd, 'gh', ['pr', 'edit', String(session.pr_number), '--body-file', bodyFile])
  }
}
module.exports = { command, git, inspect, clean, assertHead, prState, begin, commit, finishCommit, publish }
