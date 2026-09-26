'use strict'
const fs = require('node:fs')
const { randomUUID } = require('node:crypto')

const STATES = ['TODO', 'IN_PROGRESS', 'DONE', 'DELAYED']
// A task can only move forward along these edges.
const ALLOWED = { TODO: ['IN_PROGRESS', 'DELAYED'], IN_PROGRESS: ['DONE', 'DELAYED'] }

// Read a file, treating a missing backlog as a clear setup error.
function load(file) {
  if (!fs.existsSync(file)) throw new Error(`Backlog not found: ${file}. Run 'atlas init' first.`)
  return parse(fs.readFileSync(file, 'utf8'))
}

// Parse backlog Markdown into sections and tasks, ignoring code fences and comments.
function parse(text) {
  const lines = text.split('\n')
  const sections = []
  const tasks = []
  let section = null
  let task = null
  let fence = null
  let inComment = false
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i]
    if (inComment) { if (line.includes('-->')) inComment = false; continue }
    if (line.trimStart().startsWith('<!--')) { inComment = !line.includes('-->'); continue }
    const fenceMarker = line.match(/^\s{0,3}(`{3,}|~{3,})/)
    if (fenceMarker) {
      if (!fence) fence = fenceMarker[1]
      else if (fenceMarker[1][0] === fence[0] && fenceMarker[1].length >= fence.length) fence = null
      continue
    }
    if (fence) continue
    if (/^##\s/.test(line)) {
      if (task) task.end = i
      if (section) section.end = i
      task = null
      const name = line.replace(/^##\s+/, '').trim()
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
  const seen = new Set()
  for (const t of tasks) {
    if (seen.has(t.id)) throw new Error(`Duplicate task ID: ${t.id}`)
    seen.add(t.id)
    t.body = lines.slice(t.start, t.end).join('\n').trimEnd()
    t.spec = t.body.match(/^- \*\*Spec:\*\*\s*(.+)$/m)?.[1].trim()
  }
  if (tasks.filter(t => t.state === 'IN_PROGRESS').length > 1) throw new Error('Only one task can be IN_PROGRESS')
  return { lines, sections, tasks }
}

function counts(backlog) {
  return Object.fromEntries(STATES.map(state => [state, backlog.tasks.filter(t => t.state === state).length]))
}

// IN_PROGRESS takes priority so a resumed run finishes the active task first.
function next(backlog) {
  return backlog.tasks.find(t => t.state === 'IN_PROGRESS') || backlog.tasks.find(t => t.state === 'TODO')
}

// Move a task to a new section, replacing its Started/Completed/Reason fields.
function move(file, id, target, fields = {}) {
  const backlog = load(file)
  const task = backlog.tasks.find(t => t.id === id)
  if (!task) throw new Error(`Task not found: ${id}`)
  if (!ALLOWED[task.state]?.includes(target)) throw new Error(`Invalid transition: ${task.state} -> ${target}`)
  if (target === 'IN_PROGRESS' && backlog.tasks.some(t => t.state === target)) throw new Error('Another task is already IN_PROGRESS')
  const block = task.body.split('\n').filter(line => !/^- \*\*(Started|Completed|Reason):\*\*/.test(line))
  for (const [key, value] of Object.entries(fields)) block.push(`- **${key}:** ${value}`)
  const withoutTask = [...backlog.lines.slice(0, task.start), ...backlog.lines.slice(task.end)].join('\n')
  const updated = parse(withoutTask)
  const insertAt = updated.sections.find(s => s.name === target).end
  updated.lines.splice(insertAt, 0, '', ...block, '')
  const text = updated.lines.join('\n').replace(/\n{3,}/g, '\n\n')
  parse(text) // re-validate before writing
  atomicWrite(file, text)
}

function atomicWrite(file, content) {
  const temp = `${file}.${randomUUID()}.tmp`
  try {
    fs.writeFileSync(temp, content, { mode: 0o600 })
    fs.renameSync(temp, file)
  } finally {
    fs.rmSync(temp, { force: true })
  }
}

module.exports = { parse, load, counts, next, move }
