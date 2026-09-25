#!/usr/bin/env node
'use strict'
const fs = require('node:fs')
const path = require('node:path')
const os = require('node:os')
const { randomUUID } = require('node:crypto')
const backlog = require('./backlog')
const agent = require('./agent')
const git = require('./git')
const loop = require('./loop')
const pkg = require('../package.json')

const atlasHome = path.resolve(__dirname, '..')
const CONFIG_KEYS = ['provider', 'gates', 'iterations', 'timeout', 'retries', 'base']
const DEFAULT_CONFIG = { provider: 'claudecode', gates: [], iterations: 25, timeout: 1200, retries: 3 }

const HELP = `Atlas v${pkg.version} - a small, retrying Ralph loop

Usage: atlas [options] [command]

  atlas init                  Create .atlas/ project state and configuration
  atlas plan <description>    Interview, write a spec, and add tasks
  atlas [run] [iterations]    Implement and verify one task at a time
  atlas status [--json]       Show task counts and current branch
  atlas help                  Show this help

Options:
  --cli <provider>            claudecode (default), opencode, or codex
  --version, -v                Show installed version
  --help, -h                   Show help

Configuration: .atlas/config.json. Exit codes: 0 done, 1 error, 2 iteration
limit reached with tasks pending, 130 interrupted.
`

function integer(value, name, min, max = 2147483647) {
  if (!/^\d+$/.test(String(value)) || Number(value) < min || Number(value) > max) throw new Error(`${name} must be an integer between ${min} and ${max}`)
  return Number(value)
}

function parseArgs(args) {
  const options = { args: [] }
  for (let i = 0; i < args.length; i++) {
    const arg = args[i]
    if (arg === '--cli') {
      const value = args[++i]
      if (!value || !(value in agent.PROVIDERS)) throw new Error("--cli requires 'claudecode', 'opencode', or 'codex'")
      options.cli = value
    } else if (['--help', '-h'].includes(arg)) options.help = true
    else if (['--version', '-v'].includes(arg)) options.version = true
    else if (arg === '--json') options.json = true
    else if (arg.startsWith('-')) throw new Error(`Unknown option: ${arg}`)
    else options.args.push(arg)
  }
  if (options.version) return { ...options, command: 'version' }
  if (options.help) return { ...options, command: 'help' }
  const first = options.args[0]
  const command = !first || /^\d+$/.test(first) ? 'run' : options.args.shift()
  if (!['init', 'run', 'plan', 'status', 'help'].includes(command)) throw new Error(`Unknown command '${command}'. Run 'atlas help' for usage.`)
  if (command === 'run') {
    if (options.args.length > 1) throw new Error('Usage: atlas [run] [iterations]')
    if (options.args[0] !== undefined) options.iterations = integer(options.args[0], 'iterations', 1)
  } else if (command === 'plan') {
    if (!options.args.length) throw new Error('Usage: atlas plan <description>')
  } else if (options.args.length) throw new Error(`Unexpected arguments for atlas ${command}`)
  return { ...options, command }
}

function loadConfig(cwd, options) {
  const file = path.join(cwd, '.atlas/config.json')
  let saved = {}
  if (fs.existsSync(file)) {
    try {
      saved = JSON.parse(fs.readFileSync(file, 'utf8'))
    } catch {
      throw new Error(`Invalid config: ${file}`)
    }
  }
  if (!saved || typeof saved !== 'object' || Array.isArray(saved)) throw new Error(`Invalid config: ${file}`)
  for (const key of Object.keys(saved)) if (!CONFIG_KEYS.includes(key)) throw new Error(`Unknown config key: ${key}`)
  const provider = options.cli || saved.provider || DEFAULT_CONFIG.provider
  if (!(provider in agent.PROVIDERS)) throw new Error(`config.provider must be 'claudecode', 'opencode', or 'codex', got '${provider}'`)
  const gates = saved.gates ?? DEFAULT_CONFIG.gates
  if (!Array.isArray(gates) || gates.some(g => typeof g !== 'string' || !g.trim())) throw new Error('config.gates must be an array of nonempty shell commands')
  if (saved.base !== undefined && (typeof saved.base !== 'string' || !saved.base.trim())) throw new Error('config.base must be a nonempty string')
  return {
    provider, gates, base: saved.base,
    iterations: integer(options.iterations ?? saved.iterations ?? DEFAULT_CONFIG.iterations, 'iterations', 1),
    timeout: integer(saved.timeout ?? DEFAULT_CONFIG.timeout, 'timeout', 1),
    retries: integer(saved.retries ?? DEFAULT_CONFIG.retries, 'retries', 1),
  }
}

function init(cwd) {
  const dir = path.join(cwd, '.atlas')
  fs.mkdirSync(path.join(dir, 'runs'), { recursive: true })
  fs.mkdirSync(path.join(dir, 'specs'), { recursive: true })
  const files = {
    'backlog.md': fs.readFileSync(path.join(atlasHome, 'templates/backlog.md'), 'utf8').replaceAll('[PROJECT_NAME]', path.basename(cwd)),
    'guardrails.md': fs.readFileSync(path.join(atlasHome, 'templates/guardrails.md'), 'utf8'),
    'progress.txt': fs.readFileSync(path.join(atlasHome, 'templates/progress.txt'), 'utf8'),
    'config.json': JSON.stringify(DEFAULT_CONFIG, null, 2) + '\n',
    '.gitignore': 'runs/\nruntime.lock\n',
  }
  for (const [name, content] of Object.entries(files)) {
    const file = path.join(dir, name)
    if (!fs.existsSync(file)) fs.writeFileSync(file, content)
  }
  console.log(`Initialized .atlas/ in ${cwd}\nAdd tasks to .atlas/backlog.md and quality gate commands to .atlas/config.json.`)
}

function status(cwd) {
  const dir = path.join(cwd, '.atlas')
  const loaded = backlog.load(path.join(dir, 'backlog.md'))
  const counts = backlog.counts(loaded)
  const delayed = loaded.tasks.filter(t => t.state === 'DELAYED')
  let branch = null
  try {
    branch = git.currentBranch(cwd)
  } catch {
    branch = null
  }
  return { project: path.basename(cwd), tasks: counts, branch, delayed: delayed.map(t => ({ id: t.id, title: t.title, reason: t.body.match(/^- \*\*Reason:\*\*\s*(.+)$/m)?.[1] })) }
}

function printStatus(state) {
  const tasks = Object.entries(state.tasks).map(([key, value]) => `${key}=${value}`).join('  ')
  const delayed = state.delayed.length ? `\nDelayed:\n${state.delayed.map(t => `  ${t.id}: ${t.reason || t.title}`).join('\n')}` : ''
  return `Atlas Status - ${state.project}\nBranch: ${state.branch || '(none)'}\nTasks: ${tasks}${delayed}`
}

async function plan(cwd, description, provider, signal) {
  if (!agent.hasBinary(provider)) throw new Error(`${agent.PROVIDERS[provider].bin} not found on PATH.`)
  if (!process.stdin.isTTY) throw new Error('atlas plan requires an interactive terminal')
  const dir = path.join(cwd, '.atlas')
  fs.mkdirSync(path.join(dir, 'specs'), { recursive: true })
  const before = backlog.load(path.join(dir, 'backlog.md')).tasks
  const tag = randomUUID()
  const spec = `.atlas/specs/${tag}.md`
  const promptFile = path.join(dir, 'runs', `plan-${tag}.prompt.md`)
  const prompt = `${fs.readFileSync(path.join(atlasHome, 'plan_prompt.md'), 'utf8')}\n\nProject: ${cwd}\nFeature: ${description}\nSpec output: ${spec}\n`
  fs.writeFileSync(promptFile, prompt)
  try {
    const result = await agent.runInteractive(provider, promptFile, cwd)
    if (result.code !== 0) return result.code
    const after = backlog.load(path.join(dir, 'backlog.md')).tasks
    for (const task of before) {
      const match = after.find(t => t.id === task.id)
      if (!match || match.state !== task.state || match.body !== task.body) throw new Error(`Planner changed existing task ${task.id}; inspect the backlog.`)
    }
    if (!after.some(t => !before.some(b => b.id === t.id) && t.state === 'TODO')) throw new Error('Planning ended without adding TODO tasks.')
    console.log(`Spec written: ${spec}`)
    return 0
  } finally {
    fs.rmSync(promptFile, { force: true })
  }
}

function acquireLock(dir) {
  const file = path.join(dir, 'runtime.lock')
  const token = randomUUID()
  try {
    fs.writeFileSync(file, JSON.stringify({ pid: process.pid, host: os.hostname(), token }), { flag: 'wx' })
  } catch (error) {
    if (error.code !== 'EEXIST') throw error
    const existing = JSON.parse(fs.readFileSync(file, 'utf8'))
    let alive = true
    if (existing.host === os.hostname()) {
      try {
        process.kill(existing.pid, 0)
      } catch {
        alive = false
      }
    }
    if (alive) throw new Error(`Atlas is locked by PID ${existing.pid} on ${existing.host}. Remove ${file} only after its owner has stopped.`)
    fs.writeFileSync(file, JSON.stringify({ pid: process.pid, host: os.hostname(), token }), { flag: 'w' })
  }
  return () => {
    try {
      if (JSON.parse(fs.readFileSync(file, 'utf8')).token === token) fs.unlinkSync(file)
    } catch {
      // Lock already gone.
    }
  }
}

async function main(args = process.argv.slice(2), cwd = process.cwd()) {
  const options = parseArgs(args)
  if (options.command === 'version') { console.log(`Atlas v${pkg.version}`); return 0 }
  if (options.command === 'help') { console.log(HELP); return 0 }
  const dir = path.join(cwd, '.atlas')
  if (options.command === 'init') { init(cwd); return 0 }
  if (!fs.existsSync(dir)) throw new Error(".atlas/ not found. Run 'atlas init' first.")
  if (options.command === 'status') {
    const state = status(cwd)
    if (options.json) console.log(JSON.stringify(state, null, 2))
    else console.log(printStatus(state))
    return 0
  }
  const release = acquireLock(dir)
  const controller = new AbortController()
  const interrupt = () => controller.abort()
  process.on('SIGINT', interrupt)
  process.on('SIGTERM', interrupt)
  try {
    const config = loadConfig(cwd, options)
    if (options.command === 'plan') return await plan(cwd, options.args.join(' '), config.provider, controller.signal)
    return await loop.run(cwd, config, options.iterations ?? config.iterations, controller.signal)
  } finally {
    process.removeListener('SIGINT', interrupt)
    process.removeListener('SIGTERM', interrupt)
    release()
  }
}

if (require.main === module) {
  main().then(code => { process.exitCode = code }).catch(error => {
    console.error(`Error: ${error.message}`)
    process.exitCode = error.exitCode || 1
  })
}
module.exports = { main, parseArgs, loadConfig, plan, status }
