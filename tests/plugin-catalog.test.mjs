import assert from 'node:assert/strict'
import { execFileSync, spawnSync } from 'node:child_process'
import fs from 'node:fs'
import path from 'node:path'
import test from 'node:test'
import { fileURLToPath } from 'node:url'

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const validator = path.join(root, 'tools', 'validate-plugin-catalog.mjs')
const sourceCatalog = path.join(root, 'catalog', 'plugins.json')
const sourceSchema = path.join(root, 'catalog', 'schema', 'plugin-catalog.schema.json')
const sourceLock = path.join(root, 'deployments', 'windows-copilot.lock.json')

function read(file) { return JSON.parse(fs.readFileSync(file, 'utf8')) }
function write(file, value) { fs.writeFileSync(file, `${JSON.stringify(value, null, 2)}\n`) }
function pluginById(catalog, id) {
  const plugin = catalog.plugins.find(candidate => candidate.id === id)
  assert.ok(plugin, `missing catalog fixture ${id}`)
  return plugin
}

function fixture(mutate) {
  const scratchRoot = path.join(root, 'tests', '.plugin-catalog-scratch')
  fs.mkdirSync(scratchRoot, { recursive: true })
  const dir = fs.mkdtempSync(path.join(scratchRoot, 'case-'))
  const catalog = read(sourceCatalog)
  const schema = read(sourceSchema)
  const lock = read(sourceLock)
  mutate?.({ catalog, schema, lock })
  const catalogPath = path.join(dir, 'plugins.json')
  const schemaPath = path.join(dir, 'schema.json')
  const lockPath = path.join(dir, 'lock.json')
  write(catalogPath, catalog)
  write(schemaPath, schema)
  write(lockPath, lock)
  return { dir, catalogPath, schemaPath, lockPath }
}

function run(paths) {
  return spawnSync(process.execPath, [validator, `--catalog=${paths.catalogPath}`, `--schema=${paths.schemaPath}`, `--lock=${paths.lockPath}`], {
    cwd: root,
    encoding: 'utf8',
  })
}

test('current catalog validates', () => {
  const output = execFileSync(process.execPath, [validator], { cwd: root, encoding: 'utf8' })
  assert.match(output, /Plugin catalog valid/)
})

test('dsh-dev-tools records rc1 evidence and deployment-owned approval policy', () => {
  const plugin = pluginById(read(sourceCatalog), 'dsh-dev-tools')
  assert.equal(plugin.source.release, '0.2.0')
  assert.equal(plugin.validation.level, 'L2')
  assert.equal(plugin.validation.dshVersion, '0.1.2-rc.1')
  assert.equal(plugin.security.approvalGate, null)
  assert.ok(plugin.security.notes.some(note => /deployment policy/.test(note)))
  assert.ok(plugin.validation.evidence.some(evidence => evidence.path === 'tests/dsh-dev-tools.test.mjs'))
})

test('requires exactly one dsh-github-copilot locked baseline entry', () => {
  for (const mutate of [
    catalog => { catalog.plugins = catalog.plugins.filter(plugin => plugin.id !== 'dsh-github-copilot') },
    catalog => { pluginById(catalog, 'dsh-github-copilot').validation.level = 'L4' },
  ]) {
    const paths = fixture(({ catalog }) => mutate(catalog))
    const result = run(paths)
    assert.equal(result.status, 1)
    assert.match(result.stderr, /exactly one locked baseline entry/)
  }
})

test('enforces the published schema against unknown properties', () => {
  const paths = fixture(({ catalog }) => { catalog.plugins[0].unexpected = true })
  const result = run(paths)
  assert.equal(result.status, 1)
  assert.match(result.stderr, /not allowed by schema/)
})


test('rejects duplicate plugin ids', () => {
  const paths = fixture(({ catalog }) => catalog.plugins.push(structuredClone(catalog.plugins[0])))
  const result = run(paths)
  assert.equal(result.status, 1)
  assert.match(result.stderr, /duplicate id/)
})

test('rejects future verification dates', () => {
  const paths = fixture(({ catalog }) => { pluginById(catalog, 'desktop-touch-mcp').validation.verifiedAt = '2999-01-01' })
  const result = run(paths)
  assert.equal(result.status, 1)
  assert.match(result.stderr, /future date/)
})

test('rejects missing repository evidence paths', () => {
  const paths = fixture(({ catalog }) => {
    pluginById(catalog, 'desktop-touch-mcp').validation.evidence[1] = { kind: 'source-review', description: 'missing', path: 'docs/does-not-exist.md' }
  })
  const result = run(paths)
  assert.equal(result.status, 1)
  assert.match(result.stderr, /does not exist/)
})

test('rejects optional integrations claiming baseline', () => {
  const paths = fixture(({ catalog }) => {
    const plugin = pluginById(catalog, 'desktop-touch-mcp')
    plugin.validation.level = 'baseline'
    plugin.source.commit = catalog.plugins[0].source.commit
    plugin.package = catalog.plugins[0].package
    plugin.source.release = catalog.plugins[0].source.release
    plugin.artifact = structuredClone(catalog.plugins[0].artifact)
    plugin.validation.evidence.push({ kind: 'deployment-lock', description: 'false claim', path: 'deployments/windows-copilot.lock.json' })
    plugin.validation.evidence.push({ kind: 'import-probe', description: 'false claim', path: 'docs/local-core-desktop-copilot.md' })
    plugin.validation.evidence.push({ kind: 'composition-mount', description: 'false claim', path: 'docs/local-core-desktop-copilot.md' })
    plugin.validation.evidence.push({ kind: 'functional-smoke', description: 'false claim', path: 'docs/local-core-desktop-copilot.md' })
  })
  const result = run(paths)
  assert.equal(result.status, 1)
  assert.match(result.stderr, /falsely claims the current locked baseline/)
})

test('rejects deployment lock identity drift', () => {
  const paths = fixture(({ lock }) => { lock.components.copilotIntegration.source.commit = '0'.repeat(40) })
  const result = run(paths)
  assert.equal(result.status, 1)
  assert.match(result.stderr, /does not match deployment lock/)
})

test('rejects companion suite membership and role drift', () => {
  const paths = fixture(({ catalog }) => {
    catalog.suites[0].members = [
      { plugin: 'dsh-github-copilot', requiredByBaseDeployment: false },
      { plugin: 'missing-plugin', requiredByBaseDeployment: false },
    ]
  })
  const result = run(paths)
  assert.equal(result.status, 1)
  assert.match(result.stderr, /references unknown plugin missing-plugin/)
  assert.match(result.stderr, /does not match deployment companionSuite/)
})

test('rejects mutable or mismatched baseline release evidence', () => {
  const paths = fixture(({ catalog }) => {
    const plugin = pluginById(catalog, 'dsh-github-copilot')
    plugin.artifact.releaseImmutable = false
    plugin.artifact.checksumManifestUrl = 'https://github.com/cloga/dsh-github-copilot/releases/download/v0.0.0/SHA256SUMS'
  })
  const result = run(paths)
  assert.equal(result.status, 1)
  assert.match(result.stderr, /releaseImmutable|checksumManifestUrl/)
})

test('rejects malformed release tag suffixes', () => {
  const paths = fixture(({ catalog }) => {
    pluginById(catalog, 'dsh-github-copilot').artifact.releaseTag = 'v0.3.0-cloga.15/extra'
  })
  const result = run(paths)
  assert.equal(result.status, 1)
  assert.match(result.stderr, /releaseTag/)
})

test('rejects recommended entries with unknown high-impact security facts', () => {
  const paths = fixture(({ catalog }) => { catalog.plugins[0].security.approvalGate = null })
  const result = run(paths)
  assert.equal(result.status, 1)
  assert.match(result.stderr, /unknown high-impact security fields/)
})

test('rejects path and URL ambiguity in one evidence record', () => {
  const paths = fixture(({ catalog }) => { pluginById(catalog, 'desktop-touch-mcp').validation.evidence[0].path = 'docs/startup-60s-timeout.md' })
  const result = run(paths)
  assert.equal(result.status, 1)
  assert.match(result.stderr, /exactly one of path or url/)
})

test('rejects an L2 claim without import-probe evidence', () => {
  const paths = fixture(({ catalog }) => { pluginById(catalog, 'desktop-touch-mcp').validation.level = 'L2' })
  const result = run(paths)
  assert.equal(result.status, 1)
  assert.match(result.stderr, /requires successful import-probe evidence/)
})

test.after(() => {
  fs.rmSync(path.join(root, 'tests', '.plugin-catalog-scratch'), { recursive: true, force: true })
})
