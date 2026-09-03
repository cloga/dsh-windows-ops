import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'

const defaultRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')

export function validateRepositoryContent(root = defaultRoot) {
  const failures = []
  const read = relative => fs.readFileSync(path.join(root, relative), 'utf8').replaceAll('\r\n', '\n')
  const json = relative => JSON.parse(read(relative))
  const expect = (condition, message) => { if (!condition) failures.push(message) }

  const lock = json('deployments/windows-copilot.lock.json')
  const catalog = json('catalog/plugins.json')
  const locked = lock.components?.copilotIntegration
  const plugin = catalog.plugins?.find(candidate => candidate.id === 'dsh-github-copilot')
  const version = locked?.package?.version
  const artifact = locked?.package?.artifact
  const source = locked?.source

  expect(typeof version === 'string' && version.length > 0, 'deployment lock is missing the Copilot version')
  expect(plugin !== undefined, 'catalog is missing dsh-github-copilot')
  expect(plugin?.source?.repository === source?.repository, 'catalog repository differs from deployment lock')
  expect(plugin?.source?.commit === source?.commit, 'catalog source commit differs from deployment lock')
  expect(plugin?.source?.mergeCommit === source?.mergeCommit, 'catalog merge commit differs from deployment lock')
  expect(plugin?.source?.pullRequest === source?.pullRequest, 'catalog pull request differs from deployment lock')
  expect(plugin?.source?.release === version, 'catalog release differs from deployment lock')
  for (const field of ['name', 'url', 'sha256', 'size', 'releaseTag', 'releaseImmutable']) {
    expect(plugin?.artifact?.[field] === artifact?.[field], `catalog artifact.${field} differs from deployment lock`)
  }
  expect(plugin?.artifact?.checksumManifestUrl === artifact?.checksumManifest?.url, 'catalog checksum manifest differs from deployment lock')
  expect(plugin?.artifact?.checksumManifestSha256 === artifact?.checksumManifest?.sha256, 'catalog checksum digest differs from deployment lock')
  expect(plugin?.artifact?.checksumManifestSize === artifact?.checksumManifest?.size, 'catalog checksum size differs from deployment lock')
  expect(artifact?.releaseImmutable === true, 'locked Copilot Release must be immutable')
  expect(artifact?.releaseTag === `v${version}`, 'locked Copilot Release tag differs from package version')
  expect(artifact?.name === `dsh-github-copilot-${version}.tgz`, 'locked Copilot artifact name differs from package version')
  expect(artifact?.url === `https://github.com/cloga/dsh-github-copilot/releases/download/v${version}/${artifact?.name}`, 'locked Copilot artifact URL is not canonical')
  expect(artifact?.checksumManifest?.url === `https://github.com/cloga/dsh-github-copilot/releases/download/v${version}/SHA256SUMS`, 'locked checksum URL is not canonical')
  expect(/^[0-9a-f]{64}$/.test(artifact?.sha256 ?? ''), 'locked Copilot artifact SHA-256 is invalid')
  expect(/^[0-9a-f]{64}$/.test(artifact?.checksumManifest?.sha256 ?? ''), 'locked checksum-manifest SHA-256 is invalid')

  const official = lock.components?.desktop?.runtimeSelectors?.find(candidate => candidate.id === 'desktop-official')
  expect(official?.rootPackage?.version === '0.1.2-alpha.4', 'Desktop wrapper version must remain 0.1.2-alpha.4')
  expect(official?.package?.version === '0.1.2-rc.1', 'Desktop nested CLI must be 0.1.2-rc.1')
  expect(official?.package?.releaseTag === 'dsh-v0.1.2-rc.1', 'Desktop nested CLI tag differs')
  expect(official?.package?.commit === 'a66e4702047846cdaa10c66c9d3df3951f5ea70d', 'Desktop nested CLI commit differs')
  expect(official?.package?.fileCount === 10, 'Desktop nested CLI file count differs')
  expect(official?.package?.treeSha256 === '4f5b21b9a7f0aee7908e8ebf915903f39cb85b755d6cb2ef200fc0afd6d602ea', 'Desktop nested CLI tree digest differs')

  for (const id of ['dsh-playwright-host', 'dsh-cron']) {
    const overlay = lock.profile?.optionalOverlays?.find(candidate => candidate.name === id)
    const entry = catalog.plugins?.find(candidate => candidate.id === id)
    expect(overlay?.required === false, `${id} must remain optional`)
    expect(entry?.source?.commit === overlay?.sourceCommit, `${id} source commit differs from lock`)
    expect(entry?.source?.mergeCommit === overlay?.resolvedCommit, `${id} resolved commit differs from lock`)
    expect(entry?.source?.pullRequest === overlay?.pullRequest, `${id} pull request differs from lock`)
    expect(entry?.source?.release === overlay?.version, `${id} version differs from lock`)
    for (const field of ['name', 'url', 'sha256', 'size', 'releaseTag', 'releaseImmutable']) {
      expect(entry?.artifact?.[field] === overlay?.artifact?.[field], `${id} artifact.${field} differs from lock`)
    }
    expect(entry?.artifact?.checksumManifestUrl === overlay?.artifact?.checksumManifest?.url, `${id} checksum URL differs from lock`)
    expect(entry?.artifact?.checksumManifestSha256 === overlay?.artifact?.checksumManifest?.sha256, `${id} checksum digest differs from lock`)
    expect(entry?.artifact?.checksumManifestSize === overlay?.artifact?.checksumManifest?.size, `${id} checksum size differs from lock`)
  }
  expect(lock.profile?.legacyCopilotIntegrations?.some(entry => entry.name === 'dsh-web-search-provider'), 'legacy web-search provider inventory is missing')
  expect(lock.acceptance?.composedConfig?.forbiddenActiveEntries?.includes('web-search-provider'), 'legacy web-search provider must remain forbidden active')

  const currentDocs = [
    'README.md',
    'README.en.md',
    'docs/local-core-desktop-copilot.md',
    'docs/windows-replay-tooling.md',
    'docs/improvement-portfolio.md',
    'docs/powershell-5.1-pitfalls.md',
  ]
  for (const file of currentDocs) expect(read(file).includes(version), `${file} does not name the locked Copilot version`)
  expect(read('docs/local-core-desktop-copilot.md').includes(artifact.url), 'deployment guide is missing the locked artifact URL')
  expect(read('docs/local-core-desktop-copilot.md').includes(artifact.sha256), 'deployment guide is missing the locked artifact SHA-256')
  expect(read('docs/windows-replay-tooling.md').includes(source.commit), 'replay guide is missing the locked source commit')
  expect(read('docs/windows-replay-tooling.md').includes(artifact.sha256), 'replay guide is missing the locked artifact SHA-256')
  const installer = read('tools/install-windows-copilot.ps1')
  const bootstrap = read('tools/enable-copilot-search-vision.ps1')
  const replay = read('tools/dsh-replay.ps1')
  expect(installer.includes('CopilotIntegrationArtifactPath'), 'installer does not require the locked Copilot Release artifact')
  expect(installer.includes('Test-CopilotIntegrationDeploymentContract'), 'installer does not verify Copilot artifact metadata')
  expect(bootstrap.includes('Resolve-LockedCopilotPackageSpec'), 'compatibility wrapper does not resolve the locked package spec')
  expect(replay.includes("[ValidateSet('Preflight', 'Inventory', 'SelfCheck'"), 'replay CLI does not expose the documented Inventory action')
  expect(replay.includes("'Inventory' {"), 'replay CLI is missing the Inventory implementation')

  const readme = read('README.md')
  const readmeEn = read('README.en.md')
  expect((readme.match(/^## /gmu) ?? []).length === (readmeEn.match(/^## /gmu) ?? []).length, 'README heading counts differ')
  for (const content of [readme, readmeEn]) {
    for (const required of ['deployments/windows-copilot.lock.json', 'catalog/plugins.json', 'docs/local-core-desktop-copilot.md', 'tools/README.md']) {
      expect(content.includes(required), `README contract is missing ${required}`)
    }
    expect(content.includes(source.commit.slice(0, 8)), 'README contract is missing the locked Copilot source commit')
    expect(content.includes(source.mergeCommit.slice(0, 8)), 'README contract is missing the locked Copilot merge commit')
  }

  for (const currentPath of [
    'docs/local-core-desktop-copilot.md',
    'docs/plugins/scheduling.md',
    'docs/windows-replay-tooling.md',
    'tools/README.md',
    'tools/dsh-replay.patches.json',
  ]) {
    const current = read(currentPath)
    expect(!current.includes('alpha.5'), `${currentPath} retains stale alpha.5 current-lane prose`)
    expect(!current.includes('`.13`'), `${currentPath} retains stale .13 current-lane prose`)
  }

  const fixturePaths = [
    'tests/fixtures/windows-copilot/provider/deployment-baseline.json',
    'tests/fixtures/windows-copilot/global/dsh-github-copilot/deployment-baseline.json',
  ]
  const requiredCapabilities = locked?.package?.deploymentBaseline?.requiredCapabilities ?? []
  for (const fixturePath of fixturePaths) {
    const fixture = json(fixturePath)
    expect(fixture.package?.version === version, `${fixturePath} version differs from deployment lock`)
    expect(JSON.stringify(fixture.capabilities?.map(entry => entry.id)) === JSON.stringify(requiredCapabilities), `${fixturePath} capabilities differ from deployment lock`)
  }
  for (const fixturePath of [
    'tests/fixtures/windows-copilot/provider/package.json',
    'tests/fixtures/windows-copilot/global/dsh-github-copilot/package.json',
  ]) {
    expect(json(fixturePath).version === version, `${fixturePath} version differs from deployment lock`)
  }

  for (const requiredFile of [
    'AGENTS.md',
    'CONTRIBUTING.md',
    'SECURITY.md',
    '.github/PULL_REQUEST_TEMPLATE.md',
    '.github/ISSUE_TEMPLATE/deployment-bug.yml',
  ]) {
    expect(fs.existsSync(path.join(root, requiredFile)), `repository entry point is missing: ${requiredFile}`)
  }

  return { failures, version, requiredCapabilityCount: requiredCapabilities.length }
}

export function formatRepositoryContentResult(result) {
  if (result.failures.length > 0) {
    return [`Repository content validation failed (${result.failures.length}):`, ...result.failures.map(failure => `- ${failure}`)].join('\n')
  }
  return `Repository content valid for dsh-github-copilot ${result.version} (${result.requiredCapabilityCount} locked capabilities).`
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  const result = validateRepositoryContent()
  const message = formatRepositoryContentResult(result)
  if (result.failures.length > 0) {
    console.error(message)
    process.exit(1)
  }
  console.log(message)
}
