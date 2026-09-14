'use strict'
const { read, atomicWrite } = require('./storage')
const STATES = ['TODO', 'IN_PROGRESS', 'DONE', 'DELAYED']

function parse(text) {
  const lines = text.split('\n')
  const sections = []
  const tasks = []
  let section = null, task = null, fence = null, comment = false
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i]
    if (comment) { if (line.includes('-->')) comment = false; continue }
    if (line.trimStart().startsWith('<!--')) { comment = !line.includes('-->'); continue }
    const code = line.match(/^\s{0,3}(`{3,}|~{3,})/)
    if (code) {
      if (!fence) fence = code[1]
      else if (code[1][0] === fence[0] && code[1].length >= fence.length) fence = null
      continue
    }
    if (fence) continue
    if (/^##\s/.test(line)) {
      if (task) task.end = i
      if (section) section.end = i
      task = null
      const name = line.replace(/^##\s+/, '').trim().replace(/^IN PROGRESS$/, 'IN_PROGRESS')
      section = { name, start: i, end: lines.length }
      sections.push(section)
    } else if (/^###\s/.test(line) && section && STATES.includes(section.name)) {
      if (task) task.end = i
      const match = line.match(/^###\s+([A-Za-z0-9][A-Za-z0-9_-]*):\s+(.+?)\s*$/)
      if (!match) throw new Error(`Invalid task heading at line ${i + 1}; expected '### TASK-001: Title'`)
      task = { id: match[1], title: match[2], state: section.name, start: i, end: lines.length }
      tasks.push(task)
    }
  }
  for (const name of STATES) {
    if (sections.filter(s => s.name === name).length !== 1) throw new Error(`Backlog must contain exactly one '## ${name}' section`)
  }
  const ids = new Set()
  for (const t of tasks) {
    if (ids.has(t.id)) throw new Error(`Duplicate task ID: ${t.id}`)
    ids.add(t.id)
    t.body = lines.slice(t.start, t.end).join('\n').trimEnd()
    t.spec = t.body.match(/^- \*\*Spec:\*\*\s*(.+)$/m)?.[1].trim()
  }
  if (tasks.filter(t => t.state === 'IN_PROGRESS').length > 1) throw new Error('Only one task can be IN_PROGRESS')
  return { text, lines, sections, tasks }
}
function load(file) {
  const text = read(file, null)
  if (text === null) throw new Error(`Backlog not found: ${file}. Run 'atlas init' first.`)
  return parse(text)
}
function counts(backlog) {
  return Object.fromEntries(STATES.map(state => [state, backlog.tasks.filter(t => t.state === state).length]))
}
function next(backlog) {
  return backlog.tasks.find(t => t.state === 'IN_PROGRESS') || backlog.tasks.find(t => t.state === 'TODO')
}
function transition(file, id, target, metadata = {}) {
  const backlog = load(file)
  const task = backlog.tasks.find(t => t.id === id)
  if (!task) throw new Error(`Task not found: ${id}`)
  const allowed = { TODO: ['IN_PROGRESS'], IN_PROGRESS: ['DONE', 'TODO', 'DELAYED'] }
  if (!allowed[task.state]?.includes(target)) throw new Error(`Invalid transition: ${task.state} -> ${target}`)
  if (target === 'IN_PROGRESS' && backlog.tasks.some(t => t.state === target)) throw new Error('Another task is already IN_PROGRESS')
  const block = task.body.split('\n').filter(line => !/^- \*\*(Started|Completed|Reason):\*\*/.test(line))
  for (const [key, value] of Object.entries(metadata)) block.push(`- **${key}:** ${value}`)
  const remaining = [...backlog.lines.slice(0, task.start), ...backlog.lines.slice(task.end)].join('\n')
  const updated = parse(remaining)
  const insertion = updated.sections.find(s => s.name === target).end
  updated.lines.splice(insertion, 0, '', ...block, '')
  const result = updated.lines.join('\n')
  parse(result)
  atomicWrite(file, result)
}
module.exports = { parse, load, counts, next, transition }
