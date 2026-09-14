'use strict'
const path = require('node:path')
const { json } = require('./storage')
const providers = ['claudecode', 'opencode', 'codex']
function integer(value, name, min = 1, max = 2147483) {
  if (!/^\d+$/.test(String(value)) || !Number.isSafeInteger(Number(value)) || Number(value) < min || Number(value) > max) {
    throw new Error(`${name} must be an integer between ${min} and ${max}`)
  }
  return Number(value)
}
function config(cwd, options = {}, env = process.env) {
  const file = path.join(cwd, '.atlas/config.json')
  const saved = json(file, {})
  if (!saved || typeof saved !== 'object' || Array.isArray(saved)) throw new Error(`Invalid config: ${file}`)
  for (const key of Object.keys(saved)) {
    if (!['provider', 'iterations', 'timeout', 'gateTimeout', 'gates', 'defaultBranch'].includes(key)) throw new Error(`Unknown config key: ${key}`)
  }
  const provider = options.cli || env.ATLAS_CLI || saved.provider || 'claudecode'
  if (!providers.includes(provider)) throw new Error(`--cli requires 'claudecode', 'opencode', or 'codex', got '${provider}'`)
  const gates = saved.gates ?? []
  if (!Array.isArray(gates) || gates.some(g => typeof g !== 'string' || !g.trim())) throw new Error('config.gates must be an array of nonempty shell commands')
  const defaultBranch = env.ATLAS_DEFAULT_BRANCH || saved.defaultBranch || ''
  if (typeof defaultBranch !== 'string' || defaultBranch.startsWith('-')) throw new Error('Invalid defaultBranch')
  return {
    provider, gates, defaultBranch,
    iterations: integer(options.iterations ?? env.ATLAS_MAX_ITERATIONS ?? saved.iterations ?? 25, 'iterations'),
    timeout: integer(env.ATLAS_TIMEOUT ?? saved.timeout ?? 1200, 'timeout'),
    gateTimeout: integer(saved.gateTimeout ?? env.ATLAS_TIMEOUT ?? saved.timeout ?? 1200, 'gateTimeout'),
  }
}
module.exports = { config, integer, providers }
