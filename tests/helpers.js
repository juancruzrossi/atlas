'use strict'
const fs = require('node:fs')
const path = require('node:path')
const os = require('node:os')
const { spawnSync, spawn } = require('node:child_process')
const root = path.resolve(__dirname, '..')
const cli = path.join(root, 'lib/cli.js')
function fixture(t, options = {}) {
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'atlas test-'))
  const cwd = path.join(temp, 'project & $literal')
  const bin = path.join(temp, 'bin')
  const home = path.join(temp, 'home')
  for (const dir of [cwd, bin, home]) fs.mkdirSync(dir)
  const env = { ...process.env, HOME: home, GH_CONFIG_DIR: path.join(home, '.gh'), PATH: `${bin}:${process.env.PATH}`, ATLAS_CLI: 'claudecode', ATLAS_NOTIFY_TELEGRAM: 'false' }
  for (const key of ['ATLAS_MAX_ITERATIONS', 'ATLAS_TIMEOUT', 'ATLAS_DEFAULT_BRANCH', 'GIT_DIR', 'GIT_WORK_TREE', 'GIT_INDEX_FILE']) delete env[key]
  Object.assign(env, { GIT_AUTHOR_NAME: 'Atlas Test', GIT_AUTHOR_EMAIL: 'atlas@example.test', GIT_COMMITTER_NAME: 'Atlas Test', GIT_COMMITTER_EMAIL: 'atlas@example.test', GIT_CONFIG_NOSYSTEM: '1', GIT_CONFIG_GLOBAL: '/dev/null' })
  for (const provider of ['claude', 'codex', 'opencode']) fs.writeFileSync(path.join(bin, provider), `#!${process.execPath}\n` + fs.readFileSync(path.join(__dirname, 'provider-fixture.js'), 'utf8'), { mode: 0o755 })
  fs.writeFileSync(path.join(bin, 'gh'), `#!${process.execPath}\n` + fs.readFileSync(path.join(__dirname, 'github-fixture.js'), 'utf8'), { mode: 0o755 })
  function call(args = [], overrides = {}) { return spawnSync(process.execPath, [cli, ...args], { cwd, env: { ...env, ...overrides }, encoding: 'utf8', timeout: 15000 }) }
  function start(args = [], overrides = {}) { return spawn(process.execPath, [cli, ...args], { cwd, env: { ...env, ...overrides }, stdio: ['ignore', 'pipe', 'pipe'] }) }
  function git(...args) {
    const r = spawnSync('git', args, { cwd, env, encoding: 'utf8' })
    if (r.status !== 0) throw new Error(r.stderr)
    return r.stdout.trim()
  }
  function write(file, content) { fs.writeFileSync(path.join(cwd, file), typeof content === 'string' ? content : JSON.stringify(content, null, 2) + '\n') }
  function read(file) { return fs.readFileSync(path.join(cwd, file), 'utf8') }
  function json(file) { return JSON.parse(read(file)) }
  t.after(() => fs.rmSync(temp, { recursive: true, force: true }))
  call(['init'])
  fs.appendFileSync(path.join(cwd, '.atlas/.gitignore'), 'provider-calls\ngithub-calls\nfake-pr\nchild-pid\n')
  write('.atlas/config.json', { gates: ['test -f implementation.txt'], timeout: 2 })
  write('.atlas/backlog.md', '# Tasks\n\n## TODO\n\n### T-1: First task\n- **Acceptance:** implementation.txt exists\n\n## IN_PROGRESS\n\n## DONE\n\n## DELAYED\n')
  if (options.git) { git('init', '-b', 'main'); git('add', '.'); git('commit', '-m', 'chore: initial') }
  if (options.remote) {
    const remote = path.join(temp, 'remote.git')
    git('init', '--bare', remote)
    git('remote', 'add', 'origin', remote)
    git('push', '-u', 'origin', 'main')
    git('symbolic-ref', 'refs/remotes/origin/HEAD', 'refs/remotes/origin/main')
  }
  return { temp, cwd, env, bin, call, start, git, write, read, json }
}
async function waitFor(fn, timeout = 5000) {
  const start = Date.now()
  while (!fn()) {
    if (Date.now() - start > timeout) throw new Error('Condition timed out')
    await new Promise(resolve => setTimeout(resolve, 20))
  }
}
function finished(child) {
  let output = ''
  child.stdout.on('data', data => { output += data })
  child.stderr.on('data', data => { output += data })
  return new Promise(resolve => child.once('close', (code, signal) => resolve({ code, signal, output })))
}
module.exports = { fixture, waitFor, finished, root }
