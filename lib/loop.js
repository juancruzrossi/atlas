'use strict'
const fs = require('node:fs')
const path = require('node:path')
const { spawn } = require('node:child_process')
const backlog = require('./backlog')
const agent = require('./agent')
const git = require('./git')

const atlasHome = path.resolve(__dirname, '..')

// Build the prompt for one attempt: task body, its spec file, the previous
// attempt's error (if any), and the exact result file to write.
function buildPrompt(cwd, task, resultFile, previousError) {
  let spec = ''
  if (task.spec) {
    const full = path.resolve(cwd, task.spec)
    if (!fs.realpathSync(path.dirname(full)).startsWith(fs.realpathSync(cwd))) throw new Error(`Task spec must be inside the project: ${task.spec}`)
    spec = `\n\n## Feature specification (${task.spec})\n${fs.readFileSync(full, 'utf8')}`
  }
  const failure = previousError ? `\n\n## Previous attempt failed\n${previousError}` : ''
  return `${fs.readFileSync(path.join(atlasHome, 'prompt.md'), 'utf8')}\n\n## Assigned task\n${task.body}${spec}${failure}\n\n## Result file\nWrite JSON to ${JSON.stringify(resultFile)}.\n`
}

function readResult(file, taskId) {
  let value
  try {
    value = JSON.parse(fs.readFileSync(file, 'utf8'))
  } catch {
    throw new Error(`Missing or invalid task result: ${file}`)
  }
  if (!value || value.taskId !== taskId || !['done', 'blocked'].includes(value.status) || typeof value.summary !== 'string' || !value.summary.trim()) {
    throw new Error(`Missing or invalid task result: ${file}`)
  }
  return value
}

// Run every configured gate; return the first failure's command and output tail, or null.
async function runGates(cwd, config, log, signal) {
  for (const gate of config.gates) {
    console.log(`Gate: ${gate}`)
    fs.appendFileSync(log, `\nGate: ${gate}\n`)
    const result = await agent.runShell(gate, { cwd, log, timeout: config.timeout, signal })
    if (result.code === 130) throw agent.interrupted()
    if (result.code !== 0) return `${gate}\n${result.output}`
  }
  return null
}

// Args match notify-telegram.sh's contract: ITERATION MAX PROJECT SUMMARY,
// where SUMMARY has "Task:", "Status:" and "Pending:" lines.
function notifyTelegram(cwd, iteration, config, taskId, status, pending) {
  if (!process.env.ATLAS_TELEGRAM_BOT || !process.env.ATLAS_TELEGRAM_CHAT) return Promise.resolve()
  const summary = `Task: ${taskId}\nStatus: ${status}\nPending: ${pending}`
  return new Promise(resolve => {
    const child = spawn(path.join(atlasHome, 'notify-telegram.sh'), [String(iteration), String(config.iterations), path.basename(cwd), summary], { cwd, stdio: 'ignore', timeout: 15000 })
    child.once('error', error => { console.error(`Notification: ${error.message}`); resolve() })
    child.once('close', () => resolve())
  })
}

// One attempt: run the provider, restore the backlog if the agent touched
// it, and return { error } describing why the attempt failed, or { summary }.
async function attempt(cwd, config, branch, task, promptFile, resultFile, log, signal) {
  const backlogFile = path.join(cwd, '.atlas/backlog.md')
  const snapshot = fs.readFileSync(backlogFile, 'utf8')
  const result = await agent.runTask(config.provider, promptFile, { cwd, log, timeout: config.timeout, signal })
  if (fs.readFileSync(backlogFile, 'utf8') !== snapshot) fs.writeFileSync(backlogFile, snapshot)
  if (result.code === 130 || signal.aborted) throw agent.interrupted()
  if (git.currentBranch(cwd) !== branch) throw new Error('The agent switched Git branches; stopping to preserve evidence.')
  if (result.code !== 0) return { error: `Provider exited with code ${result.code}.` }
  let report
  try {
    report = readResult(resultFile, task.id)
  } catch (error) {
    return { error: error.message }
  }
  if (report.status === 'blocked') return { error: `Task reported blocked: ${report.summary}` }
  const gateFailure = await runGates(cwd, config, log, signal)
  if (gateFailure) return { error: `Gate failed: ${gateFailure}` }
  return { summary: report.summary }
}

function prBody(cwd, base) {
  const done = git.git(cwd, 'log', `${base}..HEAD`, '--grep=^feat(', '--format=%s')
  const delayed = backlog.load(path.join(cwd, '.atlas/backlog.md')).tasks.filter(t => t.state === 'DELAYED')
  const doneList = done ? done.split('\n').map(line => `- ${line}`).join('\n') : '- (none yet)'
  const delayedList = delayed.length ? delayed.map(t => `- ${t.id}: ${t.title}`).join('\n') : '- (none)'
  return `## Done\n\n${doneList}\n\n## Delayed\n\n${delayedList}\n`
}

async function run(cwd, config, iterations, signal) {
  const dir = path.join(cwd, '.atlas')
  if (!agent.hasBinary(config.provider)) throw new Error(`${agent.PROVIDERS[config.provider].bin} not found on PATH.`)
  if (config.gates.length === 0) console.log("No gates configured; relying on the agent's result.")
  fs.mkdirSync(path.join(dir, 'runs'), { recursive: true })
  const backlogFile = path.join(dir, 'backlog.md')
  if (!backlog.next(backlog.load(backlogFile))) { console.log('No runnable tasks.'); return 0 }
  const branch = git.prepareBranch(cwd)
  const base = git.baseBranch(cwd, config)
  let lastTaskId = ''
  let lastStatus = 'UNKNOWN'
  let count = 0
  for (; count < iterations; count++) {
    if (signal.aborted) throw agent.interrupted()
    const current = backlog.load(backlogFile)
    const task = backlog.next(current)
    if (!task) break
    if (task.state === 'TODO') backlog.move(backlogFile, task.id, 'IN_PROGRESS', { Started: new Date().toISOString() })
    console.log(`Task ${task.id}: ${task.title}`)
    let error = null
    let summary = null
    for (let attemptNumber = 1; attemptNumber <= config.retries; attemptNumber++) {
      const tag = `${task.id}-${attemptNumber}`
      const log = path.join(dir, 'runs', `${tag}.log`)
      const promptFile = path.join(dir, 'runs', `${tag}.prompt.md`)
      const resultFile = path.join(dir, 'runs', `${tag}.result.json`)
      fs.writeFileSync(promptFile, buildPrompt(cwd, task, resultFile, error))
      fs.rmSync(resultFile, { force: true })
      const outcome = await attempt(cwd, config, branch, task, promptFile, resultFile, log, signal)
      error = outcome.error || null
      summary = outcome.summary || null
      if (!error) break
      console.log(`Attempt ${attemptNumber} failed: ${error.split('\n')[0]}`)
    }
    if (!error) {
      backlog.move(backlogFile, task.id, 'DONE', { Completed: new Date().toISOString() })
      const progressFile = path.join(dir, 'progress.txt')
      fs.writeFileSync(progressFile, `${fs.readFileSync(progressFile, 'utf8').trimEnd()}\n\n## ${task.id}: ${task.title}\n${summary}\n`)
      git.commitAll(cwd, `feat(${task.id}): ${task.title}`)
    } else {
      git.discardChanges(cwd)
      backlog.move(backlogFile, task.id, 'DELAYED', { Reason: error.split('\n')[0] })
      git.commitAll(cwd, `chore(${task.id}): delay task`)
    }
    lastTaskId = task.id
    lastStatus = error ? 'FAILED' : 'DONE'
    git.publish(cwd, branch, base, remoteBase => prBody(cwd, remoteBase))
  }
  const remaining = backlog.counts(backlog.load(backlogFile))
  const pending = remaining.TODO + remaining.IN_PROGRESS
  await notifyTelegram(cwd, count, config, lastTaskId, lastStatus, pending)
  console.log(`${pending ? 'Iteration limit reached' : 'No runnable tasks remain'}. TODO=${remaining.TODO} IN_PROGRESS=${remaining.IN_PROGRESS} DONE=${remaining.DONE} DELAYED=${remaining.DELAYED}`)
  return pending ? 2 : 0
}

module.exports = { run, buildPrompt, readResult }
