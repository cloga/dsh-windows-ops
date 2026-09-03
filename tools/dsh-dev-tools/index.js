// dsh-dev-tools - agent-native dev/upgrade tools for packaged DSH on Windows.
// Registers: dsh_status / dsh_doctor / dsh_patch / dsh_build / dsh_upgrade.
//
// Resolves paths: env override -> updater-config.json -> defaults.
export const name = 'dsh-dev-tools'
export const inject = ['tools', 'subprocess']

import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { snapshotJsonValue } from './snapshot-json.js'
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
const BUILD_SCRIPT = readUpdaterConfig().buildScript || 'build_d.sh'
const BASH = readUpdaterConfig().bashExecutable || 'bash'

const MAX_OUTPUT_BYTES = 8 * 1024 * 1024
const PROCESS_GRACE_MS = 5_000

async function run(ctx, cmd, args, opts = {}, signal) {
  signal?.throwIfAborted()
  const executable = await ctx.subprocess.resolveExecutable(cmd, undefined, signal)
  signal?.throwIfAborted()
  const handle = ctx.subprocess.spawn({
    argv: [executable, ...args],
    cwd: opts.cwd || process.cwd(),
    stdio: {
      stdin: 'ignore',
      stdout: { maxBytes: MAX_OUTPUT_BYTES },
      stderr: { maxBytes: MAX_OUTPUT_BYTES },
    },
    graceMs: PROCESS_GRACE_MS,
    signal,
  })
  let outcome
  let failure
  try {
    outcome = await handle.done
  } catch (error) {
    failure = error
  } finally {
    const exited = await handle.waitForExit()
    if (!exited) throw new Error('managed subprocess tree did not reach quiescence')
  }
  signal?.throwIfAborted()
  const stdout = (handle.collected.stdout?.readFrom(0).text || '').trim()
  const stderr = (handle.collected.stderr?.readFrom(0).text || '').trim()
  if (failure) return { ok: false, error: failure.message || String(failure), stdout, stderr }
  const ok = outcome.exitCode === 0 && outcome.signal === null
  return ok
    ? { ok: true, stdout, stderr }
    : { ok: false, error: `process exited with code ${outcome.exitCode ?? 'null'}${outcome.signal ? ` (${outcome.signal})` : ''}`, stdout, stderr }
}
function readJson(p) { try { return JSON.parse(fs.readFileSync(p, 'utf8')) } catch { return null } }
function readVersion(pkgPath) { const j = readJson(pkgPath); return j && j.version ? j.version : '' }

export function normalizeToolOutput(value) {
  const normalized = snapshotJsonValue(value)
  if (normalized === undefined) throw new TypeError('tool output is not losslessly JSON-serializable')
  return normalized
}

async function git(ctx, args, cwd, signal) {
  return run(ctx, GIT, ['-C', cwd, ...args], {}, signal)
}

// ---------- dsh_status ----------
async function toolStatus(ctx, _args, exec) {
  const out = { home: DSH_HOME, sourceTree: SOURCE_TREE || null, runtimeDir: RUNTIME_DIR || null, app: APP_EXE || null }
  const rtPkg = RUNTIME_DIR ? path.join(RUNTIME_DIR, 'package.json') : null
  out.runtimeVersion = rtPkg ? readVersion(rtPkg) : ''
  out.sourceVersion = SOURCE_TREE ? readVersion(path.join(SOURCE_TREE, 'package.json')) : ''
  if (SOURCE_TREE) {
    const g = await git(ctx, ['rev-parse', '--abbrev-ref', 'HEAD'], SOURCE_TREE, exec.signal)
    out.branch = g.ok ? g.stdout : ('(git err: ' + (g.error || '') + ')')
    const gv = await git(ctx, ['rev-parse', '--short', 'HEAD'], SOURCE_TREE, exec.signal)
    out.commit = gv.ok ? gv.stdout : ''
    const st = await git(ctx, ['status', '--porcelain'], SOURCE_TREE, exec.signal)
    out.dirtyCount = st.ok ? st.stdout.split('\n').filter((l) => l.trim()).length : -1
  }
  out.patchesFile = fs.existsSync(PATCHES_JSON) ? PATCHES_JSON : null
  const cp = await run(ctx, NODE, [path.join(DSH_HOME, 'tools', 'dsh-compat-check.mjs'), 'web', '--json'], { cwd: process.cwd() }, exec.signal)
  const compat = tryJson(cp.stdout)
  out.compatCheck = compat
    ? { summary: compat.summary, limitations: compat.limitations }
    : { error: cp.stderr.slice(0, 200) || 'compatibility report unavailable' }
  return out
}

// ---------- dsh_patch ----------
function loadPatches() {
  if (!fs.existsSync(PATCHES_JSON)) return { file: null, patches: [] }
  const j = readJson(PATCHES_JSON)
  return { file: PATCHES_JSON, patches: Array.isArray(j && j.patches) ? j.patches : [] }
}
function canonicalSourceRoot() {
  if (!SOURCE_TREE || !fs.existsSync(SOURCE_TREE)) return null
  return fs.realpathSync.native(path.resolve(SOURCE_TREE))
}
export function isPathInside(root, candidate) {
  const normalizedRoot = process.platform === 'win32' ? root.toLowerCase() : root
  const normalizedCandidate = process.platform === 'win32' ? candidate.toLowerCase() : candidate
  const relative = path.relative(normalizedRoot, normalizedCandidate)
  return relative !== '' && !relative.startsWith(`..${path.sep}`) && relative !== '..' && !path.isAbsolute(relative)
}
function resolvePatchFile(rel) {
  if (typeof rel !== 'string' || rel.trim() === '' || path.isAbsolute(rel)) return null
  const root = canonicalSourceRoot()
  if (!root) return null
  const candidate = path.resolve(root, rel)
  if (!isPathInside(root, candidate) || !fs.existsSync(candidate)) return null
  const canonical = fs.realpathSync.native(candidate)
  return isPathInside(root, canonical) ? canonical : null
}
function patchEntry(entry, signal) {
  signal.throwIfAborted()
  const p = resolvePatchFile(entry.file)
  if (!p) return { id: entry.id, ok: false, reason: 'file is missing or outside DSH_SOURCE_TREE' }
  const findStr = typeof entry.find === 'string' ? entry.find : ''
  if (findStr.length === 0 || findStr === '~') return { id: entry.id, ok: false, reason: 'find must be non-empty' }
  const src = fs.readFileSync(p, 'utf8')
  const re = findStr.startsWith('~') ? new RegExp(findStr.slice(1)) : null
  const hit = re ? re.test(src) : src.includes(findStr)
  if (!hit) return { id: entry.id, ok: false, reason: 'find not present' }
  const replacement = typeof entry.replace === 'string' ? entry.replace : ''
  if (replacement.length > 0 && src.includes(replacement)) return { id: entry.id, ok: true, skipped: 'already patched' }
  const bak = p + '.dshpatch-bak'
  signal.throwIfAborted()
  if (!fs.existsSync(bak)) fs.copyFileSync(p, bak)
  const next = re ? src.replace(re, replacement) : src.split(findStr).join(replacement)
  signal.throwIfAborted()
  fs.writeFileSync(p, next)
  return { id: entry.id, ok: true, patched: p }
}
async function toolPatch(args, exec) {
  exec.signal.throwIfAborted()
  const action = (args && args.action) || 'list'
  const { file, patches } = loadPatches()
  if (action === 'list') return { file, count: patches.length, patches: patches.map((p) => ({ id: p.id ?? null, file: p.file ?? null, find: typeof p.find === 'string' ? p.find.slice(0, 60) : null })) }
  const results = []
  for (const entry of patches) {
    exec.signal.throwIfAborted()
    results.push(patchEntry(entry, exec.signal))
  }
  const applied = results.filter((result) => result.ok && result.patched).length
  return { action, applied, warn: results.filter((result) => result.ok === false || result.skipped).map((result) => `${result.id}: ${result.reason || result.skipped}`) }
}
async function toolPatchRollback(_args, exec) {
  exec.signal.throwIfAborted()
  const { patches } = loadPatches()
  const results = []
  for (const entry of patches) {
    exec.signal.throwIfAborted()
    const p = resolvePatchFile(entry.file)
    if (!p) { results.push({ id: entry.id, ok: false, reason: 'file is missing or outside DSH_SOURCE_TREE' }); continue }
    const bak = p + '.dshpatch-bak'
    if (!fs.existsSync(bak)) { results.push({ id: entry.id, ok: false, reason: 'no backup' }); continue }
    exec.signal.throwIfAborted()
    fs.copyFileSync(bak, p)
    results.push({ id: entry.id, ok: true, rolledBack: p })
  }
  return { action: 'rollback', rolledBack: results.filter((result) => result.ok).length }
}

// ---------- dsh_build ----------
async function toolBuild(ctx, _args, exec) {
  if (!SOURCE_TREE || !RUNTIME_DIR) return { ok: false, reason: 'DSH_SOURCE_TREE / RUNTIME_DIR not resolvable (set env or updater-config.json)' }
  const staging = RUNTIME_DIR + '.new'
  const out = { staging }
  out.sourceTree = SOURCE_TREE
  // build_d.sh: git tag already checked out by caller; run pnpm install + build via the repo's build script
  const scriptPath = path.join(SOURCE_TREE, BUILD_SCRIPT)
  if (fs.existsSync(scriptPath)) {
    const b = await run(ctx, BASH, [scriptPath], { cwd: SOURCE_TREE }, exec.signal)
    out.build = b.ok ? { ok: true, tail: b.stdout.split('\n').slice(-6).join('\n') } : { ok: false, err: b.error, tail: b.stderr.split('\n').slice(-6).join('\n') }
  } else {
    out.build = { ok: false, reason: BUILD_SCRIPT + ' not found under source tree' }
  }
  out.stagingExists = fs.existsSync(staging)
  return out
}

// ---------- dsh_upgrade ----------
async function toolUpgradeCheck(ctx, _args, exec) {
  if (!SOURCE_TREE) return { ok: false, reason: 'no source tree' }
  const t = await git(ctx, ['ls-remote', '--tags', 'origin', 'refs/tags/dsh-v*'], SOURCE_TREE, exec.signal)
  const tags = t.ok
    ? t.stdout.split('\n').map((l) => l.split('refs/tags/')[1]).filter(Boolean).sort((a, b) => b.localeCompare(a, undefined, { numeric: true }))
    : []
  const cur = readVersion(path.join(SOURCE_TREE, 'package.json'))
  return { ok: true, currentVersion: cur, newestTag: tags[0] || null, recentTags: tags.slice(0, 8) }
}
async function toolUpgradeApply(args, _exec) {
  const version = (args && args.version) || null
  return { ok: false, reason: 'legacy apply-update flow is retired; use the locked installer or the Desktop core manager after an explicit check plan', requestedVersion: version }
}

// ---------- dsh_doctor ----------
function tryJson(s) { try { return JSON.parse(s) } catch { return null } }
async function toolDoctor(ctx, args, exec) {
  const doctor = path.join(DSH_HOME, 'tools', 'dsh-doctor.mjs')
  const flags = ['--json']
  if (args && args.fix) flags.push('--fix')
  if (args && args.smoke) flags.push('--smoke')
  const r = await run(ctx, NODE, [doctor, ...flags], {}, exec.signal)
  const parsed = r.ok ? tryJson(r.stdout) : null
  return parsed
    ? { ok: true, summary: parsed.summary, checks: parsed.checks.map((c) => ({ id: c.id, status: c.status, message: c.message, fixResult: c.fixResult || null })) }
    : { ok: false, error: r.error || r.stderr || 'doctor failed', raw: (r.stdout || '').slice(0, 2000) }
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
    async execute(args, exec) {
      exec.signal.throwIfAborted()
      return normalizeToolOutput(await runFn(args, exec))
    },
  }
}

export function apply(ctx) {
  ctx.tools.register(tool('dsh_status', 'Inspect DSH dev state: source-tree branch/commit/dirty, runtime version, patch file, and import-compatibility summary.', { type: 'object', properties: {} }, (args, exec) => toolStatus(ctx, args, exec)))
  ctx.tools.register(tool('dsh_doctor', 'Health-check + targeted repair for the DSH install (shell/core/patches/config YAML/plugin links/duplicate registrations/banned plugins/git/vendor/shell process). fix=true repairs known issues; smoke=true adds an isolated boot test.', { type: 'object', properties: { fix: { type: 'boolean' }, smoke: { type: 'boolean' } } }, (args, exec) => toolDoctor(ctx, args, exec)))
  ctx.tools.register(tool('dsh_patch', 'Manage local patches (list/apply/rollback) from $DSH_HOME/tools/dsh-updater/patches.json. Backup before change, idempotent.', { type: 'object', properties: { action: { type: 'string', enum: ['list', 'apply', 'rollback'] } }, required: ['action'] }, (args, exec) => (args && args.action === 'rollback') ? toolPatchRollback(args, exec) : toolPatch(args, exec)))
  ctx.tools.register(tool('dsh_build', 'Build staging runtime (<runtimeDir>.new) from the source tree. Does NOT touch the running app.', { type: 'object', properties: {} }, (args, exec) => toolBuild(ctx, args, exec)))
  ctx.tools.register(tool('dsh_upgrade', 'Check upstream tags. The legacy apply action is retired and returns migration guidance.', { type: 'object', properties: { action: { type: 'string', enum: ['check', 'apply'] }, version: { type: 'string' } }, required: ['action'] }, (args, exec) => (args && args.action === 'apply') ? toolUpgradeApply(args, exec) : toolUpgradeCheck(ctx, args, exec)))
}
