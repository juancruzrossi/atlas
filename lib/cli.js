#!/usr/bin/env node
'use strict'
const fs = require('node:fs')
const path = require('node:path')
const { config, integer, providers } = require('./config')
const { acquireLock, read } = require('./storage')
const commands = require('./commands')
const { run } = require('./runner')
const pkg = require('../package.json')
const HELP = `Atlas v${pkg.version} - Autonomous Task Loop Agent System

Usage: atlas [options] [command]

  atlas init                  Initialize project state and configuration
  atlas plan <description>    Interview, write a spec, and add tasks
  atlas [run] [iterations]    Implement and verify one task at a time
  atlas resume [iterations]   Continue local or Git session without losing work
  atlas status [--json]       Show task counts and session state
  atlas logs [--tail N]       Show recent runs (--failed, --search, --json)
  atlas review [--dry-run]    Inspect state and report recovery instructions
  atlas doctor [--json]       Check configuration, provider, gates, and session
  atlas clean [--all]         Remove finished runtime logs; preserve task state
  atlas update                Show npm update instructions
  atlas help                  Show this help

Options:
  --cli <provider>            claudecode (default), opencode, or codex
  --version, -v               Show installed version
  --help, -h                  Show help

Configuration: .atlas/config.json; flags override ATLAS_* environment overrides.
Git sessions create one integration PR and leave it open for review.
Exit codes: 0 complete, 1 failure, 2 iteration limit, 124 timeout, 130 interrupted.
`
function parse(args) {
  const options = { args: [] }
  let positional = false
  for (let i = 0; i < args.length; i++) {
    const arg = args[i]
    if (positional) { options.args.push(arg); continue }
    if (arg === '--') { positional = true; continue }
    if (['--cli', '--tail', '--search'].includes(arg)) {
      if (args[i + 1] === undefined || args[i + 1].startsWith('--')) throw new Error(`${arg} requires an argument`)
      options[arg.slice(2)] = args[++i]
    } else if (['--dry-run', '--all', '--failed', '--json'].includes(arg)) options[arg.slice(2)] = true
    else if (['--help', '-h'].includes(arg)) options.help = true
    else if (['--version', '-v'].includes(arg)) options.version = true
    else if (arg.startsWith('-')) throw new Error(`Unknown option: ${arg}`)
    else options.args.push(arg)
  }
  if (options.cli && !providers.includes(options.cli)) throw new Error("--cli requires 'claudecode', 'opencode', or 'codex'")
  if (options.version) return { ...options, command: 'version' }
  const first = options.args[0]
  const command = options.help ? 'help' : !first || /^\d+$/.test(first) ? 'run' : options.args.shift()
  if (!['init', 'run', 'resume', 'plan', 'review', 'clean', 'logs', 'status', 'doctor', 'update', 'help'].includes(command)) throw new Error(`Unknown command '${command}'. Run 'atlas help' for usage.`)
  for (const [flag, allowed] of Object.entries({ 'dry-run': ['review'], all: ['clean'], tail: ['logs'], failed: ['logs'], search: ['logs'], json: ['logs', 'status', 'doctor', 'review'] })) {
    if (options[flag] !== undefined && command !== 'help' && !allowed.includes(command)) throw new Error(`--${flag} is only valid with ${allowed.join(', ')}`)
  }
  if (options.tail !== undefined) options.tail = integer(options.tail, '--tail', 0)
  if (['run', 'resume'].includes(command)) {
    if (options.args.length > 1) throw new Error(`Usage: atlas ${command} [iterations]`)
    if (options.args[0] !== undefined) options.iterations = integer(options.args[0], 'iterations')
  } else if (command === 'plan') {
    if (!options.args.length) throw new Error('Usage: atlas plan <description>')
  } else if (command !== 'help' && options.args.length) throw new Error(`Unexpected arguments for atlas ${command}`)
  return { ...options, command }
}
async function main(args = process.argv.slice(2), cwd = process.cwd()) {
  const options = parse(args)
  if (options.command === 'version') { console.log(`Atlas v${pkg.version}`); return 0 }
  if (options.command === 'help') { console.log(HELP); return 0 }
  if (options.command === 'update') {
    const registry = process.env.npm_config_registry || process.env.NPM_CONFIG_REGISTRY || read(path.resolve(__dirname, '../.npm-registry')).trim()
    console.log(`npm update -g @jxtools/atlas${registry ? ` --registry '${registry.replaceAll("'", "'\\''")}'` : ''}`)
    return 0
  }
  const dir = path.join(cwd, '.atlas')
  if (!['init', 'doctor'].includes(options.command) && !fs.existsSync(dir)) throw new Error(".atlas/ not found. Run 'atlas init' first.")
  if (options.command === 'status') {
    const state = commands.status(cwd)
    if (options.json) console.log(JSON.stringify(state, null, 2))
    else console.log(`Atlas Status - ${state.project}\nTasks: ${Object.entries(state.tasks).map(([key, value]) => `${key}=${value}`).join('  ')}\nSession: ${state.session?.status || 'none'}${state.session?.pr_url ? `\nPR: ${state.session.pr_url}` : ''}`)
    return 0
  }
  if (['doctor', 'review'].includes(options.command)) {
    const checks = commands.doctor(cwd, options)
    console.log(options.json ? JSON.stringify(checks, null, 2) : checks.map(c => `[${c.ok ? 'OK' : 'FAIL'}] ${c.name}: ${c.detail}`).join('\n'))
    return checks.every(c => c.ok) ? 0 : 1
  }
  if (options.command === 'logs') {
    const result = commands.logs(cwd, options)
    console.log(options.json ? JSON.stringify(result, null, 2) : result.total ? result.entries.map(e => `${e.task}  ${e.status.toUpperCase()}  ${e.file}`).join('\n') + `\n${result.entries.length} of ${result.total} logs shown` : 'No iteration logs found.')
    return 0
  }
  fs.mkdirSync(dir, { recursive: true })
  const release = acquireLock(dir)
  const controller = new AbortController()
  const interrupt = () => controller.abort()
  process.on('SIGINT', interrupt)
  process.on('SIGTERM', interrupt)
  try {
    if (options.command === 'init') { commands.init(cwd); return 0 }
    if (options.command === 'clean') { commands.clean(cwd, options.all); return 0 }
    const conf = config(cwd, options)
    if (options.command === 'plan') return await commands.plan(cwd, options, conf, controller.signal)
    return await run(cwd, conf, options.command === 'resume', controller.signal)
  } finally {
    process.removeListener('SIGINT', interrupt)
    process.removeListener('SIGTERM', interrupt)
    release()
  }
}
if (require.main === module) main().then(code => { process.exitCode = code }).catch(error => { console.error(`Error: ${error.message}`); process.exitCode = error.exitCode || 1 })
module.exports = { main, parse }
