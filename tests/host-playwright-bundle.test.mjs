import assert from 'node:assert/strict'
import { createHash } from 'node:crypto'
import { readFile } from 'node:fs/promises'
import { test } from 'node:test'

const manifestUrl = new URL('../tools/dsh-playwright-host/package.json', import.meta.url)
const patchUrl = new URL('../tools/dsh-playwright-host/cordis.patch.yml', import.meta.url)
const readmeUrl = new URL('../tools/dsh-playwright-host/README.md', import.meta.url)
const json = async path => JSON.parse(await readFile(new URL(path, import.meta.url), 'utf8'))

test('Host Playwright bundle pins the reviewed MCP and isolated Edge configuration', async () => {
  const manifest = JSON.parse(await readFile(manifestUrl, 'utf8'))
  const patch = await readFile(patchUrl, 'utf8')
  const readme = await readFile(readmeUrl, 'utf8')

  assert.equal(manifest.name, 'dsh-playwright-host')
  assert.equal(manifest.version, '0.1.7')
  assert.equal(manifest.repository.url, 'https://github.com/cloga/dsh-playwright-host.git')
  assert.equal(manifest.repository.commit, 'fdec939b48d14d66d14bef3d8f12ec68411d58fb')
  assert.equal(manifest.dsh.bundle.patch, './cordis.patch.yml')
  assert.deepEqual(manifest.peerDependencies, {
    '@deepseek-ai/dsh-mcp-client': '>=0.1.6-alpha.1 <0.1.7-0',
    '@deepseek-ai/dsh-mcp-resources': '>=0.1.6-alpha.1 <0.1.7-0',
    '@deepseek-ai/dsh-system-prompt': '>=0.1.6-alpha.1 <0.1.7-0',
  })
  // Exact published composition after normalizing repository line endings.
  const expected = `- insert:
    - id: mcp-playwright
      name: '@deepseek-ai/dsh-mcp-client'
      config:
        serverName: playwright
        transport: stdio
        command: npx
        args:
          - '-y'
          - '@playwright/mcp@0.0.80'
          - '--isolated'
          - '--browser'
          - 'msedge'
          - '--caps'
          - 'testing,devtools,vision'
          - '--viewport-size'
          - '1440x900'
        toolCallTimeoutMs: 120000
        failOnStartupError: true
        maxInstructionBytes: 32768
        reconnect:
          enabled: true
          initialDelayMs: 500
          maxDelayMs: 30000
          maxAttempts: 10
`
  assert.equal(patch.replaceAll('\r\n', '\n'), expected)
  assert.match(readme, /Host scope/)
  assert.match(readme, /concurrent Sessions can affect the same browser state/)
  assert.match(readme, /Do not restart or replace a running DSH Host/)
  assert.match(readme, /exact interruption list/)
  assert.match(readme, /if the set changes, ask again/)
})

test('optional releases retain byte identities and lock/catalog coherence without live claims', async () => {
  const lock = await json('../deployments/windows-copilot.lock.json')
  const catalog = await json('../catalog/plugins.json')
  assert.deepEqual(lock.companionSuite.compatibility.core.versions, ['0.1.6-alpha.1'])
  const expected = {
    'dsh-playwright-host': ['0.1.7', 'fdec939b48d14d66d14bef3d8f12ec68411d58fb', 389282244, 566016151, 566016150, 8280, '647c2112f09c9aa9aabfb6fbe3659dad32658a63eeb034a9040736695ca061f3'],
    'dsh-cron': ['0.7.1', '6dae9da71e6c36c58e04f3ca8c10cc5c4790b3bd', 389294372, 566045997, 566046029, 64919, '136ba9d66ba2f2ada87f1ce97dfb21be97474dc76504fc65ae8e01cde60768d0'],
  }
  for (const [name, [version, commit, releaseId, assetId, checksumId, size, sha256]] of Object.entries(expected)) {
    const overlay = lock.profile.optionalOverlays.find(item => item.name === name)
    const entry = catalog.plugins.find(item => item.id === name)
    const artifact = overlay.artifact
    assert.equal(overlay.version, version)
    assert.equal(overlay.resolvedCommit, commit)
    assert.equal(overlay.source, `github:cloga/${name}#v${version}`)
    assert.equal(overlay.profile, 'web')
    assert.equal(overlay.required, false)
    assert.ok(!lock.profile.requiredBundles.includes(name))
    assert.equal(lock.companionSuite.members.find(item => item.name === name).requiredByBaseDeployment, false)
    assert.equal(artifact.releaseId, releaseId)
    assert.equal(artifact.assetId, assetId)
    assert.equal(artifact.size, size)
    assert.equal(artifact.sha256, sha256)
    assert.equal(artifact.checksumManifest.assetId, checksumId)
    assert.equal(artifact.releaseImmutable, true)
    assert.equal(artifact.integrity, `sha512-${Buffer.from(artifact.sha512, 'hex').toString('base64')}`)
    const checksum = Buffer.from(`${sha256}  ${artifact.name}\n`)
    assert.equal(checksum.length, artifact.checksumManifest.size)
    assert.equal(createHash('sha256').update(checksum).digest('hex'), artifact.checksumManifest.sha256)
    assert.equal(entry.source.commit, overlay.sourceCommit)
    assert.equal(entry.source.mergeCommit, commit)
    assert.equal(entry.source.release, version)
    assert.equal(entry.source.pullRequest, overlay.pullRequest)
    for (const field of ['name', 'url', 'sha256', 'sha512', 'integrity', 'size', 'releaseTag', 'releaseImmutable']) {
      assert.equal(entry.artifact[field], artifact[field], `${name}.${field}`)
    }
    assert.equal(entry.artifact.releaseCommit, commit)
    assert.equal(entry.artifact.checksumManifestUrl, artifact.checksumManifest.url)
    assert.equal(entry.artifact.checksumManifestSha256, artifact.checksumManifest.sha256)
    assert.equal(entry.artifact.checksumManifestSize, artifact.checksumManifest.size)
    assert.equal(entry.validation.level, 'L1')
    assert.ok(!entry.validation.evidence.some(item => ['functional-smoke', 'composition-mount', 'import-probe'].includes(item.kind)))
  }
})
