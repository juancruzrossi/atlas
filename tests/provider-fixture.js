'use strict'
const fs = require('node:fs')
const { spawn } = require('node:child_process')
const args = process.argv.slice(2)
fs.appendFileSync('.atlas/provider-calls', JSON.stringify(args) + '\n')
const instruction = args[args.length - 1]
const promptFile = instruction.match(/^Read "(.*)" and follow/)[1]
const prompt = fs.readFileSync(promptFile, 'utf8')
const resultFile = prompt.match(/Write JSON to "([^"]+)"/)[1]
const taskId = prompt.match(/## Assigned task\n### ([A-Za-z0-9_-]+):/)[1]
const behavior = process.env.FAKE_BEHAVIOR || 'done'
console.log('provider output is streamed')
if (behavior === 'failure') { console.log('<promise>COMPLETE</promise>'); process.exit(42) }
if (behavior === 'promise') { console.log('<promise>COMPLETE</promise>'); process.exit(0) }
if (behavior === 'hang') {
  const child = spawn(process.execPath, ['-e', 'process.on("SIGTERM", () => {}); setInterval(() => {}, 1000)'], { stdio: 'inherit' })
  fs.writeFileSync('.atlas/child-pid', String(child.pid))
  process.on('SIGTERM', () => {})
  setInterval(() => {}, 1000)
} else {
  fs.writeFileSync('implementation.txt', taskId)
  if (behavior === 'tamper') fs.appendFileSync('.atlas/backlog.md', '\nchanged by provider\n')
  const report = { taskId: behavior === 'wrong-id' ? 'OTHER-1' : taskId, status: behavior === 'blocked' ? 'blocked' : 'done', summary: 'Implemented and verified the task.' }
  fs.writeFileSync(resultFile, behavior === 'bad-json' ? '{broken' : JSON.stringify(report))
}
