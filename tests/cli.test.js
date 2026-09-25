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
