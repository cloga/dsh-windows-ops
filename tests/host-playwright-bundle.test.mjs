import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import { test } from 'node:test'

const manifestUrl = new URL('../tools/dsh-playwright-host/package.json', import.meta.url)
const patchUrl = new URL('../tools/dsh-playwright-host/cordis.patch.yml', import.meta.url)
const readmeUrl = new URL('../tools/dsh-playwright-host/README.md', import.meta.url)

test('Host Playwright bundle pins the reviewed MCP and isolated Edge configuration', async () => {
  const manifest = JSON.parse(await readFile(manifestUrl, 'utf8'))
  const patch = await readFile(patchUrl, 'utf8')
  const readme = await readFile(readmeUrl, 'utf8')

  assert.equal(manifest.name, 'dsh-playwright-host')
  assert.equal(manifest.version, '0.1.2')
  assert.equal(manifest.repository.url, 'https://github.com/cloga/dsh-playwright-host.git')
  assert.equal(manifest.repository.commit, '2cf6edfd52b5a70b3f6af7b1f502c58718a6f5ac')
  assert.equal(manifest.dsh.bundle.patch, './cordis.patch.yml')
  for (const marker of [
    "id: mcp-playwright",
    "name: '@deepseek-ai/dsh-mcp-client'",
    'serverName: playwright',
    'transport: stdio',
    "'@playwright/mcp@0.0.80'",
    "'--isolated'",
    "'--browser'",
    "'msedge'",
    "'testing,devtools,vision'",
    'toolCallTimeoutMs: 120000',
    'failOnStartupError: true',
  ]) assert.match(patch, new RegExp(marker.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')))

  assert.match(readme, /Host scope/)
  assert.match(readme, /concurrent Sessions can affect the same browser state/)
  assert.match(readme, /Do not restart or replace a running DSH Host/)
  assert.match(readme, /exact interruption list/)
  assert.match(readme, /if the set changes, ask again/)
})
