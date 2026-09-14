'use strict'
const fs = require('node:fs')
const { spawn } = require('node:child_process')

function execute(command, args = [], options = {}) {
  const { cwd, input, log, timeout = 1200, signal, interactive = false, env = process.env, quiet = false } = options
  return new Promise((resolve, reject) => {
    if (signal?.aborted) return reject(Object.assign(new Error('Interrupted'), { exitCode: 130 }))
    const fd = log ? fs.openSync(log, 'a', 0o600) : null
    const child = spawn(command, args, { cwd, env, detached: !interactive, stdio: interactive ? 'inherit' : ['pipe', 'pipe', 'pipe'] })
    let timer, killTimer, stopped = null, settled = false
    function kill(sig) {
      try { process.kill(interactive ? child.pid : -child.pid, sig) } catch (error) { if (error.code !== 'ESRCH') throw error }
    }
    function stop(reason) {
      if (stopped) return
      stopped = reason
      if (child.pid) kill('SIGTERM')
      killTimer = setTimeout(() => { if (child.pid) kill('SIGKILL') }, 500)
    }
    const abort = () => stop('interrupted')
    signal?.addEventListener('abort', abort, { once: true })
    if (!interactive) {
      for (const [stream, output] of [[child.stdout, process.stdout], [child.stderr, process.stderr]]) {
        stream.on('data', data => {
          if (fd !== null) fs.writeSync(fd, data)
          if (!quiet) output.write(data)
        })
      }
      child.stdin.on('error', () => {})
      child.stdin.end(input || '')
      timer = setTimeout(() => stop('timeout'), timeout * 1000)
    }
    function finish(error, code) {
      if (settled) return
      settled = true
      clearTimeout(timer)
      clearTimeout(killTimer)
      signal?.removeEventListener('abort', abort)
      if (fd !== null) fs.closeSync(fd)
      if (error) reject(error)
      else resolve({ code: stopped === 'timeout' ? 124 : stopped === 'interrupted' ? 130 : code ?? 1, reason: stopped })
    }
    child.once('error', error => finish(new Error(`${command}: ${error.message}`)))
    child.once('exit', () => {
      // Reap descendants even when the provider exits before its children.
      if (!interactive && child.pid) kill('SIGKILL')
    })
    child.once('close', code => finish(null, code))
  })
}
module.exports = { execute }
