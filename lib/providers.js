'use strict'
const { execute } = require('./process')
const { spawnSync } = require('node:child_process')
function available(bin) { return spawnSync('/bin/sh', ['-c', 'command -v "$1"', 'atlas', bin], { stdio: 'ignore' }).status === 0 }
const bins = { claudecode: 'claude', codex: 'codex', opencode: 'opencode' }
function invocation(provider, mode, promptFile) {
  const instruction = `Read ${JSON.stringify(promptFile)} and follow its instructions.`
  if (mode === 'plan') {
    if (provider === 'claudecode') return { command: 'claude', args: [instruction], interactive: true }
    if (provider === 'codex') return { command: 'codex', args: [instruction], interactive: true }
    return { command: 'opencode', args: ['--prompt', instruction], interactive: true }
  }
  if (provider === 'codex') return { command: 'codex', args: ['exec', '--dangerously-bypass-approvals-and-sandbox', '--skip-git-repo-check', '-'] }
  if (provider === 'opencode') return { command: 'opencode', args: ['run', '--agent', 'build', instruction, '--file', promptFile], env: { ...process.env, OPENCODE_PERMISSION: process.env.OPENCODE_PERMISSION || '{"*":"allow"}' } }
  return { command: 'claude', args: ['--dangerously-skip-permissions', '-p'] }
}
function run(provider, mode, promptFile, options) {
  const { command, args, ...settings } = invocation(provider, mode, promptFile)
  return execute(command, args, { ...options, ...settings })
}
module.exports = { bins, invocation, run, available }
