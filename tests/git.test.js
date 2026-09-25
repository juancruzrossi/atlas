'use strict'
const test = require('node:test')
const assert = require('node:assert/strict')
const fs = require('node:fs')
const { fixture } = require('./helpers')

test('publishing pushes each commit and opens one PR, then edits it on the next push', t => {
  const f = fixture(t, { remote: true })
  const main = f.git('rev-parse', 'main')
  f.write('.atlas/backlog.md', f.read('.atlas/backlog.md').replace('## IN_PROGRESS', '### T-2: Second task\n\n## IN_PROGRESS'))
  const r = f.call(['2'])
  assert.equal(r.status, 0, r.stderr + r.stdout)
  const branch = f.git('branch', '--show-current')
  assert.match(branch, /^atlas\//)
  assert.equal(f.git('rev-parse', 'main'), main)
  assert.equal(f.git('rev-parse', `origin/${branch}`), f.git('rev-parse', 'HEAD'))
  assert.equal(f.git('status', '--porcelain'), '')
  const calls = f.read('.atlas/github-calls').trim().split('\n').map(JSON.parse)
  assert.equal(calls.filter(c => c[1] === 'create').length, 1)
  assert.equal(calls.filter(c => c[1] === 'edit').length, 1)
  assert.equal(calls.some(c => c.includes('merge')), false)
})

test('without an origin remote, Atlas never calls git push or gh', t => {
  const f = fixture(t)
  assert.equal(f.call(['1']).status, 0)
  assert.equal(fs.existsSync(`${f.cwd}/.atlas/github-calls`), false)
})

test('on a base branch that does not exist locally, a run with no remote still succeeds', t => {
  const f = fixture(t, { git: false })
  f.git('init', '-b', 'master')
  f.git('add', '.')
  f.git('commit', '-m', 'chore: initial')
  const r = f.call(['1'])
  assert.equal(r.status, 0, r.stderr + r.stdout)
  assert.equal(JSON.parse(f.call(['status', '--json']).stdout).tasks.DONE, 1)
})

test('a dirty tree outside .atlas is rejected before any task or branch change', t => {
  const f = fixture(t)
  f.write('user-file.txt', 'user work')
  const before = f.read('.atlas/backlog.md')
  assert.match(f.call(['1']).stderr, /Commit or stash/)
  assert.equal(f.git('branch', '--show-current'), 'main')
  assert.equal(f.read('.atlas/backlog.md'), before)
  assert.equal(f.read('user-file.txt'), 'user work')
})

test('pending changes inside .atlas alone are committed onto the new branch', t => {
  const f = fixture(t)
  f.write('.atlas/backlog.md', f.read('.atlas/backlog.md').replace('First task', 'First task (edited)'))
  assert.equal(f.call(['1']).status, 0)
  const branch = f.git('branch', '--show-current')
  assert.match(branch, /^atlas\//)
  const subjects = f.git('log', '--format=%s', '--reverse').split('\n')
  assert.equal(subjects[1], 'chore: update Atlas backlog')
})
