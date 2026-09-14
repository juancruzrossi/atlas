'use strict'
const test = require('node:test')
const assert = require('node:assert/strict')
const fs = require('node:fs')
const path = require('node:path')
const { fixture } = require('./helpers')
const { plan } = require('../lib/commands')
const { config } = require('../lib/config')

for (const provider of ['claudecode', 'codex', 'opencode']) test(`${provider} planning opens interactive mode and validates spec-linked tasks`, async t => {
  const f = fixture(t)
  const bin = { claudecode: 'claude', codex: 'codex', opencode: 'opencode' }[provider]
  fs.writeFileSync(path.join(f.bin, bin), `#!${process.execPath}\nconst fs = require('node:fs');
const args = process.argv.slice(2);
if (args.includes('exec') || args.includes('run') || args.includes('-p')) process.exit(9);
const instruction = args.find(a => a.startsWith('Read '));
const file = JSON.parse(instruction.match(/^Read (".*") and follow/)[1]);
const prompt = fs.readFileSync(file, 'utf8');
const spec = prompt.match(/^Spec output: (.+)$/m)[1];
fs.writeFileSync(spec, '# Feature spec\\nObservable acceptance criteria.\\n');
const backlog = fs.readFileSync('.atlas/backlog.md', 'utf8');
fs.writeFileSync('.atlas/backlog.md', backlog.replace('## IN_PROGRESS', '### PLAN-1: Planned task\\n- **Spec:** ' + spec + '\\n\\n## IN_PROGRESS'));
`, { mode: 0o755 })
  const previousPath = process.env.PATH
  const descriptor = Object.getOwnPropertyDescriptor(process.stdin, 'isTTY')
  process.env.PATH = f.env.PATH
  Object.defineProperty(process.stdin, 'isTTY', { value: true, configurable: true })
  t.after(() => {
    process.env.PATH = previousPath
    if (descriptor) Object.defineProperty(process.stdin, 'isTTY', descriptor)
    else delete process.stdin.isTTY
  })
  const conf = config(f.cwd, { cli: provider }, {})
  assert.equal(await plan(f.cwd, { args: ['A feature with spaces'] }, conf, new AbortController().signal), 0)
  assert.match(f.read('.atlas/backlog.md'), /PLAN-1/)
  assert.match(f.read('.atlas/backlog.md'), /T-1/)
  assert.equal(fs.readdirSync(path.join(f.cwd, '.atlas/runs')).some(f => f.endsWith('.prompt.md')), false)
})
