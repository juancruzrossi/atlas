'use strict'
const fs = require('node:fs')
const path = require('node:path')
const backlog = require('./backlog')
const agent = require('./agent')
const git = require('./git')

const atlasHome = path.resolve(__dirname, '..')

// Build the prompt for one attempt: task body, its spec file, the other
// backlog tasks (other PRs, not to be implemented here), the previous
// attempt's error (if any), and the exact result file to write.
function buildPrompt(cwd, task, allTasks, resultFile, previousError) {
  let spec = ''
  if (task.spec) {
    const full = path.resolve(cwd, task.spec)
    if (!fs.realpathSync(path.dirname(full)).startsWith(fs.realpathSync(cwd))) throw new Error(`Task spec must be inside the project: ${task.spec}`)
    spec = `\n\n## Feature specification (${task.spec})\n${fs.readFileSync(full, 'utf8')}`
  }
  const others = allTasks.filter(t => t.id !== task.id)
  const otherTasks = others.length
    ? `\n\n## Other tasks (separate PRs, do not implement)\n${others.map(t => `${t.id}: ${t.title} (${t.state})`).join('\n')}`
    : ''
  const failure = previousError ? `\n\n## Previous attempt failed\n${previousError}` : ''
  return `${fs.readFileSync(path.join(atlasHome, 'prompt.md'), 'utf8')}\n\n## Assigned task\n${task.body}${spec}${otherTasks}${failure}\n\n## Result file\nWrite JSON to ${JSON.stringify(resultFile)}.\n`
}

// Returns the agent's result, or null when it is missing or does not match the task.
function readResult(file, taskId) {
  const value = git.attempt(() => JSON.parse(fs.readFileSync(file, 'utf8')))
  const valid = value?.taskId === taskId && ['done', 'blocked'].includes(value.status) &&
    typeof value.summary === 'string' && value.summary.trim() &&
    typeof value.verification === 'string' && value.verification.trim()
  return valid ? value : null
}

// Run every configured gate; return the first failure's command and output tail, or null.
// Gate names are logged, not printed: the terminal stays limited to progress messages.
async function runGates(cwd, config, log, signal) {
  for (const gate of config.gates) {
    fs.appendFileSync(log, `\nGate: ${gate}\n`)
    const result = await agent.runShell(gate, { cwd, log, timeout: config.timeout, signal })
    if (result.code === 130) throw agent.interrupted()
    if (result.code !== 0) return `${gate}\n${result.output}`
  }
  return null
}

function progressBar(current, total) {
  const filled = total > 0 ? Math.round((current / total) * 10) : 0
  return '█'.repeat(filled) + '░'.repeat(10 - filled)
}

// One renderer for both the terminal and Telegram, so they never drift apart.
function renderMessage({ project, index, total, task, status, pr, pending, reason, log, final }) {
  const lines = [`Atlas › ${project}`]
  if (final) {
    lines.push(pending ? `⚠️ Iteration limit reached. ${pending} pending` : '🎉 All tasks completed!')
    return lines.join('\n')
  }
  lines.push(`Task ${index}/${total}  ${progressBar(index, total)}`)
  lines.push(`${status === 'done' ? '✅' : '❌'} ${task}`)
  if (status === 'done') lines.push(`🔗 ${pr}`)
  else { lines.push(`Reason: ${reason}`); lines.push(`Log: ${log}`) }
  lines.push(`📋 ${pending} pending`)
  return lines.join('\n')
}

// Print to the terminal and, when configured, send the same text to Telegram.
async function notify(text) {
  console.log(text)
  const bot = process.env.ATLAS_TELEGRAM_BOT
  const chat = process.env.ATLAS_TELEGRAM_CHAT
  if (!bot || !chat) return
  try {
    await fetch(`https://api.telegram.org/bot${bot}/sendMessage`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ chat_id: chat, text }),
      signal: AbortSignal.timeout(15000),
    })
  } catch (error) {
    console.warn(`Telegram notification failed: ${error.message}`)
  }
}

// One attempt: run the provider, restore the backlog if the agent touched
// it, and return { error } describing why the attempt failed, or the report.
async function attempt(cwd, config, branch, task, promptFile, resultFile, log, signal) {
  const backlogFile = path.join(cwd, '.atlas/backlog.md')
  const snapshot = fs.readFileSync(backlogFile, 'utf8')
  const result = await agent.runTask(config.provider, promptFile, { cwd, log, timeout: config.timeout, signal })
  if (fs.readFileSync(backlogFile, 'utf8') !== snapshot) fs.writeFileSync(backlogFile, snapshot)
  if (result.code === 130 || signal.aborted) throw agent.interrupted()
  if (git.currentBranch(cwd) !== branch) throw new Error('The agent switched Git branches; stopping to preserve evidence.')
  if (result.code !== 0) return { error: `Provider exited with code ${result.code}.` }
  const report = readResult(resultFile, task.id)
  if (!report) return { error: `Missing or invalid task result: ${resultFile}` }
  if (report.status === 'blocked') return { error: `Task reported blocked: ${report.summary}` }
  const gateFailure = await runGates(cwd, config, log, signal)
  if (gateFailure) return { error: `Gate failed: ${gateFailure}` }
  return { summary: report.summary, verification: report.verification }
}

// A field such as `- **Description:** ...` from a task body, same style as backlog.js's Spec regex.
function taskField(body, name) {
  return body.match(new RegExp(`^- \\*\\*${name}:\\*\\*\\s*(.+)$`, 'm'))?.[1].trim()
}

// Tasks that ended without their own PR (Q6): one line per `chore(<ID>): …`
// commit between the run's base and the stack's top branch, title from the
// (already loaded) backlog, note from the chore subject.
function loadNotes(cwd, backlogTasks, base, top) {
  const log = git.attempt(() => git.git(cwd, 'log', `${base}..${top}`, '--grep=^chore(', '--format=%s')) || ''
  return log.split('\n').filter(Boolean).reverse().map(subject => {
    const [, id, detail] = subject.match(/^chore\(([^)]+)\):\s*(.+)$/) || []
    const title = backlogTasks.find(t => t.id === id)?.title || id
    const note = detail.replace(/^delay task — /, 'delayed: ')
    return { id, title, note }
  })
}

// Fixed PR body (Q5): Task, Acceptance, Changes, Verification, Stack, Spec,
// and Notes on the top PR only, for tasks that ended without their own PR.
// `numbers` is one PR number (or null while a new PR has none yet) per `tasks` entry.
function buildPrBody(backlogTasks, config, task, tasks, index, notes, numbers) {
  const backlogTask = backlogTasks.find(t => t.id === task.id)
  const body = backlogTask ? backlogTask.body : ''
  const description = taskField(body, 'Description') || 'None.'
  const acceptance = taskField(body, 'Acceptance') || 'None.'
  const spec = taskField(body, 'Spec') || 'None.'
  const gatesText = config.gates.length ? config.gates.map(g => `- ✅ \`${g}\``).join('\n') : 'No Atlas gates configured.'
  const stackText = tasks.map((t, i) => {
    const line = `${numbers[i] ? `#${numbers[i]}` : '#?'} ${t.id}: ${t.title}`
    return i === index ? `- **${line} (this PR)**` : `- ${line}`
  }).join('\n')
  let text = `## Task\n${task.id}: ${task.title}\n${description}\n\n## Acceptance\n${acceptance}\n\n## Changes\n${task.summary}\n\n## Verification\n${task.verification}\n${gatesText}\n\n## Stack\n${stackText}\n\n## Spec\n${spec}\n`
  if (index === tasks.length - 1 && notes.length) text += `\n## Notes\n${notes.map(n => `- ${n.id}: ${n.title} — ${n.note}`).join('\n')}\n`
  return text
}

// Publish the whole stack: push every branch, create any missing PR, register
// the native GitHub stack, then refresh every body once. Best-effort: never
// throws, retried after the next task. Returns the top PR number, or null.
function publish(cwd, dir, backlogFile, config, ctx) {
  if (!git.attempt(() => git.git(cwd, 'remote', 'get-url', 'origin'))) return null
  try {
    git.ensureGhStack(cwd)
    const stack = git.stackBranches(cwd, ctx.run, ctx.base)
    if (!stack.length) return null
    git.git(cwd, 'push', '-u', 'origin', ...stack)
    const backlogTasks = backlog.load(backlogFile).tasks
    const tasks = stack.map(branch => ({ branch, ...git.branchTask(cwd, branch) }))
    const notes = loadNotes(cwd, backlogTasks, ctx.base, stack[stack.length - 1])
    const numbers = tasks.map(t => git.prNumber(cwd, t.branch))
    tasks.forEach((task, index) => {
      if (numbers[index]) return
      const previousBranch = index === 0 ? ctx.base : stack[index - 1]
      const bodyFile = path.join(dir, 'runs', `pr-${task.id}.md`)
      fs.writeFileSync(bodyFile, buildPrBody(backlogTasks, config, task, tasks, index, notes, numbers))
      numbers[index] = git.createPr(cwd, task.branch, previousBranch, `feat(${task.id}): ${task.title}`, bodyFile)
    })
    git.stackLink(cwd, stack)
    tasks.forEach((task, index) => {
      const bodyFile = path.join(dir, 'runs', `pr-${task.id}.md`)
      fs.writeFileSync(bodyFile, buildPrBody(backlogTasks, config, task, tasks, index, notes, numbers))
      git.gh(cwd, 'pr', 'edit', task.branch, '--body-file', bodyFile)
    })
    return numbers[numbers.length - 1] || null
  } catch (error) {
    console.warn(`Publish failed: ${error.message}; will retry after the next task.`)
    return null
  }
}

async function run(cwd, config, signal) {
  const dir = path.join(cwd, '.atlas')
  if (!agent.hasBinary(config.provider)) throw new Error(`${agent.PROVIDERS[config.provider].bin} not found on PATH.`)
  if (config.gates.length === 0) console.log("No gates configured; relying on the agent's result.")
  fs.mkdirSync(path.join(dir, 'runs'), { recursive: true })
  const backlogFile = path.join(dir, 'backlog.md')
  if (!backlog.next(backlog.load(backlogFile))) { console.log('No runnable tasks.'); return 0 }
  const ctx = git.currentRun(cwd, config)
  let count = 0
  for (; count < config.iterations; count++) {
    if (signal.aborted) throw agent.interrupted()
    const task = backlog.next(backlog.load(backlogFile))
    if (!task) break
    if (task.state === 'TODO') backlog.move(backlogFile, task.id, 'IN_PROGRESS', { Started: new Date().toISOString() })
    const allTasks = backlog.load(backlogFile).tasks
    const branch = git.taskBranch(ctx.run, task)
    const priorStack = git.stackBranches(cwd, ctx.run, ctx.base).filter(b => b !== branch)
    const previousTop = priorStack.length ? priorStack[priorStack.length - 1] : ctx.base
    if (git.currentBranch(cwd) !== branch) git.git(cwd, 'switch', '-c', branch)
    console.log(`⏳ ${task.id}: ${task.title}… working`)
    let error = null
    let success = null
    for (let attemptNumber = 1; attemptNumber <= config.retries; attemptNumber++) {
      const tag = `${task.id}-${attemptNumber}`
      const log = path.join(dir, 'runs', `${tag}.log`)
      const promptFile = path.join(dir, 'runs', `${tag}.prompt.md`)
      const resultFile = path.join(dir, 'runs', `${tag}.result.json`)
      fs.writeFileSync(promptFile, buildPrompt(cwd, task, allTasks, resultFile, error))
      fs.rmSync(resultFile, { force: true })
      const outcome = await attempt(cwd, config, branch, task, promptFile, resultFile, log, signal)
      error = outcome.error || null
      if (!error) { success = outcome; break }
      console.log(`↻ Attempt ${attemptNumber} failed: ${error.split('\n')[0]}`)
    }
    const reason = error ? error.split('\n')[0] : null
    const log = path.join(dir, 'runs', `${task.id}-${config.retries}.log`)
    let isCodeTask = false
    if (!error) {
      isCodeTask = !git.cleanOutsideAtlas(cwd)
      backlog.move(backlogFile, task.id, 'DONE', { Completed: new Date().toISOString() })
      if (isCodeTask) {
        git.commitAll(cwd, `feat(${task.id}): ${task.title}`, success.summary, success.verification)
      } else {
        git.git(cwd, 'switch', previousTop)
        git.git(cwd, 'branch', '-D', branch)
        if (previousTop !== ctx.base) git.commitAll(cwd, `chore(${task.id}): done without code changes`)
      }
    } else {
      git.discardChanges(cwd)
      backlog.move(backlogFile, task.id, 'DELAYED', { Reason: reason })
      git.git(cwd, 'switch', previousTop)
      git.git(cwd, 'branch', '-D', branch)
      if (previousTop !== ctx.base) git.commitAll(cwd, `chore(${task.id}): delay task — ${reason}`)
    }
    const pr = publish(cwd, dir, backlogFile, config, ctx)
    const remaining = backlog.counts(backlog.load(backlogFile))
    const pending = remaining.TODO + remaining.IN_PROGRESS
    await notify(renderMessage({
      project: path.basename(cwd), index: count + 1, total: count + 1 + pending,
      task: `${task.id}: ${task.title}`, status: error ? 'failed' : 'done',
      pr: !isCodeTask ? 'No PR (no code changes)' : pr ? `PR #${pr}` : 'not published',
      reason, log: path.relative(cwd, log),
      pending,
    }))
  }
  const remaining = backlog.counts(backlog.load(backlogFile))
  const pending = remaining.TODO + remaining.IN_PROGRESS
  await notify(renderMessage({ project: path.basename(cwd), final: true, pending }))
  return pending ? 2 : 0
}

module.exports = { run }
