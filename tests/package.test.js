'use strict'
const test = require('node:test')
const assert = require('node:assert/strict')
const { spawnSync } = require('node:child_process')
const { root } = require('./helpers')

test('npm pack ships only the runtime files Atlas needs', () => {
  const packed = spawnSync('npm', ['pack', '--json', '--dry-run'], { cwd: root, encoding: 'utf8', timeout: 30000 })
  assert.equal(packed.status, 0, packed.stderr)
  const info = JSON.parse(packed.stdout)[0]
  const paths = info.files.map(file => file.path)
  for (const expected of ['lib/cli.js', 'lib/backlog.js', 'lib/agent.js', 'lib/git.js', 'lib/loop.js', 'prompt.md', 'plan_prompt.md', 'notify-telegram.sh', 'templates/backlog.md', 'package.json']) {
    assert.ok(paths.includes(expected), `expected packed files to include ${expected}`)
  }
  for (const unexpected of ['atlas.sh', 'review_prompt.md', 'skills/', 'references/', 'scripts/postinstall.js']) {
    assert.equal(paths.some(p => p.startsWith(unexpected)), false, `did not expect packed files to include ${unexpected}`)
  }
  assert.equal(paths.some(p => p.startsWith('tests/')), false)
})
