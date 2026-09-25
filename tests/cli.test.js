'use strict'
const test = require('node:test')
const assert = require('node:assert/strict')
const fs = require('node:fs')
const { fixture } = require('./helpers')

test('help, version and unknown command', t => {
  const f = fixture(t)
  assert.match(f.call(['help']).stdout, /Usage: atlas/)
  assert.match(f.call(['--version']).stdout, /^Atlas v\d+\.\d+\.\d+/)
  assert.notEqual(f.call(['bogus']).status, 0)
})

test('init is idempotent and does not overwrite an existing backlog', t => {
  const f = fixture(t)
  const before = f.read('.atlas/backlog.md')
  assert.equal(f.call(['init']).status, 0)
  assert.equal(f.read('.atlas/backlog.md'), before)
})

test('status reports task counts and the current branch as plain text and JSON', t => {
  const f = fixture(t)
  const text = f.call(['status'])
  assert.equal(text.status, 0)
  assert.match(text.stdout, /TODO=1/)
  const json = JSON.parse(f.call(['status', '--json']).stdout)
  assert.deepEqual(json.tasks, { TODO: 1, IN_PROGRESS: 0, DONE: 0, DELAYED: 0 })
})

test('an unknown config key is rejected before any provider runs', t => {
  const f = fixture(t)
  f.write('.atlas/config.json', { gates: ['true'], nope: 1 })
  assert.match(f.call(['1']).stderr, /Unknown config key/)
  assert.equal(fs.existsSync(`${f.cwd}/.atlas/provider-calls`), false)
})

test('init --cli saves the provider into config.json, preserving other keys', t => {
  const f = fixture(t)
  const before = f.json('.atlas/config.json')
  assert.equal(f.call(['init', '--cli', 'codex']).status, 0)
  const after = f.json('.atlas/config.json')
  assert.equal(after.provider, 'codex')
  assert.equal(after.gates.length, before.gates.length)
  assert.equal(after.timeout, before.timeout)
  assert.equal(after.retries, before.retries)
})

test('--cli on a run persists the provider for later runs without the flag', t => {
  const f = fixture(t)
  f.write('.atlas/backlog.md', f.read('.atlas/backlog.md').replace('## IN_PROGRESS', '### T-2: Second task\n- **Acceptance:** implementation.txt exists\n\n## IN_PROGRESS'))
  assert.equal(f.call(['--cli', 'opencode', '1']).status, 2)
  assert.equal(f.json('.atlas/config.json').provider, 'opencode')
  assert.equal(f.call(['1']).status, 0)
  const calls = f.read('.atlas/provider-calls').trim().split('\n').map(JSON.parse)
  assert.deepEqual(calls[1].slice(0, 2), ['run', '--auto'])
})
