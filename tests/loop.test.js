'use strict'
const test = require('node:test')
const assert = require('node:assert/strict')
const fs = require('node:fs')
const path = require('node:path')
const { fixture, waitFor, finished } = require('./helpers')

for (const provider of ['claudecode', 'codex', 'opencode']) test(`${provider}: completes one task through the CLI and its gate`, t => {
  const f = fixture(t)
  const r = f.call(['--cli', provider, '1'])
  assert.equal(r.status, 0, r.stderr + r.stdout)
  const branch = f.git('branch', '--show-current')
  assert.match(branch, /^atlas\//)
  assert.match(f.git('log', '-1', '--format=%s'), /^feat\(T-1\)/)
  assert.match(f.read('.atlas/progress.txt'), /T-1/)
  assert.equal(JSON.parse(f.call(['status', '--json']).stdout).tasks.DONE, 1)
  assert.equal(fs.existsSync(`${f.cwd}/.atlas/runtime.lock`), false)
})

for (const behavior of ['failure', 'promise', 'bad-json', 'blocked', 'wrong-id']) test(`${behavior} exhausts retries and delays the task`, t => {
  const f = fixture(t, { retries: 1 })
  const r = f.call(['1'], { FAKE_BEHAVIOR: behavior })
  assert.equal(r.status, 0, r.stderr + r.stdout)
  assert.equal(JSON.parse(f.call(['status', '--json']).stdout).tasks.DELAYED, 1)
  assert.equal(fs.existsSync(`${f.cwd}/implementation.txt`), false)
})

test('a failing gate is retried and the previous attempt error reaches the next prompt', t => {
  const f = fixture(t)
  f.write('.atlas/config.json', { gates: ['test -f required.txt'], timeout: 5, retries: 2 })
  const before = fs.readdirSync(`${f.cwd}/.atlas`).includes('required.txt')
  assert.equal(before, false)
  // The fake provider always writes implementation.txt but never required.txt,
  // so attempt 1 fails the gate; make attempt 2 also create required.txt via a wrapper.
  fs.writeFileSync(path.join(f.bin, 'claude'), `#!${process.execPath}
const calls = require('node:fs').existsSync('.atlas/attempts') ? Number(require('node:fs').readFileSync('.atlas/attempts', 'utf8')) : 0;
require('node:fs').writeFileSync('.atlas/attempts', String(calls + 1));
if (calls >= 1) require('node:fs').writeFileSync('required.txt', 'ok');
${fs.readFileSync(path.join(__dirname, 'provider-fixture.js'), 'utf8')}
`, { mode: 0o755 })
  const r = f.call(['1'])
  assert.equal(r.status, 0, r.stderr + r.stdout)
  assert.equal(JSON.parse(f.call(['status', '--json']).stdout).tasks.DONE, 1)
  const secondPrompt = fs.readdirSync(`${f.cwd}/.atlas/runs`).find(name => name === 'T-1-2.prompt.md')
  assert.ok(secondPrompt, 'expected a second attempt prompt file to remain')
  assert.match(fs.readFileSync(`${f.cwd}/.atlas/runs/${secondPrompt}`, 'utf8'), /Previous attempt failed/)
})

test('the agent editing backlog.md is reverted before Atlas records the result', t => {
  const f = fixture(t)
  const r = f.call(['1'], { FAKE_BEHAVIOR: 'tamper' })
  assert.equal(r.status, 0, r.stderr + r.stdout)
  assert.doesNotMatch(f.read('.atlas/backlog.md'), /changed by provider/)
})

test('iteration budget stops honestly and a later run continues the queue', t => {
  const f = fixture(t)
  f.write('.atlas/backlog.md', f.read('.atlas/backlog.md').replace('## IN_PROGRESS', '### T-2: Second task\n\n## IN_PROGRESS'))
  assert.equal(f.call(['1']).status, 2)
  assert.equal(JSON.parse(f.call(['status', '--json']).stdout).tasks.DONE, 1)
  assert.equal(f.call(['1']).status, 0)
  assert.equal(JSON.parse(f.call(['status', '--json']).stdout).tasks.DONE, 2)
})

test('an empty queue does not invoke a provider', t => {
  const f = fixture(t)
  f.write('.atlas/backlog.md', '## TODO\n## IN_PROGRESS\n## DONE\n## DELAYED\n')
  assert.equal(f.call(['1']).status, 0)
  assert.equal(fs.existsSync(`${f.cwd}/.atlas/provider-calls`), false)
})

test('invalid arguments and missing gates fail before invoking the provider', t => {
  const f = fixture(t)
  for (const args of [['0'], ['run', '-1'], ['--unknown'], ['run', '1', '2']]) assert.notEqual(f.call(args).status, 0)
  f.write('.atlas/config.json', { gates: [] })
  assert.match(f.call(['1']).stderr, /at least one quality gate/)
  assert.equal(fs.existsSync(`${f.cwd}/.atlas/provider-calls`), false)
})

test('the runtime lock excludes a competing run and is released on SIGINT', async t => {
  const f = fixture(t)
  f.write('.atlas/config.json', { gates: ['test -f implementation.txt'], timeout: 10, retries: 3 })
  const child = f.start(['1'], { FAKE_BEHAVIOR: 'hang' })
  const done = finished(child)
  t.after(() => child.kill('SIGTERM'))
  await waitFor(() => fs.existsSync(`${f.cwd}/.atlas/child-pid`))
  assert.match(f.call(['1']).stderr, /locked/)
  assert.equal(f.call(['status', '--json']).status, 0)
  child.kill('SIGINT')
  const result = await done
  assert.equal(result.code, 130)
  assert.equal(fs.existsSync(`${f.cwd}/.atlas/runtime.lock`), false)
  assert.equal(JSON.parse(f.call(['status', '--json']).stdout).tasks.IN_PROGRESS, 1)
  const pid = Number(f.read('.atlas/child-pid'))
  await waitFor(() => { try { return fs.readFileSync(`/proc/${pid}/stat`, 'utf8').split(' ')[2] === 'Z' } catch { return true } })
})

test('timeout is nonzero, streams logs before exit, and kills the process tree', async t => {
  const f = fixture(t)
  f.write('.atlas/config.json', { gates: ['test -f implementation.txt'], timeout: 1, retries: 1 })
  const child = f.start(['1'], { FAKE_BEHAVIOR: 'hang' })
  const done = finished(child)
  await waitFor(() => fs.existsSync(`${f.cwd}/.atlas/child-pid`))
  const pid = Number(f.read('.atlas/child-pid'))
  const logs = fs.readdirSync(`${f.cwd}/.atlas/runs`).filter(n => n.endsWith('.log'))
  assert.match(f.read(`.atlas/runs/${logs[0]}`), /streamed/)
  const result = await done
  assert.equal(result.code, 0)
  await waitFor(() => { try { return fs.readFileSync(`/proc/${pid}/stat`, 'utf8').split(' ')[2] === 'Z' } catch { return true } })
  assert.equal(JSON.parse(f.call(['status', '--json']).stdout).tasks.DELAYED, 1)
})

test('a spec outside the project is rejected before the provider runs', t => {
  const f = fixture(t)
  f.write('.atlas/backlog.md', f.read('.atlas/backlog.md').replace('- **Acceptance:**', '- **Spec:** ../outside.md\n- **Acceptance:**'))
  assert.match(f.call(['1']).stderr, /inside the project/)
  assert.equal(fs.existsSync(`${f.cwd}/.atlas/provider-calls`), false)
})

test('--cli selects the configured provider and it receives the expected arguments', t => {
  const f = fixture(t)
  assert.equal(f.call(['--cli', 'codex', '1']).status, 0)
  const calls = f.read('.atlas/provider-calls').trim().split('\n').map(JSON.parse)
  assert.deepEqual(calls[0].slice(0, 3), ['exec', '--dangerously-bypass-approvals-and-sandbox', '--skip-git-repo-check'])
})

test('Telegram is notified only when both bot and chat are configured', t => {
  const f = fixture(t)
  assert.equal(f.call(['1']).status, 0)
  assert.equal(fs.existsSync(`${f.cwd}/.atlas/curl-calls`), false)
  const f2 = fixture(t)
  assert.equal(f2.call(['1'], { ATLAS_TELEGRAM_BOT: 'bot', ATLAS_TELEGRAM_CHAT: 'chat' }).status, 0)
  assert.equal(fs.existsSync(`${f2.cwd}/.atlas/curl-calls`), true)
})
