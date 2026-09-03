import assert from 'node:assert/strict'
import fs from 'node:fs'
import path from 'node:path'
import test from 'node:test'
import { fileURLToPath } from 'node:url'
import { validateRepositoryContent } from '../tools/validate-repository-content.mjs'

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const scratchRoot = path.join(root, 'tests', '.repository-content-scratch')
const fixtureFiles = [
  'deployments/windows-copilot.lock.json',
  'catalog/plugins.json',
  'README.md',
  'README.en.md',
  'docs/local-core-desktop-copilot.md',
  'docs/windows-replay-tooling.md',
  'docs/improvement-portfolio.md',
  'docs/powershell-5.1-pitfalls.md',
  'tools/install-windows-copilot.ps1',
  'tools/enable-copilot-search-vision.ps1',
  'tools/dsh-replay.ps1',
  'tests/fixtures/windows-copilot/provider/deployment-baseline.json',
  'tests/fixtures/windows-copilot/global/dsh-github-copilot/deployment-baseline.json',
  'tests/fixtures/windows-copilot/provider/package.json',
  'tests/fixtures/windows-copilot/global/dsh-github-copilot/package.json',
  'AGENTS.md',
  'CONTRIBUTING.md',
  'SECURITY.md',
  '.github/PULL_REQUEST_TEMPLATE.md',
  '.github/ISSUE_TEMPLATE/deployment-bug.yml',
]

function copyFixture() {
  fs.mkdirSync(scratchRoot, { recursive: true })
  const target = fs.mkdtempSync(path.join(scratchRoot, 'case-'))
  for (const relative of fixtureFiles) {
    const destination = path.join(target, relative)
    fs.mkdirSync(path.dirname(destination), { recursive: true })
    fs.copyFileSync(path.join(root, relative), destination)
  }
  return target
}

function readJson(target, relative) {
  return JSON.parse(fs.readFileSync(path.join(target, relative), 'utf8'))
}

function writeJson(target, relative, value) {
  fs.writeFileSync(path.join(target, relative), `${JSON.stringify(value, null, 2)}\n`)
}

function messages(result) {
  return result.failures.join('\n')
}

test('current repository content validates', () => {
  assert.deepEqual(validateRepositoryContent(root).failures, [])
})

test('rejects source identity and immutable release drift', () => {
  const target = copyFixture()
  const catalog = readJson(target, 'catalog/plugins.json')
  catalog.plugins[0].source.commit = '0'.repeat(40)
  catalog.plugins[0].artifact.releaseImmutable = false
  writeJson(target, 'catalog/plugins.json', catalog)
  const result = validateRepositoryContent(target)
  assert.match(messages(result), /source commit differs/)
  assert.match(messages(result), /releaseImmutable differs/)
})

test('rejects invalid checksum evidence and canonical URL drift', () => {
  const target = copyFixture()
  const lock = readJson(target, 'deployments/windows-copilot.lock.json')
  lock.components.copilotIntegration.package.artifact.checksumManifest.sha256 = '0'
  lock.components.copilotIntegration.package.artifact.url = 'https://example.test/provider.tgz'
  writeJson(target, 'deployments/windows-copilot.lock.json', lock)
  const result = validateRepositoryContent(target)
  assert.match(messages(result), /artifact URL is not canonical/)
  assert.match(messages(result), /checksum-manifest SHA-256 is invalid/)
})

test('rejects fixture capability and version drift', () => {
  const target = copyFixture()
  const fixturePath = 'tests/fixtures/windows-copilot/provider/deployment-baseline.json'
  const fixture = readJson(target, fixturePath)
  fixture.package.version = '0.0.0'
  fixture.capabilities.reverse()
  writeJson(target, fixturePath, fixture)
  const result = validateRepositoryContent(target)
  assert.match(messages(result), /version differs/)
  assert.match(messages(result), /capabilities differ/)
})

test('rejects stale README versions and missing repository entry points', () => {
  const target = copyFixture()
  const readmePath = path.join(target, 'README.en.md')
  fs.writeFileSync(readmePath, fs.readFileSync(readmePath, 'utf8').replaceAll('0.3.0-cloga.13', '0.3.0-cloga.12'))
  fs.rmSync(path.join(target, 'SECURITY.md'))
  const result = validateRepositoryContent(target)
  assert.match(messages(result), /README\.en\.md does not name/)
  assert.match(messages(result), /SECURITY\.md/)
})

test.after(() => {
  fs.rmSync(scratchRoot, { recursive: true, force: true })
})
