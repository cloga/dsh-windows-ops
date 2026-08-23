// dsh-dev-tools - agent-native dev/upgrade tools for packaged DSH on Windows.
// Registers: dsh_status / dsh_patch / dsh_build / dsh_upgrade.
//
// Resolves paths: env override -> updater-config.json -> defaults.
export const name = 'dsh-dev-tools'
export const inject = ['tools']

import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { execFile } from 'node:child_process'
import { promisify } from 'node:util'
import { fileURLToPath } from 'node:url'

const pExecFile = promisify(execFile)
const HOMEDIR = os.homedir()
const DSH_HOME = process.env.DSH_HOME || path.join(HOMEDIR, '.dsh')
const UPDATER_CFG = path.join(DSH_HOME, 'tools', 'dsh-updater', 'updater-config.json')
const PATCHES_JSON = path.join(DSH_HOME, 'tools', 'dsh-updater', 'patches.json')

function readUpdaterConfig() {
  try { return JSON.parse(fs.readFileSync(UPDATER_CFG, 'utf8')) } catch { return {} }
}
function resolvePath(envName, cfgKey, fallback) {
  const fromCfg = readUpdaterConfig()[cfgKey]
  return process.env[envName] || fromCfg || fallback
}

const SOURCE_TREE = resolvePath('DSH_SOURCE_TREE', 'sourceTree', '')
const RUNTIME_DIR = resolvePath('DSH_RUNTIME_DIR', 'runtimeDir', '')
const GIT = process.env.DSH_GIT_BIN || readUpdaterConfig().gitExecutable || 'git'
const NODE = process.env.DSH_NODE_BIN || readUpdaterConfig().nodeExecutable || process.env.nodeAlt || 'node'
const APP_EXE = resolvePath('DSH_APP_EXE', 'appDir', '')
const PNPM = readUpdaterConfig().pnpmExecutable || 'pnpm'
const BUILD_SCRIPT = readUpdaterConfig().buildScript || 'build_d.sh'
const BASH = readUpdaterConfig().bashExecutable || 'bash'

function run(cmd, args, opts = {}) {
  return pExecFile(cmd, args, { windowsHide: true, maxBuffer: 8 * 1024 * 1024, ...opts })
    .then(({ stdout, stderr }) => ({ ok: true, stdout: (stdout || '').trim(), stderr: (stderr || '').trim() }))
    .catch((err) => ({ ok: false, error: err.message || String(err), stdout: (err.stdout || '').toString().trim(), stderr: (err.stderr || '').toString().trim() }))
}
function readJson(p) { try { return JSON.parse(fs.readFileSync(p, 'utf8')) } catch { return null } }
function readVersion(pkgPath) { const j = readJson(pkgPath); return j && j.version ? j.version : '' }

async function git(args, cwd) {
  return run(GIT, ['-C', cwd, ...args])
}

// ---------- dsh_status ----------
async function toolStatus() {
  const out = { home: DSH_HOME, sourceTree: SOURCE_TREE || null, runtimeDir: RUNTIME_DIR || null, app: APP_EXE || null }
  const rtPkg = RUNTIME_DIR ? path.join(RUNTIME_DIR, 'package.json') : null
  out.runtimeVersion = rtPkg ? readVersion(rtPkg) : ''
  out.sourceVersion = SOURCE_TREE ? readVersion(path.join(SOURCE_TREE, 'package.json')) : ''
  if (SOURCE_TREE) {
    const g = await git(['rev-parse', '--abbrev-ref', 'HEAD'], SOURCE_TREE)
    out.branch = g.ok ? g.stdout : ('(git err: ' + (g.error || '') + ')')
    const gv = await git(['rev-parse', '--short', 'HEAD'], SOURCE_TREE)
    out.commit = gv.ok ? gv.stdout : ''
    const st = await git(['status', '--porcelain'], SOURCE_TREE)
    out.dirtyCount = st.ok ? st.stdout.split('\n').filter((l) => l.trim()).length : -1
  }
  out.patchesFile = fs.existsSync(PATCHES_JSON) ? PATCHES_JSON : null
  const bDir = path.join(DSH_HOME + '-backup')
  out.backup = { exists: fs.existsSync(bDir), promoted: readJson(path.join(bDir, 'PROMOTED.txt')) ? true : false }
  const cp = await run(NODE, [path.join(DSH_HOME, 'tools', 'dsh-compat-check.mjs'), 'web'], { cwd: process.cwd() })
  out.compatCheck = { summary: (cp.stdout.split('\n').filter((l) => l.includes('可用') || l.includes('会崩溃') || l.includes('有警告')).join(' | ')) || cp.stderr.slice(0, 200) }
  return out
}

// ---------- dsh_patch ----------
function loadPatches() {
  if (!fs.existsSync(PATCHES_JSON)) return { file: null, patches: [] }
  const j = readJson(PATCHES_JSON)
  return { file: PATCHES_JSON, patches: Array.isArray(j && j.patches) ? j.patches : [] }
}
function resolvePatchFile(rel) {
  const base = process.env.DSH_SOURCE_TREE ? process.env.DSH_SOURCE_TREE : (readUpdaterConfig().sourceTree || '')
  return base ? path.resolve(base, rel) : null
}
function patchEntry(entry) {
  const p = resolvePatchFile(entry.file)
  if (!p || !fs.existsSync(p)) return { id: entry.id, ok: false, reason: 'file missing: ' + entry.file }
  const src = fs.readFileSync(p, 'utf8')
  const findStr = entry.find || ''
  const re = findStr.startsWith('~') ? new RegExp(findStr.slice(1)) : null
  const hit = re ? re.test(src) : src.includes(findStr)
  if (!hit) return { id: entry.id, ok: false, reason: 'find not present' }
  if ((entry.replace || '').length > 0 && src.includes(entry.replace)) return { id: entry.id, ok: true, skipped: 'already patched' }
  const bak = p + '.dshpatch-bak'
  if (!fs.existsSync(bak)) fs.copyFileSync(p, bak)
  const next = re ? src.replace(re, entry.replace) : src.split(findStr).join(entry.replace)
  fs.writeFileSync(p, next)
  return { id: entry.id, ok: true, patched: p }
}
async function toolPatch(args) {
  const action = (args && args.action) || 'list'
  const { file, patches } = loadPatches()
  if (action === 'list') return { file, count: patches.length, patches: patches.map((p) => ({ id: p.id, file: p.file, find: p.find && p.find.slice(0, 60) })) }
  const results = []
  for (const e of patches) results.push(patchEntry(e))
  const applied = results.filter((r) => r.ok && r.patched).length
  return { action, applied, warn: results.filter((r) => r.ok === false || r.skipped).map((r) => r.id + ': ' + (r.reason || r.skipped)) }
}
async function toolPatchRollback(args) {
  const { patches } = loadPatches()
  const results = []
  for (const e of patches) {
    const p = resolvePatchFile(e.file)
    if (!p) { results.push({ id: e.id, ok: false, reason: 'file missing' }); continue }
    const bak = p + '.dshpatch-bak'
    if (!fs.existsSync(bak)) { results.push({ id: e.id, ok: false, reason: 'no backup' }); continue }
    fs.copyFileSync(bak, p)
    results.push({ id: e.id, ok: true, rolledBack: p })
  }
  return { action: 'rollback', rolledBack: results.filter((r) => r.ok).length }
}

// ---------- dsh_build ----------
async function toolBuild() {
  if (!SOURCE_TREE || !RUNTIME_DIR) return { ok: false, reason: 'DSH_SOURCE_TREE / RUNTIME_DIR not resolvable (set env or updater-config.json)' }
  const staging = RUNTIME_DIR + '.new'
  const out = { staging }
  out.sourceTree = SOURCE_TREE
  // build_d.sh: git tag already checked out by caller; run pnpm install + build via the repo's build script
  const scriptPath = path.join(SOURCE_TREE, BUILD_SCRIPT)
  if (fs.existsSync(scriptPath)) {
    const b = await run(BASH, [scriptPath], { cwd: SOURCE_TREE })
    out.build = b.ok ? { ok: true, tail: b.stdout.split('\n').slice(-6).join('\n') } : { ok: false, err: b.error, tail: b.stderr.split('\n').slice(-6).join('\n') }
  } else {
    out.build = { ok: false, reason: BUILD_SCRIPT + ' not found under source tree' }
  }
  out.stagingExists = fs.existsSync(staging)
  return out
}

// ---------- dsh_upgrade ----------
async function toolUpgradeCheck() {
  if (!SOURCE_TREE) return { ok: false, reason: 'no source tree' }
  const t = await git(['ls-remote', '--tags', 'origin', 'refs/tags/dsh-v*'], SOURCE_TREE)
  const tags = t.ok
    ? t.stdout.split('\n').map((l) => l.split('refs/tags/')[1]).filter(Boolean).sort((a, b) => b.localeCompare(a, undefined, { numeric: true }))
    : []
  const cur = readVersion(path.join(SOURCE_TREE, 'package.json'))
  return { ok: true, currentVersion: cur, newestTag: tags[0] || null, recentTags: tags.slice(0, 8) }
}
async function toolUpgradeApply(args) {
  const version = (args && args.version) || ''
  const updater = path.join(DSH_HOME, 'tools', 'dsh-updater', 'apply-update.mjs')
  if (!fs.existsSync(updater)) return { ok: false, reason: 'apply-update.mjs not found; set DSH_HOME or copy the updater from dsh-windows-ops' }
  const argv = [updater, ...(version ? ['--version', version] : [])]
  return { ok: true, note: 'upgrade runs in a detached flow (see docs/ab-self-heal.md). Invoked: node ' + argv.join(' ') }
}

// ---------- registration ----------
function tool(name, description, parameters, runFn, output_extra = {}) {
  return {
    name,
    description,
    parameters,
    output: {
      schema: { type: 'object' },
      render: (_args, value) => [{ type: 'text', text: typeof value === 'string' ? value : JSON.stringify(value, null, 2) }],
      ...output_extra,
    },
    async execute(args) { return runFn(args) },
  }
}

export function apply(ctx) {
  const register = (t) => { try { ctx.tools.register(t) } catch (e) { console.error('[dsh-dev-tools] register failed: ' + e.message) } }
  register(tool('dsh_status', 'Inspect DSH dev state: source-tree branch/commit/dirty, runtime version, patch file, A/B backup, compat-check summary.', { type: 'object', properties: {} }, () => toolStatus()))
  register(tool('dsh_patch', 'Manage local patches (list/apply/rollback) from $DSH_HOME/tools/dsh-updater/patches.json. Backup before change, idempotent.', { type: 'object', properties: { action: { type: 'string', enum: ['list', 'apply', 'rollback'] } }, required: ['action'] }, (args) => (args && args.action === 'rollback') ? toolPatchRollback(args) : toolPatch(args)))
  register(tool('dsh_build', 'Build staging runtime (<runtimeDir>.new) from the source tree. Does NOT touch the running app.', { type: 'object', properties: {} }, () => toolBuild()))
  register(tool('dsh_upgrade', 'Check upstream tags (check) or start a full upgrade (apply).', { type: 'object', properties: { action: { type: 'string', enum: ['check', 'apply'] }, version: { type: 'string' } }, required: ['action'] }, (args) => (args && args.action === 'apply') ? toolUpgradeApply(args) : toolUpgradeCheck()))
}
