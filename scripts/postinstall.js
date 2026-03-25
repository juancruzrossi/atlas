#!/usr/bin/env node

const { existsSync, mkdirSync, cpSync, readdirSync, chmodSync, readFileSync, writeFileSync } = require('fs')
const { resolve, join } = require('path')
const { execSync } = require('child_process')
const { createHash } = require('crypto')

const atlasHome = resolve(__dirname, '..')
const skillsDir = join(atlasHome, 'skills')
const homeDir = process.env.HOME || process.env.USERPROFILE
const MANIFEST_NAME = '.atlas-skills-manifest.json'
const REGISTRY_FILE = join(atlasHome, '.npm-registry')

function warn(message) {
  process.stderr.write(`Warning: ${message}\n`)
}

function resolveRegistry(env) {
  const explicit = env.npm_config_registry || env.NPM_CONFIG_REGISTRY
  if (explicit) return explicit

  try {
    return execSync('npm config get registry', {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
    }).trim()
  } catch {
    return ''
  }
}

if (!existsSync(skillsDir)) process.exit(0)

const skillDirs = readdirSync(skillsDir).filter(d =>
  d.startsWith('atlas-') && existsSync(join(skillsDir, d, 'SKILL.md'))
)

if (skillDirs.length === 0) process.exit(0)

const registry = resolveRegistry(process.env)
if (registry) {
  try {
    writeFileSync(REGISTRY_FILE, `${registry}\n`)
  } catch (error) {
    warn(`could not persist npm registry: ${error.message}`)
  }
}

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

function sha256(filePath) {
  try {
    const content = readFileSync(filePath)
    return createHash('sha256').update(content).digest('hex')
  } catch { return null }
}

function loadManifest(targetDir) {
  const manifestPath = join(targetDir, MANIFEST_NAME)
  try {
    return JSON.parse(readFileSync(manifestPath, 'utf8'))
  } catch { return {} }
}

function saveManifest(targetDir, manifest) {
  writeFileSync(join(targetDir, MANIFEST_NAME), JSON.stringify(manifest, null, 2) + '\n')
}

function getSkillFiles(dir) {
  if (!existsSync(dir)) return []
  return readdirSync(dir).filter(f => !f.startsWith('.'))
}

for (const targetDir of providers) {
  const manifest = loadManifest(targetDir)
  const newManifest = { ...manifest }

  for (const skill of skillDirs) {
    const srcDir = join(skillsDir, skill)
    const destDir = join(targetDir, skill)
    mkdirSync(destDir, { recursive: true })

    for (const file of getSkillFiles(srcDir)) {
      const srcFile = join(srcDir, file)
      const destFile = join(destDir, file)
      const srcHash = sha256(srcFile)
      const manifestKey = `${skill}/${file}`
      const destExists = existsSync(destFile)

      if (destExists) {
        const destHash = sha256(destFile)
        const lastKnownHash = manifest[manifestKey]

        // File was customized by user (hash differs from what we installed)
        if (lastKnownHash && destHash !== lastKnownHash && destHash !== srcHash) {
          try {
            cpSync(srcFile, destFile + '.new')
          } catch (error) {
            warn(`could not preserve updated skill '${manifestKey}' as '.new': ${error.message}`)
          }
          newManifest[manifestKey] = srcHash
          continue
        }
      }

      try {
        cpSync(srcFile, destFile)
        newManifest[manifestKey] = srcHash
      } catch (error) {
        warn(`could not install skill '${manifestKey}': ${error.message}`)
      }
    }
  }

  saveManifest(targetDir, newManifest)
}

// Ensure atlas.sh is executable
try {
  chmodSync(join(atlasHome, 'atlas.sh'), 0o755)
} catch (error) {
  warn(`could not mark atlas.sh as executable: ${error.message}`)
}

// Ensure notify-telegram.sh is executable
try {
  chmodSync(join(atlasHome, 'notify-telegram.sh'), 0o755)
} catch (error) {
  warn(`could not mark notify-telegram.sh as executable: ${error.message}`)
}
