'use strict'
const fs = require('node:fs')
const path = require('node:path')
const { randomUUID } = require('node:crypto')
const backlog = require('./backlog')
const storage = require('./storage')
const git = require('./git')
const providers = require('./providers')
const { execute } = require('./process')
const atlasHome = path.resolve(__dirname, '..')

function sessionPaths(cwd) {
  const dir = path.join(cwd, '.atlas')
  return { dir, queue: path.join(dir, 'backlog.md'), sessionFile: path.join(dir, 'session.json'), runs: path.join(dir, 'runs') }
}
function loadSession(file) {
  const session = storage.json(file)
  if (session && (session.version !== 1 || !['git', 'local'].includes(session.mode) || typeof session.id !== 'string' || !/^[a-zA-Z0-9-]+$/.test(session.id) || !['running', 'paused', 'complete', 'failed', 'interrupted', 'publishing'].includes(session.status) || !Array.isArray(session.completed) || (session.mode === 'git' && (typeof session.branch !== 'string' || typeof session.base !== 'string' || !/^[a-f0-9]{40,64}$/.test(session.head))))) throw new Error('Invalid Atlas session. Inspect .atlas/session.json before continuing.')
  return session
}
function taskPrompt(cwd, task, resultFile) {
  const files = ['AGENTS.md', 'CLAUDE.md', '.atlas/guardrails.md', '.atlas/progress.txt', '.atlas/errors.log']
  let spec = ''
  if (task.spec) {
    const full = path.resolve(cwd, task.spec)
    const real = fs.realpathSync(full)
    if (!real.startsWith(fs.realpathSync(cwd) + path.sep)) throw new Error(`Task spec must be inside the project: ${task.spec}`)
    spec = `\n## Feature specification (${task.spec})\n${storage.read(real)}`
  }
  return `${storage.read(path.join(atlasHome, 'prompt.md'))}\n\n## Assigned task\n${task.body}${spec}\n\n## Context files\n${files.filter(f => fs.existsSync(path.join(cwd, f))).map(f => `- ${f}`).join('\n')}\n\n## Result file\nWrite JSON to ${JSON.stringify(resultFile)} with this exact contract:\n{"taskId":${JSON.stringify(task.id)},"status":"done or blocked","summary":"What changed and how it was verified"}\n`
}
async function gates(cwd, config, log, signal) {
  for (const gate of config.gates) {
    console.log(`Gate: ${gate}`)
    fs.appendFileSync(log, `\nGate: ${gate}\n`)
    const result = await execute('/bin/sh', ['-c', gate], { cwd, log, timeout: config.gateTimeout, signal })
    if (result.code !== 0) throw Object.assign(new Error(`Quality gate failed (${result.code}): ${gate}`), { exitCode: result.code })
  }
}
function protectedState(cwd, sessionFile, queue) {
  return new Map([queue, sessionFile, path.join(cwd, '.atlas/config.json')].map(file => [file, storage.read(file, null)]))
}
function verifyProtected(snapshot) {
  for (const [file, contents] of snapshot) if (storage.read(file, null) !== contents) throw Object.assign(new Error(`Agent or gate modified Atlas-owned state: ${file}. Restore it before resuming.`), { modifiedState: file })
}
function result(file, taskId) {
  const value = storage.json(file)
  if (!value || value.taskId !== taskId || !['done', 'blocked'].includes(value.status) || typeof value.summary !== 'string' || !value.summary.trim() || value.summary.length > 10000) throw new Error(`Missing or invalid task result: ${file}`)
  return value
}
async function notify(session, message, signal) {
  if (process.env.ATLAS_NOTIFY_TELEGRAM !== 'true' || !process.env.ATLAS_TELEGRAM_BOT || !process.env.ATLAS_TELEGRAM_CHAT) return
  await execute(path.join(atlasHome, 'notify-telegram.sh'), [String(session.completed.length), String(session.completed.length), path.basename(process.cwd()), message], { timeout: 15, signal, quiet: true }).catch(error => console.error(`Notification: ${error.message}`))
}
async function run(cwd, config, resume, signal) {
  const { dir, queue, sessionFile, runs } = sessionPaths(cwd)
  fs.mkdirSync(runs, { recursive: true })
  if (fs.existsSync(path.join(dir, 'integration-session.json'))) throw new Error('Legacy integration-session.json found. Finish or archive that session before using Atlas 4; see README migration instructions.')
  let tasks = backlog.load(queue)
  let session = loadSession(sessionFile)
  if (resume && !session) throw new Error('No active session to resume. Run atlas first.')
  if (!resume && session && session.status !== 'complete') throw new Error("An unfinished session exists. Use 'atlas resume'.")
  if (!resume && !backlog.next(tasks)) { console.log('No runnable tasks.'); return 0 }
  if (backlog.next(tasks) && !providers.available(providers.bins[config.provider])) throw new Error(`${config.provider} CLI not found`)
  if (config.gates.length === 0) throw new Error('Configure at least one quality gate in .atlas/config.json (gates), then run Atlas again.')
  if (!resume) {
    if (session?.remote) {
      const state = JSON.parse(git.command(cwd, 'gh', ['pr', 'view', String(session.pr_number), '--json', 'state']))
      if (state.state === 'OPEN') throw new Error('The previous session PR is still open. Review it before starting another session.')
    }
    const id = `${new Date().toISOString().replace(/[-:.TZ]/g, '')}-${randomUUID().slice(0, 8)}`
    session = { version: 1, id, status: 'running', completed: [], ...git.begin(cwd, id, config) }
    storage.writeJson(sessionFile, session)
  } else if (session.mode === 'git') {
    git.inspect(cwd)
    git.finishCommit(cwd, session, sessionFile)
    git.assertHead(cwd, session)
    git.prState(cwd, session)
  }
  let currentLog = path.join(runs, `run-${session.id}-recovery.log`)
  try {
    if (session.finalizing) {
      // Gate reruns cover edits made after an interrupted finalization.
      const snapshot = protectedState(cwd, sessionFile, queue)
      await gates(cwd, config, currentLog, signal)
      verifyProtected(snapshot)
      session.finalizing.gates = [...config.gates]
      finalize()
    }
    for (let iteration = 0; iteration < config.iterations; iteration++) {
      if (signal.aborted) throw Object.assign(new Error('Interrupted'), { exitCode: 130 })
      tasks = backlog.load(queue)
      const task = backlog.next(tasks)
      if (!task) break
      if (session.mode === 'git') git.assertHead(cwd, session)
      const tag = `${session.id}-${randomUUID().slice(0, 8)}`
      const prefix = path.join(runs, `run-${tag}`)
      currentLog = `${prefix}.log`
      const report = `${prefix}.result.json`
      const promptFile = `${prefix}.prompt.md`
      if (task.state === 'TODO') backlog.transition(queue, task.id, 'IN_PROGRESS', { Started: new Date().toISOString() })
      session.status = 'running'
      session.taskId = task.id
      storage.writeJson(sessionFile, session)
      storage.event(dir, { type: 'task_started', session: session.id, task: task.id, log: currentLog })
      console.log(`Task ${task.id}: ${task.title}`)
      const prompt = taskPrompt(cwd, task, report)
      storage.atomicWrite(promptFile, prompt)
      const snapshot = protectedState(cwd, sessionFile, queue)
      const started = Date.now()
      let outcome = 'failed', exitCode = 1, summary = ''
      try {
        const execution = await providers.run(config.provider, 'build', promptFile, { cwd, input: prompt, log: currentLog, timeout: config.timeout, signal })
        exitCode = execution.code
        verifyProtected(snapshot)
        if (session.mode === 'git') git.assertHead(cwd, session)
        if (exitCode !== 0) throw Object.assign(new Error(`Provider failed (${exitCode}); changes are preserved. Run 'atlas resume' after resolving the failure.`), { exitCode })
        const reportData = result(report, task.id)
        summary = reportData.summary
        if (reportData.status === 'blocked') throw new Error(`Task blocked: ${summary}`)
        await gates(cwd, config, currentLog, signal)
        verifyProtected(snapshot)
        if (session.mode === 'git') git.assertHead(cwd, session)
        session.finalizing = { taskId: task.id, title: task.title, summary, gates: [...config.gates], progressBefore: storage.read(path.join(dir, 'progress.txt')) }
        storage.writeJson(sessionFile, session)
        finalize()
        outcome = 'done'
        exitCode = 0
      } catch (error) {
        exitCode = error.exitCode || 1
        summary = error.message
        throw error
      } finally {
        storage.writeJson(`${prefix}.json`, { task: task.id, status: outcome, exitCode, summary, durationMs: Date.now() - started, log: path.basename(currentLog), provider: config.provider })
        storage.event(dir, { type: 'task_finished', session: session.id, task: task.id, status: outcome, exitCode })
        fs.rmSync(promptFile, { force: true })
      }
    }
    const remaining = backlog.counts(backlog.load(queue))
    const pending = remaining.TODO + remaining.IN_PROGRESS
    if (session.mode === 'git' && session.completed.length) {
      session.status = 'publishing'
      storage.writeJson(sessionFile, session)
      const body = path.join(runs, `pr-${session.id}.md`)
      storage.atomicWrite(body, `## Changes\n\n${session.completed.map(t => `- ${t.id}: ${t.summary}`).join('\n')}\n\n## Verification\n\n${[...new Set(session.completed.flatMap(t => t.gates || []))].map(g => `- \`${g}\``).join('\n')}\n\nPending tasks: ${pending}. This PR is left open for human review.\n`)
      git.publish(cwd, session, sessionFile, body)
    }
    session.status = pending ? 'paused' : 'complete'
    delete session.taskId
    storage.writeJson(sessionFile, session)
    storage.event(dir, { type: 'run_finished', session: session.id, status: session.status, counts: remaining })
    console.log(`${pending ? 'Iteration limit reached' : 'All runnable tasks completed'}. TODO=${remaining.TODO} IN_PROGRESS=${remaining.IN_PROGRESS} DONE=${remaining.DONE} DELAYED=${remaining.DELAYED}`)
    if (session.pr_url) console.log(`PR left open: ${session.pr_url}`)
    await notify(session, `Status: ${session.status}\nPending: ${pending}`, signal)
    return pending ? 2 : 0
  } catch (error) {
    session.status = error.exitCode === 130 ? 'interrupted' : 'failed'
    // Preserve evidence if the agent modified the session itself.
    if (error.modifiedState !== sessionFile) storage.writeJson(sessionFile, session)
    fs.appendFileSync(path.join(dir, 'errors.log'), `[${new Date().toISOString()}] ${session.taskId || session.id}: ${error.message}\n`)
    storage.event(dir, { type: 'run_failed', session: session.id, error: error.message, log: currentLog })
    throw error
  }
  function finalize() {
    const finished = session.finalizing
    const current = backlog.load(queue).tasks.find(t => t.id === finished.taskId)
    if (!current || !['IN_PROGRESS', 'DONE'].includes(current.state)) throw new Error('Cannot recover finalization: task state changed.')
    if (current.state !== 'DONE') backlog.transition(queue, current.id, 'DONE', { Completed: new Date().toISOString() })
    const progress = `${finished.progressBefore.trimEnd()}\n\n## ${finished.taskId}: ${finished.title}\n${finished.summary}\n`
    const progressFile = path.join(dir, 'progress.txt')
    const currentProgress = storage.read(progressFile)
    if (currentProgress !== finished.progressBefore && currentProgress !== progress) throw new Error('Progress changed during finalization recovery; inspect it before resuming.')
    storage.atomicWrite(progressFile, progress)
    if (session.mode === 'git') git.commit(cwd, session, sessionFile, `feat: complete ${finished.taskId}`)
    if (!session.completed.some(t => t.id === finished.taskId)) session.completed.push({ id: finished.taskId, summary: finished.summary, gates: finished.gates })
    delete session.finalizing
    storage.writeJson(sessionFile, session)
  }
}
module.exports = { run, taskPrompt, sessionPaths, loadSession, gates }
