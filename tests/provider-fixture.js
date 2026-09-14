'use strict'
const fs = require('node:fs')
const path = require('node:path')
const { spawn } = require('node:child_process')
const args = process.argv.slice(2)
const prompt = args.includes('--file') ? fs.readFileSync(args[args.indexOf('--file') + 1], 'utf8') : fs.readFileSync(0, 'utf8')
fs.appendFileSync('.atlas/provider-calls', JSON.stringify(args) + '\n')
const resultPath = JSON.parse(prompt.match(/Write JSON to (".*") with this exact contract:/)[1])
const taskId = JSON.parse(prompt.match(/\{"taskId":("[^"]+")/)[1])
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
  fs.writeFileSync(resultPath, behavior === 'bad-json' ? '{broken' : JSON.stringify(report))
}
