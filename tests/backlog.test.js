'use strict'
const test = require('node:test')
const assert = require('node:assert/strict')
const { parse, next, counts, transition, load } = require('../lib/backlog')
const { fixture } = require('./helpers')
const doc = '## TODO\n### T-1: First\n\n## IN_PROGRESS\n### T-2: Active\n\n## DONE\n\n## DELAYED\n'
test('select IN_PROGRESS before an earlier TODO section', () => { assert.equal(next(parse(doc)).id, 'T-2') })
test('ignore Markdown examples, comments and unrelated sections', () => {
  const text = doc.replace('### T-1: First', '<!--\n### EX-1: Comment\n-->\n```md\n### EX-2: Example\n## DONE\n```\n### T-1: First') + '\n## Notes\n### EX-3: Not a task\n'
  assert.deepEqual(counts(parse(text)), { TODO: 1, IN_PROGRESS: 1, DONE: 0, DELAYED: 0 })
})
test('legacy IN PROGRESS heading is accepted', () => assert.equal(next(parse(doc.replace('IN_PROGRESS', 'IN PROGRESS'))).id, 'T-2'))
test('reject missing/duplicate sections, duplicate IDs, and multiple active tasks', () => {
  for (const text of [doc.replace('## DONE', '## Other'), doc + '\n## TODO\n', doc.replace('T-2:', 'T-1:'), doc.replace('### T-2: Active', '### T-2: Active\n### T-3: Active')]) assert.throws(() => parse(text))
})
test('atomic transitions preserve specs, details and all other tasks', t => {
  const f = fixture(t)
  f.write('.atlas/backlog.md', doc.replace('### T-2: Active', '### T-2: Active\n- **Spec:** .atlas/specs/a.md\n- **Started:** old\n- **Description:** preserve me'))
  transition(`${f.cwd}/.atlas/backlog.md`, 'T-2', 'DONE', { Completed: 'today' })
  const result = load(`${f.cwd}/.atlas/backlog.md`)
  assert.equal(result.tasks.find(t => t.id === 'T-2').state, 'DONE')
  assert.equal(result.tasks.find(t => t.id === 'T-2').spec, '.atlas/specs/a.md')
  assert.match(result.text, /preserve me/)
  assert.doesNotMatch(result.text, /Started/)
  assert.equal(next(result).id, 'T-1')
})
test('disallow TODO directly to DONE and multiple claims', t => {
  const f = fixture(t); f.write('.atlas/backlog.md', doc)
  assert.throws(() => transition(`${f.cwd}/.atlas/backlog.md`, 'T-1', 'DONE'))
  assert.throws(() => transition(`${f.cwd}/.atlas/backlog.md`, 'T-1', 'IN_PROGRESS'))
})
