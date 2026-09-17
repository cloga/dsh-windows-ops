import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { resolve } from 'node:path'

// Read-only planner: no subprocesses, network, credentials, writes or activation.
export function planUpgrade(args, scope) {
  if (args.length !== 4 || args[0] !== '--tag' || args[2] !== '--commit') {
    throw new Error('Usage: node tools/plan-core-upgrade.mjs --tag dsh-v<version> --commit <40-char official commit>')
  }
  const [, tag, , commit] = args
  if (!/^dsh-v\d+\.\d+\.\d+(?:-[A-Za-z0-9]+(?:[.-][A-Za-z0-9]+)*)?$/.test(tag)) throw new Error('Expected an exact official dsh-v release tag')
  if (!/^[a-f0-9]{40}$/.test(commit)) throw new Error('Expected a full lowercase official commit SHA')
  const expected = ['core', 'copilot', 'cron', 'playwright', 'ops']
  if (scope?.schemaVersion !== 1 || scope.officialRepository !== 'deepseek-ai/deepseek-harness'
    || !Array.isArray(scope.components)
    || scope.components.length !== expected.length
    || expected.some(id => scope.components.filter(item => item?.id === id).length !== 1)
    || scope.components.some(item => !/^cloga\/[a-z0-9-]+$/.test(item?.repository ?? '')
      || !Array.isArray(item.reviewAreas) || item.reviewAreas.length === 0
      || item.reviewAreas.some(area => typeof area !== 'string' || !area.trim()))
    || !Array.isArray(scope.gates) || !scope.gates.includes('official-first-feature-review')
    || !scope.gates.includes('verify-published-artifacts')
    || !Array.isArray(scope.decisionFields) || ['officialTag', 'officialCommit', 'evidence', 'parity', 'decision', 'remainingGap', 'retirementCondition', 'migrationAndRollback', 'acceptanceEvidence'].some(field => !scope.decisionFields.includes(field))
    || JSON.stringify(scope.parityStates) !== JSON.stringify(['complete', 'partial', 'absent', 'unverified'])
    || JSON.stringify(scope.decisions) !== JSON.stringify(['migrate', 'retain-temporarily', 'retire'])
    || scope.safety?.plannerOnly !== true || scope.safety?.installAuthorized !== false
    || scope.safety?.restartAuthorized !== false || scope.safety?.rewriteImmutableReleases !== false) {
    throw new Error('Invalid upgrade inventory or weakened safety contract')
  }
  return {
    schemaVersion: 1,
    kind: 'unexecuted-core-upgrade-plan',
    target: { repository: scope.officialRepository, tag, commit, verified: false },
    warning: 'Target identity is caller supplied; verify tag, commit and official source before qualification. This plan proves no compatibility.',
    gates: scope.gates,
    components: scope.components.map(component => ({ ...component, status: 'not-reviewed', decisions: [] })),
    requiredDecisionFields: scope.decisionFields,
    allowedParityStates: scope.parityStates,
    allowedDecisions: scope.decisions,
    safety: scope.safety,
  }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    const scope = JSON.parse(readFileSync(new URL('../deployments/core-upgrade-scope.json', import.meta.url), 'utf8'))
    console.log(JSON.stringify(planUpgrade(process.argv.slice(2), scope), null, 2))
  } catch (error) {
    console.error(error.message)
    process.exitCode = 2
  }
}
