'use strict'
const fs = require('node:fs')
const args = process.argv.slice(2)
fs.appendFileSync('.atlas/github-calls', JSON.stringify(args) + '\n')
if (process.env.FAKE_GH_FAILURE === args[1]) process.exit(1)
if (args[0] === 'auth') process.exit(0)
if (args[1] === 'list') console.log(fs.existsSync('.atlas/fake-pr') ? '[{"number":7,"state":"OPEN"}]' : '[]')
if (args[1] === 'create') fs.writeFileSync('.atlas/fake-pr', 'open')
if (args[1] === 'view') {
  const session = JSON.parse(fs.readFileSync('.atlas/session.json', 'utf8'))
  console.log(JSON.stringify({ number: 7, url: 'https://example.test/pull/7', state: process.env.FAKE_PR_STATE || 'OPEN', headRefName: session.branch, baseRefName: session.base }))
}
