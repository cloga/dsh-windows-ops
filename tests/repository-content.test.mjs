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
  'docs/plugins/scheduling.md',
  'docs/windows-replay-tooling.md',
  'docs/improvement-portfolio.md',
  'docs/powershell-5.1-pitfalls.md',
  'tools/README.md',
  'tools/dsh-replay.config.example.json',
  'tools/dsh-replay.patches.json',
  'tools/install-windows-copilot.ps1',
  'tools/install-optional-companion-suite.ps1',
  'tools/DshCopilotBootstrap.psm1',
  'tools/WindowsCopilotDeployment.psm1',
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
  catalog.plugins.find(plugin => plugin.id === 'dsh-playwright-host').source.pullRequest = 999
  writeJson(target, 'catalog/plugins.json', catalog)
  const result = validateRepositoryContent(target)
  assert.match(messages(result), /source commit differs/)
  assert.match(messages(result), /releaseImmutable differs/)
  assert.match(messages(result), /dsh-playwright-host pull request differs/)
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

test('rejects official Desktop runtime byte and selector drift', () => {
  const target = copyFixture()
  const lock = readJson(target, 'deployments/windows-copilot.lock.json')
  lock.components.desktop.runtimeSelectors.push({
    id: 'controlled-fork',
    source: 'controlled-core-receipt',
  })
  lock.components.desktop.installedExecutable.sha256 = '1'.repeat(64)
  lock.components.desktop.installedResources.treeSha256 = '2'.repeat(64)
  lock.components.desktop.runtimeSelectors[0].rootPackage.treeSha256 = '3'.repeat(64)
  lock.acceptance.runtimeSchema.package.entrypointSha256 = '0'.repeat(64)
  writeJson(target, 'deployments/windows-copilot.lock.json', lock)
  const result = validateRepositoryContent(target)
  assert.match(messages(result), /only the official runtime selector/)
  assert.match(messages(result), /installed Desktop executable digest differs/)
  assert.match(messages(result), /installed Desktop resource digest differs/)
  assert.match(messages(result), /complete wrapper digest differs/)
  assert.match(messages(result), /runtime schema entrypoint digest differs/)
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
  fs.writeFileSync(readmePath, fs.readFileSync(readmePath, 'utf8')
    .replaceAll('0.3.0-cloga.15', '0.3.0-cloga.12')
    .replaceAll('4e095196', '00000000'))
  fs.rmSync(path.join(target, 'SECURITY.md'))
  const result = validateRepositoryContent(target)
  assert.match(messages(result), /README\.en\.md does not name/)
  assert.match(messages(result), /missing the locked Copilot source commit/)
  assert.match(messages(result), /SECURITY\.md/)
})

test('rejects private Core paths in active deployment surfaces', () => {
  const target = copyFixture()
  const lock = readJson(target, 'deployments/windows-copilot.lock.json')
  lock.components.core = { source: { repository: 'https://github.com/cloga/deepseek-harness' } }
  writeJson(target, 'deployments/windows-copilot.lock.json', lock)
  const installerPath = path.join(target, 'tools/install-windows-copilot.ps1')
  fs.appendFileSync(installerPath, '\n# HarnessSourceRoot\n')
  const bootstrapPath = path.join(target, 'tools/DshCopilotBootstrap.psm1')
  fs.appendFileSync(bootstrapPath, "\n# owner = 'cloga/deepseek-harness'\n")
  const result = validateRepositoryContent(target)
  assert.match(messages(result), /private Core must not appear/)
  assert.match(messages(result), /retired private Core path: HarnessSourceRoot/)
  assert.match(messages(result), /DshCopilotBootstrap\.psm1 reintroduces retired private Core path/)
})

test('rejects optional suite drift from the catalog', () => {
  const target = copyFixture()
  const suitePath = path.join(target, 'tools/install-optional-companion-suite.ps1')
  fs.writeFileSync(suitePath, fs.readFileSync(suitePath, 'utf8') + "\n$legacyVersion = '0.3.3'\n")
  const result = validateRepositoryContent(target)
  assert.match(messages(result), /optional suite retains retired independent pin/)
})

test('rejects unified companion suite membership and role drift', () => {
  const target = copyFixture()
  const lock = readJson(target, 'deployments/windows-copilot.lock.json')
  lock.companionSuite.members = lock.companionSuite.members.filter(member => member.name !== 'dsh-cron')
  writeJson(target, 'deployments/windows-copilot.lock.json', lock)
  const catalog = readJson(target, 'catalog/plugins.json')
  catalog.suites[0].members.find(member => member.plugin === 'dsh-github-copilot').requiredByBaseDeployment = false
  writeJson(target, 'catalog/plugins.json', catalog)
  const result = validateRepositoryContent(target)
  assert.match(messages(result), /companion suite role differs for dsh-cron/)
  assert.match(messages(result), /catalog companion suite role differs for dsh-github-copilot/)
  assert.match(messages(result), /companion suite must contain exactly three reviewed members/)
})

test.after(() => {
  fs.rmSync(scratchRoot, { recursive: true, force: true })
})
