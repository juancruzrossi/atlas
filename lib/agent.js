'use strict'
const fs = require('node:fs')
const { spawn, spawnSync } = require('node:child_process')

// Every provider gets one short instruction argument that tells it which file to read.
const instruction = promptFile => `Read ${JSON.stringify(promptFile)} and follow its instructions exactly.`

const PROVIDERS = {
  claudecode: { bin: 'claude', task: i => ['-p', '--dangerously-skip-permissions', i], plan: i => [i] },
  codex: { bin: 'codex', task: i => ['exec', '--dangerously-bypass-approvals-and-sandbox', '--skip-git-repo-check', i], plan: i => [i] },
  opencode: { bin: 'opencode', task: i => ['run', '--auto', i], plan: i => ['--prompt', i] },
}

function hasBinary(provider) {
  return spawnSync('/bin/sh', ['-c', 'command -v "$1"', 'atlas', PROVIDERS[provider].bin], { stdio: 'ignore' }).status === 0
}

// Run a command detached in its own process group, streaming output to the
// terminal and to a log file, with timeout and signal-based cancellation.
function supervise(command, args, { cwd, log, timeout, signal, interactive = false }) {
  return new Promise((resolve, reject) => {
    if (signal?.aborted) return reject(Object.assign(new Error('Interrupted'), { exitCode: 130 }))
    const fd = log ? fs.openSync(log, 'a', 0o600) : null
    const child = spawn(command, args, { cwd, detached: !interactive, stdio: interactive ? 'inherit' : ['ignore', 'pipe', 'pipe'] })
    let timer, killTimer, stoppedFor = null, settled = false
    const kill = signalName => {
      try { process.kill(interactive ? child.pid : -child.pid, signalName) } catch (error) { if (error.code !== 'ESRCH') throw error }
    }
    const stop = reason => {
      if (stoppedFor) return
      stoppedFor = reason
      if (child.pid) kill('SIGTERM')
      killTimer = setTimeout(() => { if (child.pid) kill('SIGKILL') }, 500)
    }
    const onAbort = () => stop('interrupted')
    signal?.addEventListener('abort', onAbort, { once: true })
    let output = ''
    if (!interactive) {
      for (const [stream, mirror] of [[child.stdout, process.stdout], [child.stderr, process.stderr]]) {
        stream.on('data', data => {
          output += data
          if (fd !== null) fs.writeSync(fd, data)
          mirror.write(data)
        })
      }
      if (timeout) timer = setTimeout(() => stop('timeout'), timeout * 1000)
    }
    function finish(error, code) {
      if (settled) return
      settled = true
      clearTimeout(timer)
      clearTimeout(killTimer)
      signal?.removeEventListener('abort', onAbort)
      if (fd !== null) fs.closeSync(fd)
      if (error) reject(error)
      else resolve({ code: stoppedFor === 'timeout' ? 124 : stoppedFor === 'interrupted' ? 130 : code ?? 1, output })
    }
    child.once('error', error => finish(new Error(`${command}: ${error.message}`)))
    // Reap descendants even when the child exits before its own children do.
    child.once('exit', () => { if (!interactive && child.pid) kill('SIGKILL') })
    child.once('close', code => finish(null, code))
  })
}

// Run one provider on the assigned task's prompt file.
function runTask(provider, promptFile, { cwd, log, timeout, signal }) {
  const { bin, task } = PROVIDERS[provider]
  return supervise(bin, task(instruction(promptFile)), { cwd, log, timeout, signal })
}

// Run the provider interactively for `atlas plan`, inheriting the terminal.
function runInteractive(provider, promptFile, cwd) {
  const { bin, plan } = PROVIDERS[provider]
  return supervise(bin, plan(instruction(promptFile)), { cwd, interactive: true })
}

// Run a quality gate shell command with the same supervision as a provider.
function runShell(command, { cwd, log, timeout, signal }) {
  return supervise('/bin/sh', ['-c', command], { cwd, log, timeout, signal })
}

module.exports = { PROVIDERS, hasBinary, runTask, runInteractive, runShell }
