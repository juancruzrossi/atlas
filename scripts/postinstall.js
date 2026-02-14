#!/usr/bin/env node

const { existsSync, mkdirSync, cpSync, readdirSync, chmodSync } = require('fs')
const { resolve, join } = require('path')
const { execSync } = require('child_process')

const atlasHome = resolve(__dirname, '..')
const skillsDir = join(atlasHome, 'skills')
const homeDir = process.env.HOME || process.env.USERPROFILE

if (!existsSync(skillsDir)) process.exit(0)

const skillDirs = readdirSync(skillsDir).filter(d =>
  d.startsWith('atlas-') && existsSync(join(skillsDir, d, 'SKILL.md'))
)

if (skillDirs.length === 0) process.exit(0)

const providers = []

// Detect installed AI providers
const hasCommand = (cmd) => {
  try {
    execSync(`command -v ${cmd}`, { stdio: 'ignore' })
    return true
  } catch { return false }
}

if (hasCommand('claude')) providers.push(join(homeDir, '.claude', 'skills'))
if (hasCommand('opencode')) providers.push(join(homeDir, '.config', 'opencode', 'skills'))
if (hasCommand('codex')) providers.push(join(homeDir, '.codex', 'skills'))

for (const targetDir of providers) {
  for (const skill of skillDirs) {
    const dest = join(targetDir, skill)
    mkdirSync(dest, { recursive: true })
    try {
      cpSync(join(skillsDir, skill), dest, { recursive: true })
    } catch { /* ignore copy errors */ }
  }
}

// Ensure atlas.sh is executable
try {
  chmodSync(join(atlasHome, 'atlas.sh'), 0o755)
} catch { /* ignore */ }

// Ensure notify-telegram.sh is executable
try {
  chmodSync(join(atlasHome, 'notify-telegram.sh'), 0o755)
} catch { /* ignore */ }
