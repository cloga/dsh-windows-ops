import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { spawnSync } from 'node:child_process'
import { fileURLToPath } from 'node:url'
import { planUpgrade } from '../tools/plan-core-upgrade.mjs'

const root = new URL('../', import.meta.url)
const scope = JSON.parse(readFileSync(new URL('deployments/core-upgrade-scope.json', root), 'utf8'))
const args = ['--tag', 'dsh-v0.1.6-alpha.2', '--commit', 'ddefc45fbc7f8e46dd73185e68295696d1297887']

test('plans all maintained components without claiming qualification or executing work', () => {
  const before = JSON.stringify(scope)
  const plan = planUpgrade(args, scope)
  assert.equal(plan.kind, 'unexecuted-core-upgrade-plan')
  assert.equal(plan.target.verified, false)
  assert.deepEqual(plan.components.map(item => item.id), ['core', 'copilot', 'cron', 'playwright', 'ops'])
  assert.ok(plan.components.every(item => item.status === 'not-reviewed' && item.decisions.length === 0))
  assert.equal(plan.safety.installAuthorized, false)
  assert.equal(plan.safety.restartAuthorized, false)
  assert.equal(JSON.stringify(scope), before)
})

test('requires exact target references and rejects extra execution flags', () => {
  for (const input of [[], ['--apply'], [...args, '--install'], ['--tag', 'latest', '--commit', args[3]], ['--tag', args[1], '--commit', 'ddefc45']]) {
    assert.throws(() => planUpgrade(input, scope))
  }
})

test('refuses missing review fields, components, official provenance or safety gates', () => {
  const cases = [
    value => { value.components.pop() },
    value => { value.components[0] = value.components[1] },
    value => { value.components[0].reviewAreas = [] },
    value => { value.officialRepository = 'untrusted/repository' },
    value => { value.decisionFields = [] },
    value => { value.gates = [] },
    value => { value.parityStates = ['complete'] },
    value => { value.safety.installAuthorized = true },
    value => { value.safety.restartAuthorized = true },
    value => { value.safety.rewriteImmutableReleases = true },
  ]
  for (const mutate of cases) {
    const input = structuredClone(scope)
    mutate(input)
    assert.throws(() => planUpgrade(args, input))
  }
})

test('entry points consistently discover the same official-first workflow', () => {
  for (const path of ['AGENTS.md', 'README.md', 'README.en.md']) {
    const text = readFileSync(new URL(path, root), 'utf8')
    assert.ok(text.includes('docs/core-upgrade.md'), path)
    assert.ok(text.includes('plan-core-upgrade.mjs'), path)
  }
  const guide = readFileSync(new URL('docs/core-upgrade.md', root), 'utf8')
  for (const key of ['complete / partial / absent / unverified', 'retirement condition', 'rollback', 'immutable releases']) assert.ok(guide.includes(key), key)
})

test('CLI returns a read-only plan from an unrelated cwd and fails invalid input', () => {
  const script = fileURLToPath(new URL('tools/plan-core-upgrade.mjs', root))
  const result = spawnSync(process.execPath, [script, ...args], { cwd: fileURLToPath(new URL('../', root)), encoding: 'utf8' })
  assert.equal(result.status, 0, result.stderr)
  assert.equal(JSON.parse(result.stdout).target.commit, args[3])
  const bad = spawnSync(process.execPath, [script, '--apply'], { encoding: 'utf8' })
  assert.equal(bad.status, 2)
  assert.equal(bad.stdout, '')
})
