'use strict'
const fs = require('node:fs')
const args = process.argv.slice(2)
fs.appendFileSync('.atlas/github-calls', JSON.stringify(args) + '\n')
if (process.env.FAKE_GH_FAILURE === args[1]) process.exit(1)
if (args[0] === 'auth') process.exit(0)
if (args[1] === 'view') {
  if (!fs.existsSync('.atlas/fake-pr')) process.exit(1)
  console.log(JSON.stringify({ url: 'https://example.test/pull/7', state: process.env.FAKE_PR_STATE || 'OPEN' }))
} else if (args[1] === 'create') {
  fs.writeFileSync('.atlas/fake-pr', 'open')
}
