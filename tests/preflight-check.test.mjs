import assert from 'node:assert/strict'
import fs from 'node:fs'
import path from 'node:path'
import test from 'node:test'
import { spawnSync } from 'node:child_process'
import { fileURLToPath, pathToFileURL } from 'node:url'

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const scratchRoot = path.join(root, 'tests', '.preflight-check-scratch')
const tool = path.join(root, 'tools', 'preflight-check.mjs')
const zstd = await import(pathToFileURL(
  path.join(root, 'tools', 'vendor', 'dsh-zstd', 'types', 'zstd.js')
).href)

const cwd = String.raw`C:\fixture\project`
const project = '--C-fixture-project--'

function sessionHeader(id, overrides = {}) {
  return {
    type: 'session',
    version: 0,
    id,
    createdAt: 1,
    cwd,
    delegationDepth: 0,
    ...overrides,
  }
}

async function frame(lines) {
  return zstd.compressZstdFrame(Buffer.from(lines, 'utf8'))
}

async function writeSession(home, dirName, firstFrameLines, extraFiles = {}, projectName = project) {
  const sessionDir = path.join(home, 'sessions', projectName, dirName)
  fs.mkdirSync(sessionDir, { recursive: true })
  const log = await frame(firstFrameLines)
  fs.writeFileSync(path.join(sessionDir, 'session.jsonl.zstd'), log)
  for (const [relative, content] of Object.entries(extraFiles)) {
    const target = path.join(sessionDir, relative)
    fs.mkdirSync(path.dirname(target), { recursive: true })
    fs.writeFileSync(target, content)
  }
  return { sessionDir, log }
}

function makeHome() {
  fs.mkdirSync(scratchRoot, { recursive: true })
  const home = fs.mkdtempSync(path.join(scratchRoot, 'case-'))
  fs.mkdirSync(path.join(home, 'sessions'), { recursive: true })
  return home
}

function run(home, args = [], env = {}) {
  return spawnSync(process.execPath, [tool, ...args], {
    env: { ...process.env, DSH_HOME: home, ...env },
    encoding: 'utf8',
    timeout: 30_000,
  })
}

test('smoke rejects a runtime override outside the locked Desktop-managed entrypoint', () => {
  const home = makeHome()
  const result = run(home, ['--smoke'], {
    DSH_CLI_PATH: path.join(home, 'unreviewed', 'lib', 'bin.js'),
  })

  assert.equal(result.status, 1, output(result))
  assert.match(output(result), /DSH_CLI_PATH does not match the locked Desktop-managed runtime/)
})

test('smoke attests the complete wrapper tree before executing its entrypoint', () => {
  const source = fs.readFileSync(tool, 'utf8')
  for (const marker of [
    'runtimeTreeState(runtimeRoot)',
    'selector.rootPackage.fileCount',
    'selector.rootPackage.totalBytes',
    'selector.rootPackage.treeSha256',
    'selector.rootPackage.manifestSha256',
    'wrapper.reparseEntryCount',
    "new Intl.Collator('en-US'",
  ]) {
    assert.ok(source.includes(marker), `missing complete runtime attestation marker: ${marker}`)
  }
  assert.ok(source.indexOf('runtimeTreeState(runtimeRoot)')
    < source.indexOf("spawn(node, ['--expose-internals'"))
  assert.match(source, /Smoke backend did not terminate after SIGKILL/)
})

function output(result) {
  return `${result.stdout ?? ''}\n${result.stderr ?? ''}`
}

test('recognizes a non-UUID stable session-trinity name', async () => {
  const home = makeHome()
  const id = 'session-trinity-stable-name'
  const header = JSON.stringify(sessionHeader(id))
  await writeSession(home, id, `${header}\n`)

  const result = run(home)

  assert.equal(result.status, 0, output(result))
  assert.match(output(result), /no stray dirs/)
  assert.match(output(result), /1 sessions/)
})

test('inspects an arbitrary stable session directory name', async () => {
  const home = makeHome()
  const id = 'trinity-history-stable'
  const header = JSON.stringify(sessionHeader(id))
  await writeSession(home, id, `${header}\n`)

  const result = run(home)

  assert.equal(result.status, 0, output(result))
  assert.match(output(result), /no stray dirs/)
  assert.match(output(result), /1 sessions/)
})

test('diagnoses and quarantines a session candidate with no log', () => {
  const home = makeHome()
  const id = 'arbitrary-stable-directory'
  const sessionDir = path.join(home, 'sessions', project, id)
  const marker = Buffer.from('preserve missing-log session data', 'utf8')
  fs.mkdirSync(path.join(sessionDir, 'attachments'), { recursive: true })
  fs.writeFileSync(path.join(sessionDir, 'attachments', 'marker.bin'), marker)

  const diagnosis = run(home)

  assert.equal(diagnosis.status, 1, output(diagnosis))
  assert.match(output(diagnosis), /MISSING session\.jsonl\.zstd/)
  assert.ok(fs.existsSync(sessionDir), 'read-only diagnosis moved the session')

  const fixed = run(home, ['--fix'])

  assert.equal(fixed.status, 0, output(fixed))
  assert.equal(fs.existsSync(sessionDir), false)
  const quarantineRoot = path.join(home, 'tools', 'quarantine')
  const markerPath = fs.readdirSync(quarantineRoot, { recursive: true })
    .map(relative => path.join(quarantineRoot, relative))
    .find(candidate => path.basename(candidate) === 'marker.bin')
  assert.ok(markerPath, 'missing-log session directory was not quarantined')
  assert.deepEqual(fs.readFileSync(markerPath), marker)
})

test('treats an explicit backup directory as a stray rather than a session', () => {
  const home = makeHome()
  const strayDir = path.join(home, 'sessions', project, '.move-backups')
  fs.mkdirSync(strayDir, { recursive: true })

  const result = run(home)

  assert.equal(result.status, 1, output(result))
  assert.match(output(result), /stray dirs: 1/)
  assert.doesNotMatch(output(result), /MISSING session\.jsonl\.zstd/)
  assert.ok(fs.existsSync(strayDir), 'read-only diagnosis moved the stray directory')
})

test('rejects malformed and retired session header fields without exposing values', async () => {
  const cases = [
    ['type', header => { header.type = 'event' }],
    ['version', header => { header.version = 1 }],
    ['id', header => { header.id = '' }],
    ['createdAt missing', header => { delete header.createdAt }],
    ['createdAt', header => { header.createdAt = 1.5 }],
    ['delegationDepth missing', header => { delete header.delegationDepth }],
    ['delegationDepth', header => { header.delegationDepth = -1 }],
    ['seedLength', header => { header.seedLength = -1 }],
    ['seedLength fractional', header => { header.seedLength = 1.5 }],
    ['seedLength negative zero', header => { header.seedLength = -0 }],
    ['origin', header => { header.origin = 'root' }],
    ['agentPreset', header => { header.agentPreset = 42 }],
    ['sandboxMode', header => { header.sandboxMode = 'secret-retired-value' }],
    ['approvalPolicy', header => { header.approvalPolicy = 'secret-retired-value' }],
  ]

  for (const [name, mutate] of cases) {
    const home = makeHome()
    const id = `malformed-${name}`
    const header = sessionHeader(id)
    mutate(header)
    const serialized = name === 'seedLength negative zero'
      ? JSON.stringify(header).replace('"seedLength":0', '"seedLength":-0')
      : JSON.stringify(header)
    await writeSession(home, id, `${serialized}\n`)

    const result = run(home)

    assert.equal(result.status, 1, `${name}: ${output(result)}`)
    assert.match(output(result), /valid session header/, name)
    assert.doesNotMatch(output(result), /secret-retired-value/, name)
  }
})

test('rejects a directory that does not equal the encoded header id', async () => {
  const home = makeHome()
  const headerId = 'session~trinity'
  const wrongDirName = headerId
  const marker = Buffer.from('retain encoded-id mismatch data', 'utf8')
  const candidate = await writeSession(
    home,
    wrongDirName,
    `${JSON.stringify(sessionHeader(headerId))}\n`,
    { 'attachments/marker.bin': marker }
  )

  const diagnosis = run(home)

  assert.equal(diagnosis.status, 1, output(diagnosis))
  assert.match(output(diagnosis), /SESSION DIRECTORY vs HEADER mismatch/)
  assert.ok(fs.existsSync(candidate.sessionDir))

  const fixed = run(home, ['--fix'])

  assert.equal(fixed.status, 0, output(fixed))
  assert.equal(fs.existsSync(candidate.sessionDir), false)
  const quarantineRoot = path.join(home, 'tools', 'quarantine')
  const markerPath = fs.readdirSync(quarantineRoot, { recursive: true })
    .map(relative => path.join(quarantineRoot, relative))
    .find(candidatePath => path.basename(candidatePath) === 'marker.bin')
  assert.ok(markerPath, 'encoded-id mismatch directory was not quarantined')
  assert.deepEqual(fs.readFileSync(markerPath), marker)
})

test('accepts the official encoded physical directory for an unsafe header id', async () => {
  const home = makeHome()
  const headerId = 'session/trinity'
  await writeSession(
    home,
    'session~002Ftrinity',
    `${JSON.stringify(sessionHeader(headerId))}\n`
  )

  const result = run(home)

  assert.equal(result.status, 0, output(result))
})

test('giant first frame is diagnosed read-only and the whole session is quarantined byte-identically', async () => {
  const home = makeHome()
  const id = 'session-trinity-giant-frame'
  const header = JSON.stringify(sessionHeader(id))
  const event = JSON.stringify({ type: 'user/message', data: { content: 'fixture event' } })
  const marker = Buffer.from('retain the entire session directory', 'utf8')
  const { sessionDir, log } = await writeSession(
    home,
    id,
    `${header}\n${event}\n`,
    { 'attachments/marker.bin': marker }
  )

  const beforeEntries = fs.readdirSync(sessionDir, { recursive: true }).sort()
  const diagnosis = run(home)

  assert.equal(diagnosis.status, 1, output(diagnosis))
  assert.match(output(diagnosis), /first Zstandard frame is not exactly one nonempty newline-terminated JSON header/)
  assert.doesNotMatch(output(diagnosis), /fixture event|user\/message/)
  assert.ok(fs.existsSync(sessionDir), 'read-only diagnosis moved the session')
  assert.deepEqual(fs.readdirSync(sessionDir, { recursive: true }).sort(), beforeEntries)
  assert.deepEqual(fs.readFileSync(path.join(sessionDir, 'session.jsonl.zstd')), log)
  assert.equal(fs.existsSync(path.join(home, 'tools', 'quarantine')), false)

  const fixed = run(home, ['--fix'])

  assert.equal(fixed.status, 0, output(fixed))
  assert.equal(fs.existsSync(sessionDir), false)
  const quarantineRoot = path.join(home, 'tools', 'quarantine')
  const quarantinedLog = fs.readdirSync(quarantineRoot, { recursive: true })
    .map(relative => path.join(quarantineRoot, relative))
    .find(candidate => path.basename(candidate) === 'session.jsonl.zstd')
  assert.ok(quarantinedLog, 'quarantined session log was not found')
  assert.deepEqual(fs.readFileSync(quarantinedLog), log)
  assert.deepEqual(
    fs.readFileSync(path.join(path.dirname(quarantinedLog), 'attachments', 'marker.bin')),
    marker
  )
})

test('detects the same parsed header id under differently named directories', async () => {
  const home = makeHome()
  const id = 'session-trinity-duplicate'
  const duplicateDirName = 'duplicate-alias'
  const header = JSON.stringify(sessionHeader(id))
  await writeSession(home, id, `${header}\n`)
  const marker = Buffer.from('duplicate session sidecar', 'utf8')
  const duplicate = await writeSession(
    home,
    duplicateDirName,
    `${header}\n`,
    { 'attachments/marker.bin': marker }
  )

  const diagnosis = run(home)

  assert.equal(diagnosis.status, 1, output(diagnosis))
  assert.match(output(diagnosis), /DUPLICATE parsed session id across 2 directories/)
  assert.ok(fs.existsSync(duplicate.sessionDir), 'read-only diagnosis moved the duplicate')

  const fixed = run(home, ['--fix'])

  assert.equal(fixed.status, 0, output(fixed))
  assert.equal(fs.existsSync(duplicate.sessionDir), false)
  assert.ok(fs.existsSync(path.join(home, 'sessions', project, id)))
  const quarantineRoot = path.join(home, 'tools', 'quarantine')
  const quarantinedLog = fs.readdirSync(quarantineRoot, { recursive: true })
    .map(relative => path.join(quarantineRoot, relative))
    .find(candidate => path.basename(candidate) === 'session.jsonl.zstd')
  assert.ok(quarantinedLog, 'duplicate session directory was not quarantined')
  assert.deepEqual(fs.readFileSync(quarantinedLog), duplicate.log)
  assert.deepEqual(
    fs.readFileSync(path.join(path.dirname(quarantinedLog), 'attachments', 'marker.bin')),
    marker
  )
})

test.after(() => {
  fs.rmSync(scratchRoot, { recursive: true, force: true })
})
