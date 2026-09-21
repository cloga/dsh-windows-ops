import assert from 'node:assert/strict'
import fs from 'node:fs'
import path from 'node:path'
import test from 'node:test'
import { fileURLToPath } from 'node:url'
import { execFileSync } from 'node:child_process'
import { createHash } from 'node:crypto'
import { tmpdir } from 'node:os'
import { validateRepositoryContent } from '../tools/validate-repository-content.mjs'

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const scratchRoot = path.join(root, 'tests', '.repository-content-scratch')
const formalFixtureRoot = JSON.parse(fs.readFileSync(path.join(root, 'deployments/windows-copilot.lock.json'), 'utf8'))
  .components.desktop.releaseChannel.nativeProvisioning.fixtureRoot.replaceAll('\\', '/')
const fixtureFiles = [
  ...['release.json', 'build-receipt.json', 'capability.json', 'desktop-provisioning.json', 'helper-acceptance.json',
    'acceptance.json', 'initial-desktop-plugin-provisioning-state.json', 'initial-desktop-plugin-receipts.json',
    'initial-package.json', 'initial-packaged-graph.json', 'initial-settings-readonly.json', 'initial-version-menu.json',
    'initial-usage-readonly.json', 'restart-desktop-plugin-provisioning-state.json',
    'restart-desktop-plugin-receipts.json', 'restart-package.json', 'restart-packaged-graph.json',
    'restart-settings-readonly.json', 'restart-version-menu.json', 'restart-usage-readonly.json'].map(name => `${formalFixtureRoot}/${name}`),
  'deployments/windows-copilot.lock.json',
  'catalog/plugins.json',
  'README.md',
  'README.en.md',
  'docs/local-core-desktop-copilot.md',
  'docs/official-desktop-plugin-provisioning-removal.md',
  'docs/plugins/scheduling.md',
  'docs/windows-replay-tooling.md',
  'docs/improvement-portfolio.md',
  'docs/vision-dual-channel.md',
  'docs/powershell-5.1-pitfalls.md',
  'tools/README.md',
  'tools/dsh-replay.config.example.json',
  'tools/dsh-replay.patches.json',
  'tools/install-windows-copilot.ps1',
  'tools/install-optional-companion-suite.ps1',
  'tools/DshCopilotBootstrap.psm1',
  'tools/WindowsCopilotDeployment.psm1',
  'tools/DshOfficialDesktopBuild.psm1',
  'tools/DshOfficialDesktopPluginProvisioning.psm1',
  'tools/DshOfficialDesktopUpdateChannel.psm1',
  'tools/Install-DshOfficialDesktopLocal.psm1',
  'tools/sync-official-desktop-plugin-release.ps1',
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

test('preserves attested release bytes with Git autocrlf enabled and detects the unprotected control', () => {
  const temporary = fs.mkdtempSync(path.join(tmpdir(), 'dsh-release-checkout-'))
  const lock = readJson(root, 'deployments/windows-copilot.lock.json')
  const relative = `${lock.components.desktop.releaseChannel.nativeProvisioning.fixtureRoot.replaceAll('\\', '/')}/release.json`
  const attributeDirectory = path.dirname(path.dirname(relative))
  const attributes = fs.readFileSync(path.join(root, attributeDirectory, '.gitattributes'))
  const bytes = fs.readFileSync(path.join(root, relative))
  const expected = readJson(root, 'deployments/windows-copilot.lock.json').components.desktop.releaseChannel.manifestRawSha256
  const digest = value => createHash('sha256').update(value).digest('hex')
  assert.equal(digest(bytes), expected)
  const env = Object.fromEntries(['PATH', 'Path', 'SystemRoot', 'WINDIR', 'TEMP', 'TMP'].filter(key => process.env[key]).map(key => [key, process.env[key]]))
  Object.assign(env, { GIT_CONFIG_NOSYSTEM: '1', GIT_CONFIG_GLOBAL: process.platform === 'win32' ? 'NUL' : '/dev/null', GIT_CONFIG_COUNT: '0' })
  try {
    for (const protectedBytes of [false, true]) {
      const directory = path.join(temporary, protectedBytes ? 'protected' : 'control')
      const checkout = path.join(temporary, protectedBytes ? 'protected-output' : 'control-output')
      fs.mkdirSync(path.join(directory, path.dirname(relative)), { recursive: true })
      fs.mkdirSync(checkout)
      fs.writeFileSync(path.join(directory, relative), bytes)
      if (protectedBytes) fs.writeFileSync(path.join(directory, attributeDirectory, '.gitattributes'), attributes)
      const git = (...args) => execFileSync('git', ['-c', 'core.autocrlf=true', '-c', 'core.eol=crlf', '-c', 'core.safecrlf=false', '-C', directory, ...args],
        { env, encoding: 'utf8', stdio: 'pipe', timeout: 30_000 })
      git('init', '--quiet')
      git('add', '--', 'tests')
      git('checkout-index', `--prefix=${checkout.replaceAll('\\', '/')}/`, '--', relative)
      const actual = fs.readFileSync(path.join(checkout, relative))
      if (protectedBytes) { assert.deepEqual(actual, bytes); assert.equal(digest(actual), expected) }
      else assert.notEqual(digest(actual), expected)
    }
  } finally {
    fs.rmSync(temporary, { recursive: true, force: true })
  }
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

for (const [name, mutate, expected] of [
  ['source', (desktop) => { desktop.source.commit = '29f1863f5457470bacd12de00e987b8bdd6f4b2f' }, /Desktop fork source commit differs/],
  ['sequence', (desktop) => { desktop.releaseChannel.sequence = 6 }, /Desktop fork release sequence differs/],
  ['installer', (desktop) => { desktop.artifact.sha256 = 'f39c5dba008385614428e89c3e28f85f0d3aeb24cc0f7992ac1c63c3082c717c' }, /Desktop fork installer digest differs/],
  ['build receipt', (desktop) => { desktop.releaseChannel.buildReceipt.sha256 = 'd083232d6ac98736935529c352259f97abe19b45cb522d730b0488b1b7777515' }, /Desktop fork build receipt raw digest differs/],
]) {
  test(`rejects historical cloga.5 Desktop ${name} in the formal .6 baseline`, () => {
    const target = copyFixture()
    const lock = readJson(target, 'deployments/windows-copilot.lock.json')
    mutate(lock.components.desktop)
    writeJson(target, 'deployments/windows-copilot.lock.json', lock)
    assert.match(messages(validateRepositoryContent(target)), expected)
  })
}

test('rejects Desktop runtime byte and selector drift', () => {
  const target = copyFixture()
  const lock = readJson(target, 'deployments/windows-copilot.lock.json')
  lock.components.desktop.runtimeSelectors.push({
    id: 'controlled-fork',
    source: 'controlled-core-receipt',
  })
  lock.components.desktop.installedExecutable.sha256 = '1'.repeat(64)
  if (lock.components.desktop.installedResources) {
    lock.components.desktop.installedResources.treeSha256 = '2'.repeat(64)
  } else {
    lock.components.desktop.installedRuntimeDescriptor.sha256 = '2'.repeat(64)
  }
  if (lock.components.desktop.runtimeSelectors[0].rootPackage) {
    lock.components.desktop.runtimeSelectors[0].rootPackage.treeSha256 = '3'.repeat(64)
    lock.acceptance.runtimeSchema.package.entrypointSha256 = '0'.repeat(64)
  } else {
    lock.components.desktop.runtimeSelectors[0].descriptor.sha256 = '3'.repeat(64)
    lock.acceptance.runtimeSchema.source.releaseTag = 'dsh-v0.1.2'
  }
  writeJson(target, 'deployments/windows-copilot.lock.json', lock)
  const result = validateRepositoryContent(target)
  assert.match(messages(result), /only the reviewed runtime selector/)
  assert.match(messages(result), /installed Desktop .*executable digest differs/)
  if (lock.components.desktop.installedResources) {
    assert.match(messages(result), /installed Desktop resource digest differs/)
    assert.match(messages(result), /complete wrapper digest differs/)
    assert.match(messages(result), /runtime schema entrypoint digest differs/)
  } else {
    assert.match(messages(result), /installed Desktop runtime descriptor digest differs/)
    assert.match(messages(result), /Desktop fork runtime descriptor differs/)
    assert.match(messages(result), /runtime schema Desktop release tag differs/)
  }
})

for (const [label, mutate, expected] of [
  ['missing layout', schema => { delete schema.layout }, /ASAR runtime schema layout is missing/],
  ['legacy wrapper claim', schema => { schema.wrapper = { name: 'deepseek-harness-pkg', version: '0.1.2-alpha.5' } }, /must not claim a legacy physical wrapper/],
  ['descriptor digest', schema => { schema.descriptorSha256 = '0'.repeat(64) }, /ASAR runtime schema descriptor digest differs/],
  ['wrong package version', schema => { schema.package.version = '0.1.5-rc.2' }, /ASAR runtime package metadata differs/],
  ['wrong entrypoint path', schema => { schema.package.entrypoint = 'lib/private-wrapper.js' }, /ASAR runtime package paths differ/],
  ['missing built data record', schema => { schema.requiredBuiltFiles.pop() }, /ASAR runtime built-file data inventory is invalid/],
]) {
  test(`rejects ASAR metadata schema ${label} without implying preset/CLI support`, () => {
    const target = copyFixture(); const lock = readJson(target, 'deployments/windows-copilot.lock.json')
    mutate(lock.acceptance.runtimeSchema); writeJson(target, 'deployments/windows-copilot.lock.json', lock)
    assert.match(messages(validateRepositoryContent(target)), expected)
  })
}

test('rejects plugin policy drift', () => {
  const target = copyFixture()
  const lock = readJson(target, 'deployments/windows-copilot.lock.json')
  lock.profile.pluginPolicy.unmanagedDisposition = 'allow'
  lock.profile.pluginPolicy.targets[0].rules = lock.profile.pluginPolicy.targets[0].rules
    .filter(rule => rule.name !== 'dsh-tauri-worktree')
  writeJson(target, 'deployments/windows-copilot.lock.json', lock)
  const result = validateRepositoryContent(target)
  assert.match(messages(result), /unmanaged plugins must be inventory warnings/)
  assert.match(messages(result), /alpha\.1 plugin denylist size differs/)
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
    .replaceAll('0.4.0-alpha.32', '0.4.0-alpha.17')
    .replaceAll('76d190ae', '00000000'))
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
