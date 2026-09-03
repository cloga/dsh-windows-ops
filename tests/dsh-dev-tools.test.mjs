import assert from 'node:assert/strict'
import { execFileSync } from 'node:child_process'
import { existsSync } from 'node:fs'
import { mkdir, readFile, rm, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import path from 'node:path'
import { after, test } from 'node:test'
import { fileURLToPath, pathToFileURL } from 'node:url'

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const pluginRoot = path.join(repoRoot, 'tools', 'dsh-dev-tools')
const sandbox = await import('node:fs/promises').then(({ mkdtemp }) => mkdtemp(path.join(tmpdir(), 'dsh-dev-tools-')))
const home = path.join(sandbox, 'home')
const sourceTree = path.join(sandbox, 'source')
const runtime = path.join(sandbox, 'runtime')
const updater = path.join(home, 'tools', 'dsh-updater')
const insideFile = path.join(sourceTree, 'inside.txt')
const outsideFile = path.join(sandbox, 'outside.txt')
const patchesFile = path.join(updater, 'patches.json')
await mkdir(updater, { recursive: true })
await mkdir(runtime, { recursive: true })
await mkdir(sourceTree, { recursive: true })
await writeFile(path.join(runtime, 'package.json'), JSON.stringify({ version: '0.1.2-rc.1' }))
await writeFile(path.join(sourceTree, 'package.json'), JSON.stringify({ version: '0.1.2-rc.1' }))
await writeFile(insideFile, 'before')
await writeFile(outsideFile, 'outside')
await writeFile(path.join(home, 'tools', 'dsh-compat-check.mjs'), '')
await writeFile(path.join(home, 'tools', 'dsh-doctor.mjs'), '')

const previousEnv = {
  DSH_HOME: process.env.DSH_HOME,
  DSH_SOURCE_TREE: process.env.DSH_SOURCE_TREE,
  DSH_RUNTIME_DIR: process.env.DSH_RUNTIME_DIR,
  DSH_NODE_BIN: process.env.DSH_NODE_BIN,
}
process.env.DSH_HOME = home
process.env.DSH_SOURCE_TREE = sourceTree
process.env.DSH_RUNTIME_DIR = runtime
process.env.DSH_NODE_BIN = process.execPath

const spawnSpecs = []
const resolutionCalls = []
const quiescence = []

function outputFor(argv) {
  const joined = argv.join(' ')
  if (joined.includes('dsh-compat-check.mjs')) return JSON.stringify({ summary: { ok: true }, limitations: [] })
  if (joined.includes('dsh-doctor.mjs')) return JSON.stringify({ summary: { ok: true }, checks: [{ id: 'runtime', status: 'pass', message: 'ready' }] })
  if (joined.includes('rev-parse --abbrev-ref HEAD')) return 'main'
  if (joined.includes('rev-parse --short HEAD')) return 'abc1234'
  return ''
}

const subprocess = {
  async resolveExecutable(command, env, signal) {
    signal?.throwIfAborted()
    resolutionCalls.push({ command, env, signal })
    return command
  },
  spawn(spec) {
    spawnSpecs.push(spec)
    const smoke = spec.argv.includes('--smoke')
    const stdout = smoke ? '' : outputFor(spec.argv)
    let done
    if (smoke) {
      done = new Promise((resolve) => {
        spec.signal.addEventListener('abort', () => {
          quiescence.push('leader-exited')
          resolve({ exitCode: null, signal: 'SIGTERM' })
        }, { once: true })
      })
    } else {
      done = Promise.resolve({ exitCode: 0, signal: null })
    }
    return {
      pid: spawnSpecs.length,
      stdin: undefined,
      stdout: undefined,
      stderr: undefined,
      collected: {
        stdout: { readFrom: () => ({ text: stdout, nextOffset: Buffer.byteLength(stdout), lossy: false }) },
        stderr: { readFrom: () => ({ text: '', nextOffset: 0, lossy: false }) },
      },
      done,
      terminate() {},
      async waitForExit() {
        if (smoke) {
          quiescence.push('wait-descendant')
          await new Promise((resolve) => setTimeout(resolve, 25))
          quiescence.push('descendant-exited')
        }
        return true
      },
    }
  },
}

const plugin = await import(`${pathToFileURL(path.join(pluginRoot, 'index.js')).href}?test=${Date.now()}`)
const { snapshotJsonValue } = await import(pathToFileURL(path.join(pluginRoot, 'snapshot-json.js')).href)
const definitions = new Map()
const ctx = {
  subprocess,
  tools: {
    register(definition) {
      assert.ok(!definitions.has(definition.name), `duplicate tool ${definition.name}`)
      definitions.set(definition.name, definition)
      return () => definitions.delete(definition.name)
    },
  },
}
plugin.apply(ctx)

after(async () => {
  for (const [name, value] of Object.entries(previousEnv)) {
    if (value === undefined) delete process.env[name]
    else process.env[name] = value
  }
  await rm(sandbox, { recursive: true, force: true })
})

function execution(signal = new AbortController().signal) {
  return { signal, agent: {}, deferContext() {}, concludeTurn() {} }
}

async function setPatches(patches) {
  await writeFile(patchesFile, JSON.stringify({ patches }))
}

function assertCanonicalJson(value) {
  assert.deepEqual(snapshotJsonValue(value), value)
  assert.deepEqual(JSON.parse(JSON.stringify(value)), value)
}

test('registers five tools directly and declares the required rc1 services', () => {
  assert.deepEqual(plugin.inject, ['tools', 'subprocess'])
  assert.deepEqual([...definitions.keys()].sort(), [
    'dsh_build',
    'dsh_doctor',
    'dsh_patch',
    'dsh_status',
    'dsh_upgrade',
  ])
  for (const definition of definitions.values()) assert.equal(definition.execute.length, 2)
})

test('uses rc1 lossless JSON snapshot semantics and rejects every lossy root', () => {
  const canonical = { nested: [null, true, 'text', 2.5], object: { ok: true } }
  const detached = plugin.normalizeToolOutput(canonical)
  assert.deepEqual(detached, canonical)
  assert.notEqual(detached, canonical)
  const cycle = {}; cycle.self = cycle
  const sparse = []; sparse.length = 1
  for (const value of [undefined, -0, Number.NaN, Number.POSITIVE_INFINITY, new Date(), new Error('x'), Symbol('x'), cycle, sparse, [undefined], { value: undefined }]) {
    assert.equal(snapshotJsonValue(value), undefined)
    assert.throws(() => plugin.normalizeToolOutput(value), /not losslessly JSON-serializable/)
  }
})

test('spawns only through the subprocess service with explicit bounded policy', async () => {
  await setPatches([{ id: 'listed', file: 'inside.txt', find: 'before', replace: 'after' }])
  const status = await definitions.get('dsh_status').execute({}, execution())
  assertCanonicalJson(status)
  assert.ok(spawnSpecs.length >= 4)
  for (const spec of spawnSpecs) {
    assert.ok(Array.isArray(spec.argv) && spec.argv.length > 0)
    assert.equal(typeof spec.cwd, 'string')
    assert.deepEqual(spec.stdio, {
      stdin: 'ignore',
      stdout: { maxBytes: 8 * 1024 * 1024 },
      stderr: { maxBytes: 8 * 1024 * 1024 },
    })
    assert.equal(spec.graceMs, 5_000)
    assert.ok(spec.signal instanceof AbortSignal)
  }
  assert.ok(resolutionCalls.every((call) => call.signal instanceof AbortSignal))
})

test('waits for descendant quiescence before surfacing cancellation', async () => {
  const controller = new AbortController()
  const pending = definitions.get('dsh_doctor').execute({ smoke: true }, execution(controller.signal))
  setTimeout(() => controller.abort(new Error('test cancellation')), 10)
  await assert.rejects(pending, /test cancellation|abort/i)
  assert.deepEqual(quiescence, ['leader-exited', 'wait-descendant', 'descendant-exited'])
})

test('rejects traversal, absolute paths, empty find, and never mutates outside the canonical source tree', async () => {
  await writeFile(insideFile, 'before')
  await writeFile(outsideFile, 'outside')
  await setPatches([
    { id: 'traversal', file: '../outside.txt', find: 'outside', replace: 'changed' },
    { id: 'absolute', file: outsideFile, find: 'outside', replace: 'changed' },
    { id: 'empty', file: 'inside.txt', find: '', replace: 'changed' },
    { id: 'valid', file: 'inside.txt', find: 'before', replace: 'after' },
  ])
  const result = await definitions.get('dsh_patch').execute({ action: 'apply' }, execution())
  assertCanonicalJson(result)
  assert.equal(result.applied, 1)
  assert.equal(await readFile(insideFile, 'utf8'), 'after')
  assert.equal(await readFile(outsideFile, 'utf8'), 'outside')
  if (process.platform === 'win32') {
    assert.equal(plugin.isPathInside(sourceTree.toUpperCase(), insideFile.toLowerCase()), true)
  }
})

test('already-aborted apply and rollback perform zero writes', async () => {
  await writeFile(insideFile, 'before')
  const backup = `${insideFile}.dshpatch-bak`
  await rm(backup, { force: true })
  await setPatches([{ id: 'valid', file: 'inside.txt', find: 'before', replace: 'after' }])
  const applyAbort = new AbortController(); applyAbort.abort(new Error('abort apply'))
  await assert.rejects(definitions.get('dsh_patch').execute({ action: 'apply' }, execution(applyAbort.signal)), /abort apply/)
  assert.equal(await readFile(insideFile, 'utf8'), 'before')
  assert.equal(existsSync(backup), false)

  await writeFile(insideFile, 'modified')
  await writeFile(backup, 'backup')
  const rollbackAbort = new AbortController(); rollbackAbort.abort(new Error('abort rollback'))
  await assert.rejects(definitions.get('dsh_patch').execute({ action: 'rollback' }, execution(rollbackAbort.signal)), /abort rollback/)
  assert.equal(await readFile(insideFile, 'utf8'), 'modified')
})

test('retired upgrade apply returns canonical locked migration guidance', async () => {
  const result = await definitions.get('dsh_upgrade').execute({ action: 'apply', version: '0.1.2-rc.1' }, execution())
  assertCanonicalJson(result)
  assert.equal(result.ok, false)
  assert.equal(result.requestedVersion, '0.1.2-rc.1')
  assert.match(result.reason, /locked installer or the Desktop core manager/)
})

test('exact rc1 source and real Cordis ToolRuntime prove Fiber-owned disposal', async () => {
  const manifest = JSON.parse(await readFile(path.join(pluginRoot, 'package.json'), 'utf8'))
  assert.equal(manifest.version, '0.2.0')
  assert.equal(manifest.engines.node, '^22.19.0 || >=24.0.0')
  assert.equal(manifest.peerDependencies['@deepseek-ai/cordis'], '4.0.2')
  assert.equal(manifest.peerDependencies['@deepseek-ai/dsh-subprocess'], '0.1.2-rc.1')
  assert.equal(manifest.peerDependencies['@deepseek-ai/dsh-tools'], '0.1.2-rc.1')
  assert.ok(manifest.files.includes('snapshot-json.js'))

  const rc1Root = process.env.DSH_RC1_ROOT
    ? path.resolve(process.env.DSH_RC1_ROOT)
    : path.resolve(repoRoot, '..', '.tmp-dsh-rc1')
  const head = execFileSync('git', ['-C', rc1Root, 'rev-parse', 'HEAD'], { encoding: 'utf8' }).trim()
  assert.equal(head, 'a66e4702047846cdaa10c66c9d3df3951f5ea70d')
  for (const [relative, expected] of [
    ['package.json', ['0.1.2-rc.1']],
    ['packages/core/tools/package.json', ['@deepseek-ai/dsh-tools', '0.1.2-rc.1']],
    ['packages/subprocess/subprocess/package.json', ['@deepseek-ai/dsh-subprocess', '0.1.2-rc.1']],
    ['packages/util/values/package.json', ['@deepseek-ai/dsh-util-values', '0.1.2-rc.1']],
  ]) {
    const text = await readFile(path.join(rc1Root, ...relative.split('/')), 'utf8')
    for (const marker of expected) assert.ok(text.includes(marker), `${relative} is missing ${marker}`)
  }
  const subprocessSource = await readFile(path.join(rc1Root, 'packages', 'subprocess', 'subprocess', 'src', 'types.ts'), 'utf8')
  for (const marker of ['argv: readonly string[]', 'stdio: SubprocessStdio', 'graceMs: number', 'signal?: AbortSignal', 'waitForExit(signal?: AbortSignal): Promise<boolean>']) {
    assert.ok(subprocessSource.includes(marker), `rc1 subprocess seam is missing ${marker}`)
  }
  const valuesSource = await readFile(path.join(rc1Root, 'packages', 'util', 'values', 'src', 'index.ts'), 'utf8')
  for (const marker of ['export function snapshotJsonValue', 'Object.is(current, -0)', 'Reflect.ownKeys(current).length !== length + 1']) {
    assert.ok(valuesSource.includes(marker), `rc1 JSON snapshot seam is missing ${marker}`)
  }

  const fixture = path.join(repoRoot, 'tests', 'fixtures', 'dsh-dev-tools-rc1-lifecycle.mjs')
  execFileSync(process.execPath, ['--import', 'tsx/esm', fixture], {
    cwd: rc1Root,
    env: { ...process.env, DSH_RC1_ROOT: rc1Root, DSH_DEV_TOOLS_ROOT: pluginRoot },
    stdio: 'inherit',
  })
})
