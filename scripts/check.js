'use strict'
const fs = require('node:fs')
const path = require('node:path')
const { execFileSync } = require('node:child_process')
for (const dir of ['lib', 'scripts']) for (const file of fs.readdirSync(dir)) {
  if (file.endsWith('.js')) execFileSync(process.execPath, ['--check', path.join(dir, file)], { stdio: 'inherit' })
}
if (fs.readFileSync('AGENTS.md', 'utf8') !== fs.readFileSync('CLAUDE.md', 'utf8')) throw new Error('AGENTS.md and CLAUDE.md differ')
const pkg = require('../package.json')
const lock = require('../package-lock.json')
if (pkg.version !== lock.version || pkg.version !== lock.packages[''].version) throw new Error('Package versions differ')
console.log('Syntax, instructions, and package versions verified.')
