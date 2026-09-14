'use strict'
const fs = require('node:fs')
const path = require('node:path')
const os = require('node:os')
const { randomUUID } = require('node:crypto')
const storage = require('./storage')
const backlog = require('./backlog')
const { config } = require('./config')
const { bins, run: runProvider, available } = require('./providers')
const { loadSession } = require('./runner')
const git = require('./git')
const home = path.resolve(__dirname, '..')
const runtimeIgnore = ['runs/', 'activity.log', 'errors.log', 'session.json', 'runtime.lock', '*.tmp']
function init(cwd) {
  const dir = path.join(cwd, '.atlas')
  fs.mkdirSync(path.join(dir, 'runs'), { recursive: true })
  for (const [name, content] of Object.entries({
    'backlog.md': storage.read(path.join(home, 'templates/backlog.md')).replaceAll('[PROJECT_NAME]', path.basename(cwd)),
    'guardrails.md': storage.read(path.join(home, 'templates/guardrails.md')),
    'progress.txt': storage.read(path.join(home, 'templates/progress.txt')),
    'activity.log': '', 'errors.log': '',
    'config.json': JSON.stringify({ provider: 'claudecode', iterations: 25, timeout: 1200, gates: [] }, null, 2) + '\n',
  })) {
    const file = path.join(dir, name)
    if (!fs.existsSync(file)) storage.atomicWrite(file, content)
  }
  const ignoreFile = path.join(dir, '.gitignore')
  const ignore = storage.read(ignoreFile)
  const missing = runtimeIgnore.filter(entry => !ignore.split('\n').includes(entry))
  if (missing.length) storage.atomicWrite(ignoreFile, ignore.trimEnd() + '\n' + missing.join('\n') + '\n')
  console.log(`✓ Initialized .atlas/ in ${cwd}\nAdd tasks to .atlas/backlog.md and quality gate commands to .atlas/config.json.`)
}
function status(cwd) {
  const dir = path.join(cwd, '.atlas')
  const session = loadSession(path.join(dir, 'session.json'))
  return { project: path.basename(cwd), tasks: backlog.counts(backlog.load(path.join(dir, 'backlog.md'))), session, lock: storage.json(path.join(dir, 'runtime.lock')) }
}
function doctor(cwd, options) {
  const checks = []
  const check = (name, fn) => {
    try { const detail = fn(); checks.push({ name, ok: true, detail }) } catch (error) { checks.push({ name, ok: false, detail: error.message }) }
  }
  let conf
  check('Configuration', () => { conf = config(cwd, options); return 'valid' })
  if (conf) check('Provider', () => { if (!available(bins[conf.provider])) throw new Error(`${bins[conf.provider]} not found`); return conf.provider })
  check('Package', () => {
    for (const name of ['prompt.md', 'plan_prompt.md', 'review_prompt.md']) if (!fs.existsSync(path.join(home, name))) throw new Error(`Missing ${name}`)
    return 'prompts present'
  })
  if (fs.existsSync(path.join(cwd, '.atlas'))) {
    check('Backlog', () => JSON.stringify(backlog.counts(backlog.load(path.join(cwd, '.atlas/backlog.md')))))
    check('Quality gates', () => { if (!conf?.gates.length) throw new Error('Set gates in .atlas/config.json'); return conf.gates.join(', ') })
    check('Lock', () => {
      const lock = storage.json(path.join(cwd, '.atlas/runtime.lock'))
      if (!lock) return 'unlocked'
      let alive = true
      if (lock.host === os.hostname() && Number.isSafeInteger(lock.pid) && lock.pid > 0) {
        try { process.kill(lock.pid, 0) } catch (error) { if (error.code === 'ESRCH') alive = false }
      }
      throw new Error(alive ? `Owner PID ${lock.pid} on ${lock.host}; verify before removing lock` : `Owner PID ${lock.pid} has stopped; remove .atlas/runtime.lock to recover`)
    })
    check('Session', () => {
      if (fs.existsSync(path.join(cwd, '.atlas/integration-session.json'))) throw new Error('Legacy session needs migration; see README')
      const session = loadSession(path.join(cwd, '.atlas/session.json'))
      if (session?.mode === 'git') { git.assertHead(cwd, session); git.prState(cwd, session) }
      return session?.status || 'none'
    })
  }
  const repo = git.inspect(cwd)
  if (repo?.remote) check('GitHub CLI', () => { git.command(cwd, 'gh', ['auth', 'status']); return 'authenticated' })
  return checks
}
function logs(cwd, options) {
  const dir = path.join(cwd, '.atlas/runs')
  const files = fs.existsSync(dir) ? fs.readdirSync(dir).filter(f => f.endsWith('.log')) : []
  const entries = files.map(file => {
    const log = path.join(dir, file)
    const meta = storage.json(log.replace(/\.log$/, '.json'))
    const text = storage.read(log)
    return { file, time: fs.statSync(log).mtimeMs, task: meta?.task || text.match(/^Task:\s*(.+)$/m)?.[1] || '(no summary)', status: meta?.status || text.match(/^Status:\s*(.+)$/m)?.[1] || 'unknown', exitCode: meta?.exitCode, durationMs: meta?.durationMs, text }
  }).sort((a, b) => b.time - a.time || b.file.localeCompare(a.file))
  return { total: entries.length, entries: entries.filter(e => (!options.failed || /fail|error|skip|unknown/i.test(e.status)) && (!options.search || e.text.toLowerCase().includes(options.search.toLowerCase()))).slice(0, options.tail ?? 10).map(({ text, ...entry }) => entry) }
}
function clean(cwd, all) {
  const dir = path.join(cwd, '.atlas')
  const session = loadSession(path.join(dir, 'session.json'))
  if (session && session.status !== 'complete') throw new Error("An unfinished session exists; resume it before cleaning its recovery evidence.")
  const runs = path.join(dir, 'runs')
  let removed = 0
  if (fs.existsSync(runs)) for (const name of fs.readdirSync(runs)) {
    const file = path.join(runs, name)
    if (fs.lstatSync(file).isFile() && /\.(log|json|md|txt|tmp)$/.test(name)) { fs.unlinkSync(file); removed++ }
  }
  for (const name of fs.readdirSync(dir)) if (name.endsWith('.tmp') && fs.lstatSync(path.join(dir, name)).isFile()) fs.unlinkSync(path.join(dir, name))
  if (all) for (const name of ['activity.log', 'errors.log']) storage.atomicWrite(path.join(dir, name), '')
  console.log(`✓ Atlas clean completed\nRemoved run logs: ${removed}\nSession metadata retained for PR recovery.`)
}
async function plan(cwd, options, conf, signal) {
  if (!available(bins[conf.provider])) throw new Error(`${bins[conf.provider]} not found`)
  if (!process.stdin.isTTY) throw new Error('atlas plan requires an interactive terminal')
  const dir = path.join(cwd, '.atlas')
  fs.mkdirSync(path.join(dir, 'specs'), { recursive: true })
  const beforeTasks = backlog.load(path.join(dir, 'backlog.md')).tasks
  const protectedFiles = ['config.json', 'session.json', 'runtime.lock'].map(name => path.join(dir, name))
  const beforeState = protectedFiles.map(file => storage.read(file, null))
  const beforeGit = git.inspect(cwd)
  const tag = randomUUID()
  const spec = `.atlas/specs/spec-${tag}.md`
  const file = path.join(dir, 'runs', `plan-${tag}.prompt.md`)
  const prompt = `${storage.read(path.join(home, 'plan_prompt.md'))}\n\nProject: ${cwd}\nFeature: ${options.args.join(' ')}\nSpec output: ${spec}\nBacklog: .atlas/backlog.md\n`
  storage.atomicWrite(file, prompt)
  try {
    const result = await runProvider(conf.provider, 'plan', file, { cwd, signal })
    if (result.code !== 0) return result.code
    const afterTasks = backlog.load(path.join(dir, 'backlog.md')).tasks
    for (const task of beforeTasks) {
      const after = afterTasks.find(t => t.id === task.id)
      if (!after || after.state !== task.state || after.body !== task.body) throw new Error(`Planner changed existing task ${task.id}; inspect the backlog.`)
    }
    for (let i = 0; i < protectedFiles.length; i++) if (storage.read(protectedFiles[i], null) !== beforeState[i]) throw new Error('Planner modified Atlas runtime/configuration; inspect the changes.')
    const afterGit = git.inspect(cwd)
    if (JSON.stringify(beforeGit) !== JSON.stringify(afterGit)) throw new Error('Planner changed Git state; inspect the changes.')
    if (!afterTasks.some(t => !beforeTasks.some(before => before.id === t.id) && t.state === 'TODO' && t.spec === spec)) throw new Error('Planning ended without adding TODO tasks linked to the new specification.')
    if (!storage.read(path.join(cwd, spec)).trim()) throw new Error('Planning ended without writing the feature specification.')
    console.log(`Spec written: ${spec}`)
    return 0
  } finally { fs.rmSync(file, { force: true }) }
}
module.exports = { init, status, doctor, logs, clean, plan, available }
