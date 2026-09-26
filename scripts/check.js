'use strict'
const fs = require('node:fs')
const os = require('node:os')
const path = require('node:path')
const { execFileSync } = require('node:child_process')
for (const dir of ['lib', 'scripts']) for (const file of fs.readdirSync(dir)) {
  if (file.endsWith('.js')) execFileSync(process.execPath, ['--check', path.join(dir, file)], { stdio: 'inherit' })
}
if (fs.readFileSync('AGENTS.md', 'utf8') !== fs.readFileSync('CLAUDE.md', 'utf8')) throw new Error('AGENTS.md and CLAUDE.md differ')
const pkg = require('../package.json')
const lock = require('../package-lock.json')
if (pkg.version !== lock.version || pkg.version !== lock.packages[''].version) throw new Error('Package versions differ')

// discardChanges must preserve an untracked .atlas/ (backlog, specs, config)
// while still removing other untracked debris.
;(function checkDiscardPreservesAtlas() {
  const git = require('../lib/git')
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'atlas-check-'))
  try {
    execFileSync('git', ['init', '-q'], { cwd: dir })
    fs.writeFileSync(path.join(dir, 'README.md'), 'init\n')
    execFileSync('git', ['add', '-A'], { cwd: dir })
    execFileSync('git', ['commit', '-q', '-m', 'init'], { cwd: dir })
    fs.mkdirSync(path.join(dir, '.atlas'))
    fs.writeFileSync(path.join(dir, '.atlas', 'backlog.md'), 'backlog\n')
    fs.writeFileSync(path.join(dir, 'stray.txt'), 'stray\n')
    git.discardChanges(dir)
    if (!fs.existsSync(path.join(dir, '.atlas', 'backlog.md'))) throw new Error('discardChanges deleted .atlas/backlog.md')
    if (fs.existsSync(path.join(dir, 'stray.txt'))) throw new Error('discardChanges left stray.txt behind')
  } finally {
    fs.rmSync(dir, { recursive: true, force: true })
  }
})()

console.log('Syntax, instructions, package versions, and .atlas/ preservation verified.')
