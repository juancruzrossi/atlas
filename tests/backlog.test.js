'use strict'
const test = require('node:test')
const assert = require('node:assert/strict')
const fs = require('node:fs')
const path = require('node:path')
const os = require('node:os')
const { parse, next, counts, move, load } = require('../lib/backlog')

const doc = '## TODO\n### T-1: First\n\n## IN_PROGRESS\n### T-2: Active\n\n## DONE\n\n## DELAYED\n'

function tempFile(t, content) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'atlas-backlog-'))
  const file = path.join(dir, 'backlog.md')
  fs.writeFileSync(file, content)
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }))
  return file
}

test('select IN_PROGRESS before an earlier TODO section', () => {
  assert.equal(next(parse(doc)).id, 'T-2')
})

test('ignore Markdown examples, comments and unrelated sections', () => {
  const text = doc.replace('### T-1: First', '<!--\n### EX-1: Comment\n-->\n```md\n### EX-2: Example\n## DONE\n```\n### T-1: First') + '\n## Notes\n### EX-3: Not a task\n'
  assert.deepEqual(counts(parse(text)), { TODO: 1, IN_PROGRESS: 1, DONE: 0, DELAYED: 0 })
})

test('reject missing/duplicate sections, duplicate IDs, and multiple active tasks', () => {
  for (const text of [doc.replace('## DONE', '## Other'), doc + '\n## TODO\n', doc.replace('T-2:', 'T-1:'), doc.replace('### T-2: Active', '### T-2: Active\n### T-3: Active')]) {
    assert.throws(() => parse(text))
  }
})

test('atomic move preserves specs, details and all other tasks', t => {
  const file = tempFile(t, doc.replace('### T-2: Active', '### T-2: Active\n- **Spec:** .atlas/specs/a.md\n- **Started:** old\n- **Description:** preserve me'))
  move(file, 'T-2', 'DONE', { Completed: 'today' })
  const result = load(file)
  assert.equal(result.tasks.find(t => t.id === 'T-2').state, 'DONE')
  assert.equal(result.tasks.find(t => t.id === 'T-2').spec, '.atlas/specs/a.md')
  const text = fs.readFileSync(file, 'utf8')
  assert.match(text, /preserve me/)
  assert.doesNotMatch(text, /Started/)
  assert.equal(next(result).id, 'T-1')
})

test('disallow TODO directly to DONE and multiple claims', t => {
  const file = tempFile(t, doc)
  assert.throws(() => move(file, 'T-1', 'DONE'))
  assert.throws(() => move(file, 'T-1', 'IN_PROGRESS'))
})

test('TODO can move straight to DELAYED', t => {
  const file = tempFile(t, doc)
  move(file, 'T-1', 'DELAYED', { Reason: 'gave up' })
  assert.equal(load(file).tasks.find(t => t.id === 'T-1').state, 'DELAYED')
})
