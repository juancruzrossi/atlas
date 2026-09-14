'use strict'
const fs = require('node:fs')
const path = require('node:path')
const os = require('node:os')
const { randomUUID } = require('node:crypto')

function read(file, fallback = '') {
  try { return fs.readFileSync(file, 'utf8') } catch (error) {
    if (error.code === 'ENOENT') return fallback
    throw error
  }
}
function json(file, fallback = null) {
  const text = read(file, null)
  if (text === null) return fallback
  try { return JSON.parse(text) } catch { throw new Error(`Invalid JSON: ${file}`) }
}
function atomicWrite(file, content) {
  const temp = `${file}.${randomUUID()}.tmp`
  try {
    fs.writeFileSync(temp, content, { mode: 0o600, flag: 'wx' })
    fs.renameSync(temp, file)
  } finally { fs.rmSync(temp, { force: true }) }
}
function writeJson(file, value) { atomicWrite(file, JSON.stringify(value, null, 2) + '\n') }
function acquireLock(dir) {
  const file = path.join(dir, 'runtime.lock')
  const owner = { pid: process.pid, host: os.hostname(), token: randomUUID() }
  try { fs.writeFileSync(file, JSON.stringify(owner), { flag: 'wx', mode: 0o600 }) } catch (error) {
    if (error.code !== 'EEXIST') throw error
    const existing = json(file)
    throw new Error(`Atlas is locked by PID ${existing?.pid || 'unknown'} on ${existing?.host || 'unknown'}. Use 'atlas doctor' to inspect it; remove ${file} only after its owner has stopped.`)
  }
  return () => {
    if (json(file)?.token === owner.token) fs.unlinkSync(file)
  }
}
function event(dir, value) {
  fs.appendFileSync(path.join(dir, 'activity.log'), JSON.stringify({ time: new Date().toISOString(), ...value }) + '\n')
}
module.exports = { read, json, atomicWrite, writeJson, acquireLock, event }
