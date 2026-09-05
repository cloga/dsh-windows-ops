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
  const legacyVision = catalog.plugins?.find(candidate => candidate.id === 'dsh-vision-any')
  const version = locked?.package?.version
  const artifact = locked?.package?.artifact
  const source = locked?.source

  expect(typeof version === 'string' && version.length > 0, 'deployment lock is missing the Copilot version')
  expect(plugin !== undefined, 'catalog is missing dsh-github-copilot')
  expect(plugin?.source?.repository === source?.repository, 'catalog repository differs from deployment lock')
  expect(plugin?.source?.commit === source?.commit, 'catalog source commit differs from deployment lock')
  expect(plugin?.source?.mergeCommit === source?.mergeCommit, 'catalog merge commit differs from deployment lock')
  expect(plugin?.source?.pullRequest === source?.pullRequest, 'catalog pull request differs from deployment lock')
  expect(plugin?.source?.reviewedHead === source?.reviewedHead, 'catalog reviewed head differs from deployment lock')
  expect(plugin?.source?.release === version, 'catalog release differs from deployment lock')
  for (const field of ['name', 'url', 'sha256', 'size', 'releaseTag', 'releaseCommit', 'releaseImmutable']) {
    expect(plugin?.artifact?.[field] === artifact?.[field], `catalog artifact.${field} differs from deployment lock`)
  }
  expect(plugin?.artifact?.checksumManifestUrl === artifact?.checksumManifest?.url, 'catalog checksum manifest differs from deployment lock')
  expect(plugin?.artifact?.checksumManifestSha256 === artifact?.checksumManifest?.sha256, 'catalog checksum digest differs from deployment lock')
  expect(plugin?.artifact?.checksumManifestSize === artifact?.checksumManifest?.size, 'catalog checksum size differs from deployment lock')
  expect(artifact?.releaseImmutable === true, 'locked Copilot Release must be immutable')
  expect(artifact?.releaseCommit === '473b8aa174eb47a323b026c098b73bf7d716772c', 'locked Copilot Release commit differs')
  expect(artifact?.releaseTag === `v${version}`, 'locked Copilot Release tag differs from package version')
  expect(artifact?.name === `dsh-github-copilot-${version}.tgz`, 'locked Copilot artifact name differs from package version')
  expect(artifact?.url === `https://github.com/cloga/dsh-github-copilot/releases/download/v${version}/${artifact?.name}`, 'locked Copilot artifact URL is not canonical')
  expect(artifact?.checksumManifest?.url === `https://github.com/cloga/dsh-github-copilot/releases/download/v${version}/SHA256SUMS`, 'locked checksum URL is not canonical')
  expect(/^[0-9a-f]{64}$/.test(artifact?.sha256 ?? ''), 'locked Copilot artifact SHA-256 is invalid')
  expect(/^[0-9a-f]{64}$/.test(artifact?.checksumManifest?.sha256 ?? ''), 'locked checksum-manifest SHA-256 is invalid')

  const suite = lock.companionSuite
  const catalogSuite = catalog.suites?.find(candidate => candidate.id === suite?.id)
  const expectedSuiteMembers = [
    ['dsh-github-copilot', true],
    ['dsh-cron', false],
    ['dsh-playwright-host', false],
  ]
  expect(suite?.includeParameter === 'IncludeCompanionSuite', 'companion suite include parameter differs')
  expect(suite?.profile === 'web', 'companion suite profile must be web')
  expect(catalogSuite?.profile === suite?.profile, 'catalog companion suite profile differs from lock')
  for (const [name, requiredByBaseDeployment] of expectedSuiteMembers) {
    const lockedMember = suite?.members?.find(member => member.name === name)
    const catalogMember = catalogSuite?.members?.find(member => member.plugin === name)
    expect(lockedMember?.requiredByBaseDeployment === requiredByBaseDeployment, `companion suite role differs for ${name}`)
    expect(catalogMember?.requiredByBaseDeployment === requiredByBaseDeployment, `catalog companion suite role differs for ${name}`)
    expect(catalog.plugins?.some(candidate => candidate.id === name), `catalog companion suite member is missing: ${name}`)
  }
  expect(suite?.members?.length === expectedSuiteMembers.length, 'companion suite must contain exactly three reviewed members')
  expect(catalogSuite?.members?.length === expectedSuiteMembers.length, 'catalog companion suite must contain exactly three reviewed members')
  expect(suite?.acceptance?.cron?.requiredTools?.includes('cron_list'), 'companion suite cron acceptance is missing')
  expect(suite?.acceptance?.playwright?.requiredTools?.includes('mcp__playwright__browser_snapshot'), 'companion suite Playwright acceptance is missing')
  expect(suite?.acceptance?.playwright?.isolatedBrowser === true, 'companion suite Playwright must require browser isolation')

  const desktop = lock.components?.desktop
  const selectors = desktop?.runtimeSelectors ?? []
  const official = selectors.find(candidate => candidate.id === 'desktop-official')
  expect(desktop?.version === '0.10.3', 'Desktop version must be 0.10.3')
  expect(desktop?.source?.commit === '113dc8f77095e765f4f55e233d8455e7ad9204ae', 'Desktop source commit differs')
  expect(desktop?.artifact?.sha256 === 'ce4328448a948e6df904548455a32b81f9905908f3b8562f8e8fdfdbac3bfb90', 'Desktop setup digest differs')
  expect(desktop?.artifact?.size === 6213496, 'Desktop setup size differs')
  expect(desktop?.installedExecutable?.sha256 === 'd191cb2729f53c4fa889fab62c48af38979812f5560d0bb8f8ad4cadeff8b5df', 'installed Desktop executable digest differs')
  expect(desktop?.installedExecutable?.size === 23059456, 'installed Desktop executable size differs')
  expect(desktop?.installedExecutable?.authenticodeStatus === 'NotSigned', 'installed Desktop signature status differs')
  expect(desktop?.installedResources?.fileCount === 1765, 'installed Desktop resource file count differs')
  expect(desktop?.installedResources?.totalBytes === 13008656, 'installed Desktop resource size differs')
  expect(desktop?.installedResources?.treeSha256 === '29323493802cc7d75fd02a762066d7be8f0da1ac86e1fe1f8f44e2ea15d074ef', 'installed Desktop resource digest differs')
  expect(lock.components?.core === undefined, 'private Core must not appear in the active deployment lock')
  expect(desktop?.defaultRuntimeSelector === 'desktop-official', 'Desktop official runtime must be the default selector')
  expect(selectors.length === 1 && official !== undefined, 'Desktop must expose only the official runtime selector')
  expect(official?.rootPackage?.version === '0.1.2-alpha.5', 'Desktop wrapper version must be 0.1.2-alpha.5')
  expect(official?.rootPackage?.fileCount === 10347, 'Desktop complete wrapper file count differs')
  expect(official?.rootPackage?.totalBytes === 134066533, 'Desktop complete wrapper size differs')
  expect(official?.rootPackage?.treeSha256 === 'b0f32889536e1bce92a6bc032b11a6865e946015b44de5db4397f080e309c86d', 'Desktop complete wrapper digest differs')
  expect(official?.rootPackage?.manifestSha256 === 'bcfbd3f14511fa9470ea748303a8f9c6307121d2741990823089c5677291e8ba', 'Desktop wrapper manifest digest differs')
  expect(official?.rootPackage?.reparseDirectoryCount === 0, 'Desktop complete wrapper must forbid reparse directories')
  expect(official?.package?.version === '0.1.2-rc.1', 'Desktop nested CLI must be 0.1.2-rc.1')
  expect(official?.package?.releaseTag === 'dsh-v0.1.2-rc.1', 'Desktop nested CLI tag differs')
  expect(official?.package?.commit === 'a66e4702047846cdaa10c66c9d3df3951f5ea70d', 'Desktop nested CLI commit differs')
  expect(official?.package?.fileCount === 10, 'Desktop nested CLI file count differs')
  expect(official?.package?.treeSha256 === '4f5b21b9a7f0aee7908e8ebf915903f39cb85b755d6cb2ef200fc0afd6d602ea', 'Desktop nested CLI tree digest differs')
  expect(official?.package?.entrypointSize === 8021, 'Desktop nested CLI entrypoint size differs')
  expect(official?.package?.entrypointSha256 === 'dc23f6c5dd7df8834e3e38bdb9609d77b459834681ae9b7133b417b0c35f3166', 'Desktop nested CLI entrypoint digest differs')
  expect(desktop?.internalPlugins?.length === 8, 'Desktop must lock all eight official Profile links')
  expect(desktop?.internalPlugins?.some(entry => entry.name === 'dsh-tauri-panel-scheduler' && entry.version === '0.6.7'), 'Desktop scheduler Profile link is missing')
  expect(lock.profile?.requiredBundles?.includes('dsh-tauri-panel-scheduler'), 'Desktop scheduler bundle is missing')
  expect(lock.profile?.plugins?.some(entry => entry.name === 'dsh-tauri-panel-scheduler' && entry.source === 'desktop-internal'), 'Desktop scheduler plugin contract is missing')
  const runtimeSchema = lock.acceptance?.runtimeSchema
  expect(runtimeSchema?.scope === 'desktop-official', 'runtime schema must attest the official Desktop runtime')
  expect(runtimeSchema?.root === official?.root, 'runtime schema root differs from the Desktop selector')
  expect(runtimeSchema?.source?.repository === 'github.com/deepseek-ai/deepseek-harness', 'runtime schema source must be upstream')
  expect(runtimeSchema?.source?.commit === official?.package?.commit, 'runtime schema source commit differs from the Desktop selector')
  expect(runtimeSchema?.wrapper?.version === official?.rootPackage?.version, 'runtime schema wrapper differs from the Desktop selector')
  expect(runtimeSchema?.wrapper?.fileCount === official?.rootPackage?.fileCount, 'runtime schema wrapper file count differs from the Desktop selector')
  expect(runtimeSchema?.wrapper?.totalBytes === official?.rootPackage?.totalBytes, 'runtime schema wrapper size differs from the Desktop selector')
  expect(runtimeSchema?.wrapper?.treeSha256 === official?.rootPackage?.treeSha256, 'runtime schema wrapper digest differs from the Desktop selector')
  expect(runtimeSchema?.package?.version === official?.package?.version, 'runtime schema package differs from the Desktop selector')
  expect(runtimeSchema?.package?.entrypointSize === official?.package?.entrypointSize, 'runtime schema entrypoint size differs from the Desktop selector')
  expect(runtimeSchema?.package?.entrypointSha256 === official?.package?.entrypointSha256, 'runtime schema entrypoint digest differs from the Desktop selector')
  expect(runtimeSchema?.requiredBuiltFiles?.length === 3, 'runtime schema must attest the three reviewed official modules')
  expect(!JSON.stringify(lock).includes('cloga/deepseek-harness'), 'active lock reintroduces the private Core repository')

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
  expect(legacyVision?.recommendation === 'historical', 'dsh-vision-any must remain historical rather than an installation recommendation')
  expect(legacyVision?.summary?.includes('superseded'), 'dsh-vision-any catalog entry must explain its native-image replacement')

  const nativeVisionDoc = read('docs/vision-dual-channel.md')
  expect(nativeVisionDoc.includes('@deepseek-ai/dsh-tool-fs'), 'native image guide is missing the official read_image owner')
  expect(nativeVisionDoc.includes('不再推荐安装 `dsh-vision-any`'), 'native image guide does not retire the secondary vision fallback')

  const currentDocs = [
    'README.md',
    'README.en.md',
    'docs/local-core-desktop-copilot.md',
    'docs/windows-replay-tooling.md',
    'docs/improvement-portfolio.md',
    'docs/powershell-5.1-pitfalls.md',
  ]
  for (const file of currentDocs) expect(read(file).includes(version), `${file} does not name the locked Copilot version`)
  for (const file of ['README.md', 'README.en.md', 'docs/local-core-desktop-copilot.md']) {
    const content = read(file)
    expect(content.includes(desktop.version), `${file} does not name the locked Desktop version`)
    expect(content.includes(desktop.source.commit), `${file} is missing the locked Desktop source commit`)
  }
  expect(read('docs/local-core-desktop-copilot.md').includes(artifact.url), 'deployment guide is missing the locked artifact URL')
  expect(read('docs/local-core-desktop-copilot.md').includes(artifact.sha256), 'deployment guide is missing the locked artifact SHA-256')
  expect(read('docs/local-core-desktop-copilot.md').includes(desktop.artifact.sha256), 'deployment guide is missing the locked Desktop artifact SHA-256')
  expect(read('docs/local-core-desktop-copilot.md').includes(desktop.installedExecutable.sha256), 'deployment guide is missing the installed Desktop executable SHA-256')
  expect(read('docs/local-core-desktop-copilot.md').includes(desktop.installedResources.treeSha256), 'deployment guide is missing the installed Desktop resources digest')
  expect(read('docs/local-core-desktop-copilot.md').includes(official.rootPackage.treeSha256), 'deployment guide is missing the complete wrapper digest')
  expect(read('docs/local-core-desktop-copilot.md').includes(official.package.entrypointSha256), 'deployment guide is missing the locked runtime entrypoint SHA-256')
  expect(read('docs/windows-replay-tooling.md').includes(source.commit), 'replay guide is missing the locked source commit')
  expect(read('docs/windows-replay-tooling.md').includes(artifact.sha256), 'replay guide is missing the locked artifact SHA-256')
  const installer = read('tools/install-windows-copilot.ps1')
  const deploymentModule = read('tools/WindowsCopilotDeployment.psm1')
  const bootstrapModule = read('tools/DshCopilotBootstrap.psm1')
  const bootstrap = read('tools/enable-copilot-search-vision.ps1')
  const optionalSuite = read('tools/install-optional-companion-suite.ps1')
  const replay = read('tools/dsh-replay.ps1')
  expect(installer.includes('CopilotIntegrationArtifactPath'), 'installer does not require the locked Copilot Release artifact')
  expect(installer.includes('Test-CopilotIntegrationDeploymentContract'), 'installer does not verify Copilot artifact metadata')
  expect(installer.includes('IncludeCompanionSuite'), 'installer does not expose the unified companion suite flow')
  for (const retired of ['HarnessSourceRoot', 'CoreInstallPrefix', 'controlled-fork']) {
    expect(!installer.includes(retired), `installer reintroduces retired private Core path: ${retired}`)
  }
  for (const [file, content] of [
    ['tools/WindowsCopilotDeployment.psm1', deploymentModule],
    ['tools/DshCopilotBootstrap.psm1', bootstrapModule],
    ['tools/enable-copilot-search-vision.ps1', bootstrap],
  ]) {
    for (const retired of ['controlled-fork', 'cloga/deepseek-harness', 'DSH_CLI_PATH']) {
      expect(!content.includes(retired), `${file} reintroduces retired private Core path: ${retired}`)
    }
  }
  expect(optionalSuite.includes('ManifestPath'), 'optional suite does not accept the authoritative deployment lock')
  expect(optionalSuite.includes('install-windows-copilot.ps1'), 'optional suite does not route through the authoritative installer')
  expect(optionalSuite.includes('IncludeCompanionSuite'), 'optional suite does not select the authoritative companion suite')
  expect(optionalSuite.includes('RemoveCompanionSuite'), 'optional suite does not route optional removal through the main installer')
  for (const retiredPin of ['0.3.3', '0.1.1', 'f5e8df45496523c98874e6f484b886941683f7d6', '86ca74d4fdf89d6aa6036f273eb8acab4adae34f']) {
    expect(!optionalSuite.includes(retiredPin), `optional suite retains retired independent pin: ${retiredPin}`)
  }
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

  const activeDeploymentDocs = [
    'AGENTS.md',
    'README.md',
    'README.en.md',
    'docs/local-core-desktop-copilot.md',
    'docs/windows-replay-tooling.md',
    'tools/README.md',
    'tools/dsh-replay.config.example.json',
    'tools/dsh-replay.patches.json',
  ]
  for (const currentPath of activeDeploymentDocs) {
    const current = read(currentPath)
    for (const retired of [
      'HarnessSourceRoot',
      'CoreInstallPrefix',
      'controlled-fork',
      'cloga/deepseek-harness',
      'dsh-local-core',
      'DSH_CORE_ROOT',
    ]) {
      expect(!current.includes(retired), `${currentPath} reintroduces retired private Core path: ${retired}`)
    }
  }
  for (const currentPath of [
    'docs/local-core-desktop-copilot.md',
    'docs/windows-replay-tooling.md',
    'tools/README.md',
    'tools/dsh-replay.patches.json',
  ]) {
    const current = read(currentPath)
    expect(!current.includes('0.1.2-alpha.4'), `${currentPath} retains stale alpha.4 current-lane prose`)
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
