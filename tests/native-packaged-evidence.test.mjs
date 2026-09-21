// All alpha.2 inputs are generated inert copies. No executable/application is launched.
// The existing required CI entry owns these v3 cases too; no workflow list expansion.
import './native-packaged-v3-cases.mjs';
import assert from 'node:assert/strict';
import childProcess from 'node:child_process';
import { syncBuiltinESMExports } from 'node:module';
import { readFileSync, rmSync, symlinkSync, unlinkSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { test } from 'node:test';
import { packagedFixture, packagedV2Fixture, dualPackagedFixture } from './helpers/native-packaged-fixture.mjs';
import { packagedEvidenceFormat, usesCombinedPackagedEvidence, readCombinedPackagedEvidence, readDualPackagedEvidence, verifyFreshOrdinaryPackagedEvidence } from '../tools/native-packaged-evidence.mjs';
import { verifyNativeReleaseEvidence } from '../tools/verify-native-desktop.mjs';
import { verifyFreshSettingsEvidence, validateSourceIdentity } from './native-asar-release-smoke.mjs';
import { captureOpsCaller, expectedCoreSource, invokeCoreFixture } from '../tools/native-core-fixture-caller.mjs';

function forbidChildren(t) {
  const mocks = ['spawn', 'spawnSync', 'execFile', 'execFileSync'].map(name => t.mock.method(childProcess, name, () => { throw new Error('unexpected child'); }));
  syncBuiltinESMExports();
  t.after(() => { for (const mock of mocks) assert.equal(mock.mock.callCount(), 0); t.mock.restoreAll(); syncBuiltinESMExports(); });
}
const verify = f => readCombinedPackagedEvidence(f.lock, f.directory);
const change = (f, file, mutate) => { const value = f.get(file); mutate(value); f.put(file, value); };

test('combined inert graph passes explicit adapter and formal consumer without ordinary acceptance or upgrade promotion', t => {
  forbidChildren(t); const f = packagedFixture(t); const accepted = verify(f);
  assert.equal(accepted.normalAcceptanceCompleted, false); assert.equal(accepted.cleanupVerified, false);
  assert.equal(accepted.installerUpgradeVerified, false);
  assert.equal(verifyNativeReleaseEvidence(f.lock, f.directory).valid, true);
});

for (const [name, mutate] of [
  ['absent descriptor', f => { delete f.lock.components.desktop.releaseChannel.nativeProvisioning.packagedAcceptance; }],
  ['unknown schema', f => { f.lock.components.desktop.releaseChannel.nativeProvisioning.packagedAcceptance.schemaVersion = 2; }],
  ['unknown format', f => { f.lock.components.desktop.releaseChannel.nativeProvisioning.packagedAcceptance.format = 'automatic'; }],
  ['unknown descriptor key', f => { f.lock.components.desktop.releaseChannel.nativeProvisioning.packagedAcceptance.acceptance = true; }],
  ['foreign version', f => { f.lock.components.desktop.releaseChannel.upstreamVersion = '0.1.6-alpha.3'; }],
  ['historical version with combined declaration', f => { f.lock.components.desktop.releaseChannel.upstreamVersion = '0.1.6-alpha.1'; }],
  ['null hosted run', f => { f.lock.components.desktop.releaseChannel.nativeProvisioning.packagedAcceptance.runId = null; }],
  ['ordinary acceptance beside suite', f => f.put('acceptance.json', {})],
]) test(`combined rejects ${name} before any child`, t => {
  forbidChildren(t); const f = packagedFixture(t); mutate(f); assert.throws(() => verify(f), /native-packaged-evidence-invalid/);
});

for (const file of ['packaged-suite.json', 'functional-results.json', 'failure.json', 'observer-cleanup.json',
  'core-qualification/qualification.json', 'core-qualification/workflow-run.json', 'core-qualification/workflow-job.json',
  ...['installer-upgrade', 'baseline', 'candidate', 'candidate-restart', 'profile-cleanup', 'package-acceptance', 'acquisition']
    .map(name => `core-qualification/installed/${name}.json`)]) {
  test(`combined rejects missing ${file}`, t => { forbidChildren(t); const f = packagedFixture(t); unlinkSync(join(f.directory, file)); assert.throws(() => verify(f)); });
  test(`combined rejects changed original ${file}`, t => { forbidChildren(t); const f = packagedFixture(t); writeFileSync(join(f.directory, file), readFileSync(join(f.directory, file), 'utf8') + '\n'); assert.throws(() => verify(f)); });
}

for (const [name, file, mutate] of [
  ['provisional promoted', 'functional-results.json', v => { v.normalAcceptanceCompleted = true; }],
  ['provisional cleanup promoted', 'functional-results.json', v => { v.cleanupVerified = true; }],
  ['functional incomplete', 'functional-results.json', v => { v.functionalAssertionsCompleted = false; }],
  ['source mismatch', 'functional-results.json', v => { v.sourceCommit = 'a'.repeat(40); }],
  ['tree mismatch', 'functional-results.json', v => { v.sourceTree = 'b'.repeat(40); }],
  ['mixed evidence', 'failure.json', v => { v.evidenceId = '11111111-2222-3333-4444-555555555555'; }],
  ['mixed run', 'observer-cleanup.json', v => { v.runId = '456'; }],
  ['mixed attempt', 'packaged-suite.json', v => { v.runAttempt = '1'; }],
  ['raw/canonical plan confusion', 'functional-results.json', v => { v.planSha256 = v.provisioningSha256; }],
  ['metadata/EXE confusion', 'functional-results.json', v => { v.executableSha256 = v.runtimeSha256; }],
  ['wrong failure marker', 'failure.json', v => { v.error = 'ordinary error'; }],
  ['unfinalized failure', 'failure.json', v => { v.cleanupCompleted = false; }],
  ['diagnostic errors', 'failure.json', v => { v.diagnosticErrors = ['failed write']; }],
  ['cleanup errors', 'failure.json', v => { v.cleanupErrors = ['failed removal']; }],
  ['capture error', 'failure.json', v => { v.captureError = 'hidden error'; }],
  ['wrong failure schema', 'failure.json', v => { v.schemaVersion = 1; }],
  ['old observer schema', 'observer-cleanup.json', v => { v.schemaVersion = 2; }],
  ['observer not invoked', 'observer-cleanup.json', v => { v.observerInvokedOnce = false; }],
  ['cleanup not complete', 'observer-cleanup.json', v => { v.ownedLegacySdkRemoved = false; }],
  ['suite ordinary scope', 'packaged-suite.json', v => { v.scope = 'packaged-acceptance'; }],
  ['unknown suite key', 'packaged-suite.json', v => { v.valid = true; }],
  ['live OAuth claim', 'functional-results.json', v => { v.realOAuth = true; }],
  ['model claim', 'functional-results.json', v => { v.realModelRound = true; }],
  ['search claim', 'functional-results.json', v => { v.realSearch = true; }],
  ['live quota claim', 'functional-results.json', v => { v.liveAccountQuota = true; }],
  ['upgrade claim', 'functional-results.json', v => { v.installerUpgradeVerified = true; }],
  ['summary scope confusion', 'core-qualification/qualification.json', v => { v.scope = 'locked-release-ops-observer'; }],
  ['summary unknown field', 'core-qualification/qualification.json', v => { v.valid = true; }],
  ['summary source mismatch', 'core-qualification/qualification.json', v => { v.sourceCommit = 'f'.repeat(40); }],
  ['summary missing installed qualification', 'core-qualification/qualification.json', v => { v.actualInstalledUpgradeVerified = false; }],
  ['cross-version choice overclaim', 'core-qualification/qualification.json', v => { v.limits.choicesAcrossInstallerUpgradeVerified = true; }],
  ['CI unknown input', 'core-qualification/qualification.json', v => { v.inputs.unreviewed = 'a'.repeat(64); }],
  ['unhashed CI-only root', 'core-qualification/qualification.json', v => { v.inputs['upgrade.owner'] = ''; }],
  ['workflow wrong repository', 'core-qualification/workflow-run.json', v => { v.repository.full_name = 'other/repo'; }],
  ['workflow wrong head', 'core-qualification/workflow-run.json', v => { v.head_sha = 'f'.repeat(40); }],
  ['workflow wrong attempt', 'core-qualification/workflow-run.json', v => { v.run_attempt = 1; }],
  ['workflow failure', 'core-qualification/workflow-run.json', v => { v.conclusion = 'failure'; }],
  ['job foreign run', 'core-qualification/workflow-job.json', v => { v.run_id = 456; }],
  ['job failure', 'core-qualification/workflow-job.json', v => { v.conclusion = 'failure'; }],
  ['qualification step skipped', 'core-qualification/workflow-job.json', v => { v.steps[2].conclusion = 'skipped'; }],
  ['qualification duplicate', 'core-qualification/workflow-job.json', v => { v.steps.push(v.steps[2]); }],
]) test(`combined rejects rehashed ${name}`, t => {
  forbidChildren(t); const f = packagedFixture(t); change(f, file, mutate); f.seal(); assert.throws(() => verify(f), /native-/);
});

for (const [name, mutate] of [
  ['wrong receipt filename', f => { const suite = f.get('packaged-suite.json'); suite.receipts.failure.file = '../failure.json'; f.lock.components.desktop.releaseChannel.nativeProvisioning.packagedAcceptance.suiteSha256 = f.put('packaged-suite.json', suite); }],
  ['wrong observer hash', f => { change(f, 'observer-cleanup.json', v => { v.functionalSha256 = '0'.repeat(64); }); const suite = f.get('packaged-suite.json'); suite.receipts.observer.sha256 = f.digest('observer-cleanup.json'); f.lock.components.desktop.releaseChannel.nativeProvisioning.packagedAcceptance.suiteSha256 = f.put('packaged-suite.json', suite); }],
  ['malformed JSON', f => writeFileSync(join(f.directory, 'packaged-suite.json'), '{')],
  ['oversize JSON', f => writeFileSync(join(f.directory, 'packaged-suite.json'), Buffer.alloc(32 * 1024 * 1024 + 1))],
  ['settings string', f => { change(f, 'restart-settings-readonly.json', v => { v.currentWorkspaceReadOnly = 'true'; }); f.lock.components.desktop.releaseChannel.nativeProvisioning.settingsAcceptance.restartSha256 = f.digest('restart-settings-readonly.json'); f.seal(); }],
  ['missing hosted provider', f => { change(f, 'restart-settings-readonly.json', v => { v.registeredSearchProviders = []; }); f.lock.components.desktop.releaseChannel.nativeProvisioning.settingsAcceptance.restartSha256 = f.digest('restart-settings-readonly.json'); f.seal(); }],
  ['native popup claim', f => { change(f, 'restart-version-menu.json', v => { v.nativePopupOpened = true; }); change(f, 'functional-results.json', v => { v.versionMenus[1].nativePopupOpened = true; }); f.seal(); }],
  ['private peer ownership', f => { change(f, 'initial-desktop-plugin-receipts.json', v => { v.owners['dsh-github-copilot'] = 'user'; }); f.seal(); }],
]) test(`combined rejects ${name}`, t => { forbidChildren(t); const f = packagedFixture(t); mutate(f); assert.throws(() => verify(f)); });

test('combined rejects linked qualification directory without following it', t => {
  forbidChildren(t); const f = packagedFixture(t); const other = packagedFixture(t);
  // Junction creation does not require Windows symlink privilege.
  rmSync(join(f.directory, 'core-qualification'), { recursive: true });
  symlinkSync(join(other.directory, 'core-qualification'), join(f.directory, 'core-qualification'), 'junction');
  assert.throws(() => verify(f), /native-reparse-path/); unlinkSync(join(f.directory, 'core-qualification'));
});

test('fresh ordinary alpha2 uses real Ops run and semantic phase menus, not formal window IDs', t => {
  forbidChildren(t); const f = packagedFixture(t); const run = f.ordinary();
  const accepted = verifyFreshOrdinaryPackagedEvidence(f.lock, f.directory, run);
  assert.equal(accepted.normalAcceptanceCompleted, true); assert.equal(accepted.cleanupVerified, true);
  assert.equal(accepted.installerUpgradeVerified, false);
  assert.equal(verifyFreshSettingsEvidence(f.lock, accepted, f.directory), undefined);
});
for (const [name, mutate] of [
  ['missing settings proof', f => { delete f.lock.components.desktop.releaseChannel.nativeProvisioning.settingsAcceptance; }],
  ['missing usage proof', f => { delete f.lock.components.desktop.releaseChannel.nativeProvisioning.usageAcceptance; }],
  ['missing settings digest', f => { delete f.lock.components.desktop.releaseChannel.nativeProvisioning.settingsAcceptance.initialSha256; }],
  ['missing declared menu digest', f => { delete f.lock.components.desktop.releaseChannel.nativeProvisioning.settingsAcceptance.initialVersionMenuSha256; }],
  ['missing usage digest', f => { delete f.lock.components.desktop.releaseChannel.nativeProvisioning.usageAcceptance.restartSha256; }],
  ['wrong source', f => change(f, 'acceptance.json', v => { v.sourceCommit = 'a'.repeat(40); })],
  ['wrong tree', f => change(f, 'acceptance.json', v => { v.sourceTree = 'a'.repeat(40); })],
  ['formal run substituted', f => change(f, 'acceptance.json', v => { v.runId = '123'; })],
  ['wrong Ops attempt', f => change(f, 'acceptance.json', v => { v.runAttempt = '2'; })],
  ['ordinary not complete', f => change(f, 'acceptance.json', v => { v.normalAcceptanceCompleted = false; })],
  ['ordinary cleanup false', f => change(f, 'acceptance.json', v => { v.cleanupVerified = false; })],
  ['provisional identity drift', f => change(f, 'functional-results.json', v => { v.evidenceId = '11111111-2222-3333-4444-555555555555'; })],
  ...['failure.json', 'observer-cleanup.json', 'packaged-suite.json'].map(file => [`unexpected ${file}`, f => f.put(file, {})]),
]) test(`fresh ordinary rejects ${name}`, t => { forbidChildren(t); const f = packagedFixture(t); const run = f.ordinary(); mutate(f); assert.throws(() => verifyFreshOrdinaryPackagedEvidence(f.lock, f.directory, run), /native-/); });

for (const [name, file, mutate] of [
  ['upgrade not succeeded', 'installer-upgrade', v => { v.succeeded = false; }],
  ['upgrade primary failure', 'installer-upgrade', v => { v.failure = 'failed'; }],
  ['upgrade cleanup error', 'installer-upgrade', v => { v.cleanupErrors = ['failed']; }],
  ['upgrade secondary error', 'installer-upgrade', v => { v.secondaryErrors = ['failed']; }],
  ['upgrade foreign source', 'installer-upgrade', v => { v.sourceCommit = 'f'.repeat(40); }],
  ['upgrade binding false', 'installer-upgrade', v => { v.baselineProcessBinding.hashMatches = false; }],
  ['cross-version user choices claim', 'installer-upgrade', v => { v.pluginUserChoicesVerified = true; }],
  ['retained-home mismatch', 'candidate-restart', v => { v.retainedEnvSha256 = '0'.repeat(64); }],
  ['baseline foreign source', 'baseline', v => { v.sourceCommit = 'f'.repeat(40); }],
  ['baseline foreign version', 'baseline', v => { v.version = '0.1.6-foreign'; }],
  ['candidate foreign source', 'candidate', v => { v.sourceCommit = 'f'.repeat(40); }],
  ['candidate foreign version', 'candidate', v => { v.version = '0.1.6-foreign'; }],
  ['candidate foreign runtime', 'candidate', v => { v.runtimeSha256 = '0'.repeat(64); }],
  ['restart foreign executable', 'candidate-restart', v => { v.executableSha256 = '0'.repeat(64); }],
  ['candidate settings not loaded', 'candidate', v => { v.actualHostSettingsViews.currentWorkspaceReadOnly = false; }],
  ['candidate real model claim', 'candidate', v => { v.realModelRound = true; }],
  ['profile cleanup incomplete', 'profile-cleanup', v => { v.ownedHomeRemoved = false; }],
  ['same-version scope relabeled', 'package-acceptance', v => { v.scope = 'cross-version-upgrade'; }],
  ['same-version choice overclaim', 'package-acceptance', v => { v.choicesAcrossInstallerUpgradeVerified = true; }],
  ['package not succeeded', 'package-acceptance', v => { v.succeeded = false; }],
  ['package page error', 'package-acceptance', v => { v.pageErrors = ['failed']; }],
  ['package cleanup error', 'package-acceptance', v => { v.cleanupErrors = ['failed']; }],
  ['package secondary error', 'package-acceptance', v => { v.secondaryErrors = ['failed']; }],
  ['package process still live', 'package-acceptance', v => { v.shellIncarnations[0].exited = false; }],
  ['package no checkpoints', 'package-acceptance', v => { v.checkpoints = []; }],
  ['acquisition mutable', 'acquisition', v => { v.immutable = false; }],
  ['acquisition wrong installer digest', 'acquisition', v => { v.installerSha256 = '0'.repeat(64); }],
  ['acquisition execution claim', 'acquisition', v => { v.installerExecuted = true; }],
]) test(`archived installed graph rejects rehashed ${name}`, t => {
  forbidChildren(t); const f = packagedFixture(t);
  change(f, `core-qualification/installed/${file}.json`, mutate); f.seal(); assert.throws(() => verify(f), /native-packaged-evidence-invalid/);
});
for (const phase of ['baseline', 'candidate', 'candidate-restart']) test(`archived installed graph rejects contradictory ${phase} failure receipt`, t => {
  forbidChildren(t); const f = packagedFixture(t); f.put(`core-qualification/installed/${phase}-failure.json`, {});
  assert.throws(() => verify(f), /native-packaged-evidence-invalid/);
});

const ambient = () => ({ GITHUB_ACTIONS: 'true', GITHUB_REPOSITORY: 'cloga/dsh-windows-ops', GITHUB_SHA: 'a'.repeat(40), GITHUB_RUN_ID: '456', GITHUB_RUN_ATTEMPT: '3', KEEP: 'unchanged' });
const coreFacts = () => ({ commit: 'b'.repeat(40), tree: 'c'.repeat(40), version: '0.1.6-alpha.2.cloga.1',
  upstreamVersion: '0.1.6-alpha.2', executableSha256: 'd'.repeat(64), runtimeSha256: 'e'.repeat(64), planSha256: 'f'.repeat(64) });
function sourceContract() {
  const facts = coreFacts();
  const lock = { components: { desktop: { source: { commit: facts.commit, tree: facts.tree }, version: facts.version,
    releaseChannel: { upstreamVersion: facts.upstreamVersion, build: { planSha256: facts.planSha256 } },
    installedExecutable: { sha256: facts.executableSha256 }, installedRuntimeDescriptor: { sha256: facts.runtimeSha256 } } } };
  const verifiedSource = { sourceRepository: 'cloga/deepseek-harness', sourceCommit: facts.commit,
    sourceTree: facts.tree, version: facts.version, upstreamVersion: facts.upstreamVersion };
  return { facts, lock, verifiedSource };
}
test('explicit seven Core facts come from the source-verified lock, not ambient Ops identity', t => {
  forbidChildren(t); const { facts, lock, verifiedSource } = sourceContract();
  const expected = expectedCoreSource(lock, verifiedSource);
  assert.deepEqual(expected, facts); assert.equal(Object.isFrozen(expected), true);
  assert.notEqual(expected.commit, ambient().GITHUB_SHA);
  lock.components.desktop.source.commit = '0'.repeat(40);
  assert.deepEqual(expected, facts); assert.throws(() => expectedCoreSource(lock, verifiedSource), /caller-invalid/);
});
for (const field of ['sourceRepository', 'sourceCommit', 'sourceTree', 'version', 'upstreamVersion']) {
  test(`source adapter rejects drifted verified ${field}`, t => {
    forbidChildren(t); const { lock, verifiedSource } = sourceContract();
    assert.throws(() => expectedCoreSource(lock, { ...verifiedSource, [field]: 'wrong' }), /caller-invalid/);
  });
}
for (const outcome of ['success', 'import-rejection', 'observer-rejection', 'undefined']) {
  test(`explicit Core invocation preserves all Ops environment during ${outcome}`, async t => {
    forbidChildren(t); const env = Object.freeze(ambient()); const before = { ...env }; const caller = captureOpsCaller(env);
    const marker = outcome === 'undefined' ? undefined : new Error(outcome); let invoked = false;
    const expected = coreFacts();
    const promise = invokeCoreFixture(caller, expected, async received => {
      invoked = true; assert.deepEqual(env, before); assert.deepEqual(received, expected);
      assert.equal(Object.isFrozen(received), true); assert.notEqual(received, expected);
      await Promise.resolve(); assert.deepEqual(env, before);
      if (outcome !== 'success') throw marker;
      return { ...received }; // Independent observed result, as returned by the future Core API.
    }, env);
    if (outcome === 'success') assert.deepEqual(await promise, expected);
    else await promise.then(() => assert.fail('must reject'), error => assert.equal(error, marker));
    assert.equal(invoked, true); assert.deepEqual(env, before);
  });
}
for (const field of ['GITHUB_ACTIONS', 'GITHUB_REPOSITORY', 'GITHUB_SHA', 'GITHUB_RUN_ID', 'GITHUB_RUN_ATTEMPT']) {
  test(`invalid ${field} is rejected before Core import/invocation`, async t => {
    forbidChildren(t); const env = ambient(); const caller = captureOpsCaller(env); env[field] = 'wrong';
    let invoked = false; await assert.rejects(invokeCoreFixture(caller, coreFacts(), () => { invoked = true; }, env), /caller-invalid/);
    assert.equal(invoked, false); assert.equal(env[field], 'wrong');
  });
}
for (const field of Object.keys(coreFacts())) {
  for (const mode of ['missing', 'malformed']) test(`rejects ${mode} Core ${field} before import/invocation`, async t => {
    forbidChildren(t); const env = ambient(); const expected = coreFacts();
    if (mode === 'missing') delete expected[field]; else expected[field] = 'wrong';
    let invoked = false;
    await assert.rejects(invokeCoreFixture(captureOpsCaller(env), expected, () => { invoked = true; }, env), /caller-invalid/);
    assert.equal(invoked, false);
  });
  test(`rejects a returned observed Core ${field} differing from the lock`, async t => {
    forbidChildren(t); const env = ambient();
    await assert.rejects(invokeCoreFixture(captureOpsCaller(env), coreFacts(), async facts => ({ ...facts, [field]: 'wrong' }), env), /caller-invalid/);
  });
}
test('old void API, absent or extra explicit facts fail closed without a fallback', async t => {
  forbidChildren(t); const env = ambient(); const caller = captureOpsCaller(env);
  await assert.rejects(invokeCoreFixture(caller, coreFacts(), async () => undefined, env), /caller-invalid/);
  for (const value of [undefined, null, { ...coreFacts(), caller }]) {
    let invoked = false;
    await assert.rejects(invokeCoreFixture(caller, value, () => { invoked = true; }, env), /caller-invalid/);
    assert.equal(invoked, false);
  }
});
test('missing caller SHA stays absent and cannot invoke Core', async t => {
  forbidChildren(t); const env = ambient(); const caller = captureOpsCaller(env); delete env.GITHUB_SHA;
  let invoked = false; await assert.rejects(invokeCoreFixture(caller, coreFacts(), () => { invoked = true; }, env), /caller-invalid/);
  assert.equal(invoked, false); assert.equal(Object.hasOwn(env, 'GITHUB_SHA'), false);
});
for (const fails of [false, true]) test(`caller drift is detected without environment repair or primary masking (failure=${fails})`, async t => {
  forbidChildren(t); const env = ambient(); const caller = captureOpsCaller(env); const marker = new Error('Core failed');
  const promise = invokeCoreFixture(caller, coreFacts(), async facts => {
    env.GITHUB_SHA = '0'.repeat(40); if (fails) throw marker; return { ...facts };
  }, env);
  await assert.rejects(promise, error => fails ? error === marker : /caller-invalid/.test(error.message));
  assert.equal(env.GITHUB_SHA, '0'.repeat(40));
});

test('fresh identity validation continues to reject a Core checkout that differs from lock', t => {
  forbidChildren(t); const f = packagedFixture(t); const d = f.lock.components.desktop; const build = d.releaseChannel.build;
  const identity = { head: d.source.commit, tree: d.source.tree, dirty: '', lockfileSha256: build.lockfileSha256,
    planSha256: build.planSha256, packageManager: `pnpm@${build.pnpmVersion}`, rootVersion: d.releaseChannel.upstreamVersion,
    desktopVersion: d.releaseChannel.upstreamVersion, nodeVersion: build.nodeVersion };
  assert.equal(validateSourceIdentity(f.lock, d.version, identity).sourceCommit, d.source.commit);
  for (const field of ['head', 'tree', 'dirty']) assert.throws(() => validateSourceIdentity(f.lock, d.version, { ...identity, [field]: 'foreign' }), /checkout-mismatch/);
});

test('default environment keeps the genuine Ops SHA during a thrown undefined', async t => {
  forbidChildren(t);
  const values = ambient(); const saved = Object.fromEntries(Object.keys(values).map(key => [key, process.env[key]]));
  try {
    Object.assign(process.env, values); const caller = captureOpsCaller(); let invoked = false;
    await invokeCoreFixture(caller, coreFacts(), () => {
      invoked = true; assert.equal(process.env.GITHUB_SHA, caller.sourceCommit);
      assert.equal(process.env.GITHUB_RUN_ID, caller.runId); throw undefined;
    }).then(() => assert.fail('must reject'), error => assert.equal(error, undefined));
    assert.equal(invoked, true); assert.equal(process.env.GITHUB_SHA, values.GITHUB_SHA);
  } finally {
    for (const [key, value] of Object.entries(saved)) { if (value === undefined) delete process.env[key]; else process.env[key] = value; }
  }
});

test('historical alpha1 remains explicit ordinary behavior without combined descriptor', () => {
  const lock = JSON.parse(readFileSync(new URL('../deployments/windows-copilot.lock.json', import.meta.url)));
  assert.equal(lock.components.desktop.releaseChannel.upstreamVersion, '0.1.6-alpha.1');
  assert.equal(usesCombinedPackagedEvidence(lock), false);
});

// V2 inputs contain reviewed metadata, not executed Client bytes or a claim of alpha.33/runtime qualification.
test('explicit v2 validates schema2 positive observations through the formal consumer (inert)', t => {
  forbidChildren(t); const f = packagedV2Fixture(t); const accepted = verify(f);
  assert.equal(accepted.schemaVersion, 2); assert.equal(accepted.normalAcceptanceCompleted, false);
  assert.equal(accepted.installerUpgradeVerified, false); assert.equal(accepted.liveAccountQuota, false);
  assert.deepEqual(accepted.positiveCopilotUsage.map(value => value.provider), ['github-copilot', 'github-copilot-preview']);
  assert.ok(accepted.positiveCopilotUsage.every(value => Object.keys(value).length === 21));
  assert.equal(verifyNativeReleaseEvidence(f.lock, f.directory).valid, true);
});
test('fresh v2 ordinary keeps its own run and text bytes, not formal byte equality (inert)', t => {
  forbidChildren(t); const f = packagedV2Fixture(t); const originalPositiveDigest = f.digest('positive-usage.json');
  const run = f.ordinary();
  for (const file of ['functional-results.json', 'acceptance.json']) change(f, file, v => {
    v.positiveCopilotUsage[0].usageText = 'Credits: 7 used · 13 left';
  });
  change(f, 'positive-usage.json', v => { v.cases[0].usageText = 'Credits: 7 used · 13 left'; });
  assert.notEqual(f.digest('positive-usage.json'), originalPositiveDigest);
  const accepted = verifyFreshOrdinaryPackagedEvidence(f.lock, f.directory, run);
  assert.equal(accepted.schemaVersion, 2); assert.equal(accepted.normalAcceptanceCompleted, true);
  assert.equal(accepted.runId, '456'); assert.equal(accepted.runAttempt, '3');
  assert.equal(accepted.installerUpgradeVerified, false);
});
test('positive filename cannot implicitly select v2 for a v1 receipt (inert)', t => {
  forbidChildren(t); const f = packagedFixture(t); f.put('positive-usage.json', {});
  assert.equal(verify(f).schemaVersion, 1); assert.equal(verify(f).positiveCopilotUsage, undefined);
});
for (const [name, mutate] of [
  ['v2 format without v2 functional schema', f => { change(f, 'functional-results.json', v => { v.schemaVersion = 1; }); f.seal(); }],
  ['v1 format with v2 functional schema', f => { f.lock.components.desktop.releaseChannel.nativeProvisioning.packagedAcceptance.format = 'combined-suite-v1'; }],
  ['unknown v3 format', f => { f.lock.components.desktop.releaseChannel.nativeProvisioning.packagedAcceptance.format = 'combined-suite-v3'; }],
  ['missing functional positive array', f => { change(f, 'functional-results.json', v => { delete v.positiveCopilotUsage; }); f.seal(); }],
  ['missing functional transport', f => { change(f, 'functional-results.json', v => { delete v.positiveUsageHostTransport; }); f.seal(); }],
  ['functional Host transport claim', f => { change(f, 'functional-results.json', v => { v.positiveUsageHostTransport = 'live'; }); f.seal(); }],
  ['missing positive file', f => unlinkSync(join(f.directory, 'positive-usage.json'))],
  ['changed original positive bytes', f => writeFileSync(join(f.directory, 'positive-usage.json'), readFileSync(join(f.directory, 'positive-usage.json'), 'utf8') + '\n')],
  ['oversized positive bytes', f => writeFileSync(join(f.directory, 'positive-usage.json'), Buffer.alloc(64 * 1024 + 1))],
  ['missing summary positive input', f => { const summary = f.get('core-qualification/qualification.json'); delete summary.inputs['packaged.positiveUsage']; f.lock.components.desktop.releaseChannel.nativeProvisioning.packagedAcceptance.qualificationSha256 = f.put('core-qualification/qualification.json', summary); }],
  ['wrong summary positive digest', f => { const summary = f.get('core-qualification/qualification.json'); summary.inputs['packaged.positiveUsage'] = '0'.repeat(64); f.lock.components.desktop.releaseChannel.nativeProvisioning.packagedAcceptance.qualificationSha256 = f.put('core-qualification/qualification.json', summary); }],
  ['forged declared Client override', f => { f.lock.components.desktop.releaseChannel.nativeProvisioning.packagedAcceptance.expectedClientSha256 = '0'.repeat(64); }],
  ['missing archived installed evidence', f => unlinkSync(join(f.directory, 'core-qualification/installed/installer-upgrade.json'))],
]) test(`v2 rejects ${name}`, t => { forbidChildren(t); const f = packagedV2Fixture(t); mutate(f); assert.throws(() => verify(f)); });
for (const [name, mutate] of [
  ['unknown positive key', v => { v.extra = true; }],
  ['wrong runtime', v => { v.runtimeSha256 = '0'.repeat(64); }],
  ['arbitrary valid Client digest', v => { v.installedClientSha256 = 'a'.repeat(64); }],
  ['uppercase Client digest', v => { v.installedClientSha256 = v.installedClientSha256.toUpperCase(); }],
  ['self-authorized Client digest', v => { v.expectedClientSha256 = v.installedClientSha256 = 'a'.repeat(64); }],
  ['original application not restored', v => { v.originalSignedOutApplicationRestored = false; }],
  ['string restoration flag', v => { v.originalSignedOutApplicationRestored = 'true'; }],
  ['provided Host transport', v => { v.hostTransport = 'provided'; }],
  ['source version drift', v => { v.pluginSource.version = '0.4.0-alpha.34'; }],
  ['source commit drift', v => { v.pluginSource.targetCommit = 'f'.repeat(40); }],
  ['source tar digest drift', v => { v.pluginSource.sha256 = 'f'.repeat(64); }],
  ['source asset drift', v => { v.pluginSource.assetId++; }],
  ['source registry drift', v => { v.pluginSource.dependencyRegistry = 'https://registry.npmjs.org/'; }],
  ['source checksum drift', v => { v.pluginSource.checksumManifest.sha256 = 'f'.repeat(64); }],
  ['source unknown field', v => { v.pluginSource.expectedClientSha256 = v.installedClientSha256; }],
  ...['runtimeSha256', 'installedClientSha256', 'pluginSource', 'cases', 'originalSignedOutApplicationRestored', 'hostTransport'].map(key => [`missing ${key}`, v => { delete v[key]; }]),
]) test(`v2 rejects rehashed ${name}`, t => {
  forbidChildren(t); const f = packagedV2Fixture(t); change(f, 'positive-usage.json', mutate); f.seal();
  assert.throws(() => verify(f), /native-packaged-evidence-invalid/);
});
const positiveBoolKeys = ['sessionSubscribed', 'removedSessionHidesUsage', 'otherProviderHidesUsage', 'clientDisposalRemovesUsage',
  'applicationMountPreserved', 'syntheticSiblingPreserved', 'inheritedSessionScopeVerified', 'explicitUndefinedSessionScopeAbsent',
  'removedSessionRestoresUsage', 'closedSessionHidesUsage', 'closedSessionRestoresUsage', 'restoredProviderShowsUsage', 'subscriptionsReleased', 'syntheticContextDisposed'];
const mutateBothCases = (f, mutate) => {
  const record = f.get('positive-usage.json'); mutate(record.cases); f.put('positive-usage.json', record);
  change(f, 'functional-results.json', value => { value.positiveCopilotUsage = record.cases; });
};
for (const [name, mutate] of [
  ['one route only', cases => cases.pop()], ['extra route', cases => cases.push(cases[0])], ['route order', cases => cases.reverse()],
  ['duplicate provider', cases => { cases[1].provider = cases[0].provider; }],
  ['unknown case field', cases => { cases[0].surprise = true; }],
  ['wrong scope', cases => { cases[1].scope = 'live-quota'; }],
  ['wrong case transport', cases => { cases[1].hostTransport = 'provided'; }],
  ['selector error', cases => { cases[0].selectorErrors = 1; }],
  ['remote call', cases => { cases[1].forbiddenRemoteCalls = 1; }],
  ...[2, 3, 5, '4', false].map(count => [`quotaReads=${JSON.stringify(count)}`, cases => { cases[0].quotaReads = count; }]),
  ...['17 used13 left', '0.7 used13 left', '7 used113 left', '7 used0.13 left', '7 used13 leftover', '7 used', '13 left', '7 used13 left' + 'x'.repeat(257)]
    .map(text => [`wrong usage text ${text.slice(0, 30)}`, cases => { cases[0].usageText = text; }]),
  ...positiveBoolKeys.map((key, index) => [`false ${key}`, cases => { cases[index % 2][key] = false; }]),
  ...positiveBoolKeys.map((key, index) => [`missing ${key}`, cases => { delete cases[index % 2][key]; }]),
  ['string cleanup flag', cases => { cases[1].syntheticContextDisposed = 'true'; }],
]) test(`v2 rejects jointly rehashed case ${name}`, t => {
  forbidChildren(t); const f = packagedV2Fixture(t); mutateBothCases(f, mutate); f.seal();
  assert.throws(() => verify(f), /native-packaged-evidence-invalid/);
});
function deferredTimeline(events, phase, after, count = 1) {
  const rows = structuredClone(events);
  const index = after === 'end' ? rows.length : rows.findIndex(row => row.event === `${phase}:${after}`) + 1;
  rows.splice(index, 0, ...Array.from({ length: count }, () => ({ event: `${phase}:provider-deferred`, milliseconds: 0 })));
  return rows;
}
function resealTimeline(f, events) {
  events.forEach((row, index) => { row.milliseconds = index; });
  change(f, 'functional-results.json', value => { value.timeline = events; });
  change(f, 'failure.json', value => { value.timeline = [...events, { event: 'failure', milliseconds: events.length }]; });
  f.seal(); // Rebind functional/failure -> observer/suite -> summary; rejection must be semantic.
}
for (const selected of [['initial'], ['restart'], ['initial', 'restart']]) {
  test(`v2 permits exactly one deferred event immediately after application for ${selected.join('+')}`, t => {
    forbidChildren(t); const f = packagedV2Fixture(t); let events = f.get('functional-results.json').timeline;
    for (const phase of selected) events = deferredTimeline(events, phase, 'application');
    resealTimeline(f, events); assert.equal(verify(f).schemaVersion, 2);
    const run = f.ordinary(); assert.equal(verifyFreshOrdinaryPackagedEvidence(f.lock, f.directory, run).schemaVersion, 2);
  });
}
test('v1 historical deferred-event filter is preserved unchanged', t => {
  forbidChildren(t); const f = packagedFixture(t);
  resealTimeline(f, deferredTimeline(f.get('functional-results.json').timeline, 'initial', 'end', 2));
  assert.equal(verify(f).schemaVersion, 1);
});
for (const [name, mutate] of [
  ...['initial', 'restart'].flatMap(phase => [
    [`duplicate ${phase} provider-deferred`, events => deferredTimeline(events, phase, 'application', 2)],
    [`${phase} provider-deferred before application`, events => deferredTimeline(events, phase, 'version-menu')],
    [`${phase} provider-deferred after account`, events => deferredTimeline(events, phase, 'account')],
    [`${phase} provider-deferred after timeline`, events => deferredTimeline(events, phase, 'end')],
  ]),
  ['missing positive event', events => events.filter(row => row.event !== 'restart:positive-usage')],
  ['positive in initial phase', events => events.map(row => ({ ...row, event: row.event === 'restart:positive-usage' ? 'initial:positive-usage' : row.event }))],
  ['positive after closed', events => { const rows = [...events]; [rows[rows.length - 1], rows[rows.length - 2]] = [rows[rows.length - 2], rows[rows.length - 1]]; return rows; }],
  ['duplicate positive event', events => [...events, { event: 'restart:positive-usage', milliseconds: events.length }]],
]) test(`v2 rejects strict timeline ${name}`, t => {
  forbidChildren(t); const f = packagedV2Fixture(t);
  resealTimeline(f, mutate(f.get('functional-results.json').timeline));
  assert.throws(() => verify(f), /native-packaged-evidence-invalid/);
  const run = f.ordinary();
  assert.throws(() => verifyFreshOrdinaryPackagedEvidence(f.lock, f.directory, run), /native-packaged-evidence-invalid/);
});
for (const [name, mutate] of [
  ['missing positive file', f => unlinkSync(join(f.directory, 'positive-usage.json'))],
  ['wrong positive source', f => change(f, 'positive-usage.json', v => { v.pluginSource.targetCommit = 'f'.repeat(40); })],
  ['arbitrary Client digest', f => change(f, 'positive-usage.json', v => { v.installedClientSha256 = 'f'.repeat(64); })],
  ['unrestored signed-out app', f => change(f, 'positive-usage.json', v => { v.originalSignedOutApplicationRestored = false; })],
  ['case mismatch', f => change(f, 'positive-usage.json', v => { v.cases[0].usageText = 'Credits: 7 used, 13 left'; })],
  ['schema1 ordinary receipt', f => change(f, 'acceptance.json', v => { v.schemaVersion = 1; })],
  ['wrong fresh run', f => change(f, 'acceptance.json', v => { v.runId = '123'; })],
]) test(`fresh v2 rejects ${name}`, t => {
  forbidChildren(t); const f = packagedV2Fixture(t); const run = f.ordinary(); mutate(f);
  assert.throws(() => verifyFreshOrdinaryPackagedEvidence(f.lock, f.directory, run));
});

const verifyDual = f => readDualPackagedEvidence(f.lock, f.directory);
test('dual original scopes and actual six-field public build projection pass without rewriting bytes (inert)', t => {
  forbidChildren(t); const f = dualPackagedFixture(t);
  const watched = ['acceptance.json', 'functional-results.json', 'positive-usage.json', 'release.json', 'build-receipt.json',
    'canary/functional-results.json', 'canary/failure.json', 'canary/observer-cleanup.json', 'canary/packaged-suite.json',
    'core-qualification/qualification.json', 'core-qualification/workflow-artifacts.json'];
  const before = watched.map(file => f.digest(file));
  assert.equal(packagedEvidenceFormat(f.lock), 'dual-ordinary-canary-v1'); assert.equal(usesCombinedPackagedEvidence(f.lock), false);
  const accepted = verifyDual(f); assert.equal(accepted.normalAcceptanceCompleted, true); assert.equal(accepted.cleanupVerified, true);
  const other = f.get('canary/functional-results.json');
  assert.notEqual(accepted.evidenceId, other.evidenceId); assert.notDeepEqual(accepted.versionMenus, other.versionMenus);
  assert.notDeepEqual(accepted.timeline, other.timeline);
  assert.notEqual(f.get('initial-packaged-graph.json').profile, f.get('canary/initial-packaged-graph.json').profile);
  assert.equal(Object.keys(f.get('core-qualification/qualification.json').inputs).length, 45);
  assert.equal(f.get('release.json').build.runUrl, undefined); assert.equal(f.get('build-receipt.json').buildInputs.attempt, undefined);
  assert.equal(f.lock.components.desktop.releaseChannel.build.attempt, 2);
  const result = verifyNativeReleaseEvidence(f.lock, f.directory);
  assert.equal(result.valid, true); assert.deepEqual(result.formalEvidenceLimits, { archiveBytesVerified: false,
    archiveMembershipVerified: false, unarchivedInstalledRootsReplayed: false, scope: 'pinned-api-and-original-json-consistency' });
  assert.deepEqual(watched.map(file => f.digest(file)), before);
});
test('dual fresh Ops third ordinary run keeps own menus, providers, profiles and real Ops run identity (inert)', t => {
  forbidChildren(t); const f = dualPackagedFixture(t); const fresh = f.fresh();
  const accepted = verifyFreshOrdinaryPackagedEvidence(f.lock, fresh.directory, fresh.run);
  assert.equal(accepted.runId, '456'); assert.equal(accepted.runAttempt, '3');
  assert.notEqual(accepted.evidenceId, f.get('acceptance.json').evidenceId);
  assert.notDeepEqual(accepted.versionMenus, f.get('acceptance.json').versionMenus);
  assert.equal(verifyFreshSettingsEvidence(f.lock, accepted, fresh.directory), undefined);
  assert.throws(() => verifyFreshOrdinaryPackagedEvidence(f.lock, fresh.directory, { runId: '123', runAttempt: '2' }));
});

for (const [name, mutate] of [
  ['missing format', f => { delete f.lock.components.desktop.releaseChannel.nativeProvisioning.packagedAcceptance; }],
  ['unknown format', f => { f.lock.components.desktop.releaseChannel.nativeProvisioning.packagedAcceptance.format = 'dual-v99'; }],
  ['combined declaration cannot reinterpret dual files', f => { f.lock.components.desktop.releaseChannel.nativeProvisioning.packagedAcceptance.format = 'combined-suite-v2'; }],
  ['ordinary pin disagrees with ancestor pin', f => { f.lock.components.desktop.releaseChannel.nativeProvisioning.ancestorIsolation.acceptanceSha256 = '0'.repeat(64); }],
  ['missing original artifacts metadata pin', f => { delete f.lock.components.desktop.releaseChannel.nativeProvisioning.packagedAcceptance.workflowArtifactsSha256; }],
  ['alpha1 quota2 declaration mixed into dual', f => { f.lock.components.desktop.releaseChannel.nativeProvisioning.usagePositiveAcceptance = { schemaVersion: 1 }; }],
  ['primary failure receipt', f => f.put('failure.json', {})],
  ['primary canary suite', f => f.put('packaged-suite.json', {})],
  ['canary ordinary receipt', f => f.put('canary/acceptance.json', f.get('acceptance.json'))],
  ['canary helper copy', f => f.put('canary/helper-acceptance.json', f.get('helper-acceptance.json'))],
  ['canary public metadata copy', f => f.put('canary/desktop-provisioning.json', f.get('desktop-provisioning.json'))],
]) test(`dual rejects ${name}`, t => { forbidChildren(t); const f = dualPackagedFixture(t); mutate(f); assert.throws(() => verifyDual(f)); });
for (const file of ['acceptance.json', 'functional-results.json', 'positive-usage.json', 'helper-acceptance.json',
  'canary/functional-results.json', 'canary/failure.json', 'canary/observer-cleanup.json', 'canary/packaged-suite.json', 'canary/positive-usage.json',
  'core-qualification/qualification.json', 'core-qualification/workflow-run.json', 'core-qualification/workflow-job.json',
  'core-qualification/workflow-artifacts.json', 'core-qualification/installed/installer-upgrade.json']) {
  test(`dual rejects missing original ${file}`, t => { forbidChildren(t); const f = dualPackagedFixture(t); unlinkSync(join(f.directory, file)); assert.throws(() => verifyDual(f)); });
}
for (const file of ['acceptance.json', 'positive-usage.json', 'canary/functional-results.json', 'canary/positive-usage.json', 'core-qualification/workflow-artifacts.json']) {
  test(`dual rejects changed original raw bytes ${file}`, t => {
    forbidChildren(t); const f = dualPackagedFixture(t); writeFileSync(join(f.directory, file), readFileSync(join(f.directory, file), 'utf8') + '\n');
    assert.throws(() => verifyDual(f));
  });
}
for (const [name, file, mutate] of [
  ['primary normal false', 'acceptance.json', v => { v.normalAcceptanceCompleted = false; }],
  ['primary provisional substituted', 'acceptance.json', v => { v.scope = 'packaged-functional-observations'; }],
  ['primary cleanup false', 'acceptance.json', v => { v.cleanupVerified = false; }],
  ['primary old schema', 'acceptance.json', v => { v.schemaVersion = 1; }],
  ['primary UUID family mismatch', 'functional-results.json', v => { v.evidenceId = '33333333-4444-4555-8666-777777777777'; }],
  ['primary source mismatch', 'acceptance.json', v => { v.sourceCommit = '0'.repeat(40); }],
  ['primary Ops run substituted', 'acceptance.json', v => { v.runId = '456'; }],
  ['canary source mismatch', 'canary/functional-results.json', v => { v.sourceCommit = '0'.repeat(40); }],
  ['canary tree mismatch', 'canary/functional-results.json', v => { v.sourceTree = '0'.repeat(40); }],
  ['canary run mismatch', 'canary/functional-results.json', v => { v.runId = '456'; }],
  ['canary attempt mismatch', 'canary/functional-results.json', v => { v.runAttempt = '3'; }],
  ['canary UUID family mismatch', 'canary/observer-cleanup.json', v => { v.evidenceId = '33333333-4444-4555-8666-777777777777'; }],
  ['canary cleanup error', 'canary/failure.json', v => { v.cleanupErrors = ['inert failure']; }],
  ['canary unknown edge path', 'canary/packaged-suite.json', v => { v.receipts.functional.file = '../functional-results.json'; }],
  ['primary settings false', 'initial-settings-readonly.json', v => { v.currentWorkspaceReadOnly = false; }],
  ['canary settings false', 'canary/initial-settings-readonly.json', v => { v.currentWorkspaceReadOnly = false; }],
  ['canary menu differs from own observation', 'canary/initial-version-menu.json', v => { v.windowId = 7000; }],
  ['installed record success false', 'core-qualification/installed/installer-upgrade.json', v => { v.succeeded = false; }],
]) test(`dual rejects rehashed ${name}`, t => {
  forbidChildren(t); const f = dualPackagedFixture(t); change(f, file, mutate);
  if (name === 'canary unknown edge path') {
    f.lock.components.desktop.releaseChannel.nativeProvisioning.packagedAcceptance.suiteSha256 = f.digest(file);
  } else f.seal();
  assert.throws(() => verifyDual(f));
});
function dualSummary(f, mutate) {
  const value = f.get('core-qualification/qualification.json'); mutate(value);
  f.lock.components.desktop.releaseChannel.nativeProvisioning.packagedAcceptance.qualificationSha256 = f.put('core-qualification/qualification.json', value);
}
for (const [name, mutate] of [
  ['normal false', v => { v.normalPackagedAcceptanceCompleted = false; }],
  ['canary normal true', v => { v.canaryNormalAcceptanceCompleted = true; }],
  ['missing canary scope', v => { delete v.canaryNormalAcceptanceCompleted; }],
  ['unknown summary key', v => { v.zipMembershipVerified = true; }],
  ['wrong run', v => { v.runId = '456'; }],
  ['wrong source', v => { v.sourceCommit = '0'.repeat(40); }],
  ['wrong sequence', v => { v.sequence++; }],
  ['live quota claim', v => { v.limits.liveAccountQuota = true; }],
  ['invented ordinary runtime input', v => { v.inputs['ordinary.runtime'] = '0'.repeat(64); }],
  ['old packaged helper label', v => { v.inputs['packaged.helper'] = v.inputs['ordinary.helper']; delete v.inputs['ordinary.helper']; }],
  ['missing ordinary acceptance input', v => { delete v.inputs['ordinary.acceptance']; }],
  ['missing ordinary positive input', v => { delete v.inputs['ordinary.positiveUsage']; }],
  ['missing canary positive input', v => { delete v.inputs['packaged.positiveUsage']; }],
  ['wrong canary phase digest', v => { v.inputs['packaged.restart.settings'] = '0'.repeat(64); }],
  ['wrong original ordinary hash', v => { v.inputs['ordinary.acceptance'] = '0'.repeat(64); }],
  ['invalid CI-attested hash', v => { v.inputs['upgrade.owner'] = 'not-a-hash'; }],
]) test(`dual rejects rehashed summary ${name}`, t => {
  forbidChildren(t); const f = dualPackagedFixture(t); dualSummary(f, mutate); assert.throws(() => verifyDual(f));
});
for (const [name, mutate] of [
  ['missing observer', v => { v.steps.splice(1, 1); }],
  ['skipped observer', v => { v.steps[1].conclusion = 'skipped'; }],
  ['failed qualification', v => { v.steps[3].conclusion = 'failure'; }],
  ['duplicated observer', v => { v.steps.push({ ...v.steps[1] }); }],
  ['observer before primary', v => { v.steps[1].number = 0; }],
  ['qualification before installed', v => { v.steps[3].number = 2; }],
  ['summary upload before qualification', v => { v.steps[4].number = 1; }],
  ['wrong job run attempt', v => { v.run_attempt = 9; }],
]) test(`dual rejects rehashed workflow ${name}`, t => {
  forbidChildren(t); const f = dualPackagedFixture(t); change(f, 'core-qualification/workflow-job.json', mutate); f.seal(); assert.throws(() => verifyDual(f));
});
for (const [name, mutate] of [
  ['incomplete paginated inventory', v => { v.total_count++; }],
  ['missing primary artifact', v => { v.artifacts.shift(); v.total_count--; }],
  ['duplicate artifact ID', v => { v.artifacts[1].id = v.artifacts[0].id; }],
  ['duplicate selected artifact name', v => { v.artifacts[1].name = v.artifacts[0].name; }],
  ['expired artifact', v => { v.artifacts[0].expired = true; }],
  ['malformed archive digest', v => { v.artifacts[0].digest = 'sha256:wrong'; }],
  ['zero archive bytes', v => { v.artifacts[0].size_in_bytes = 0; }],
  ['wrong artifact URL ID', v => { v.artifacts[0].id++; }],
  ['foreign repository download', v => { v.artifacts[0].archive_download_url = 'https://example.com/archive.zip'; }],
  ['wrong artifact run', v => { v.artifacts[0].workflow_run.id = 456; }],
  ['wrong artifact source', v => { v.artifacts[0].workflow_run.head_sha = '0'.repeat(40); }],
  ['wrong artifact repository', v => { v.artifacts[0].workflow_run.repository_id++; }],
  ['wrong artifact head repository', v => { v.artifacts[0].workflow_run.head_repository_id++; }],
  ['qualification name wrong attempt', v => { v.artifacts[2].name = v.artifacts[2].name.replace(/-2$/u, '-3'); }],
]) test(`dual rejects rehashed artifact metadata ${name}`, t => {
  forbidChildren(t); const f = dualPackagedFixture(t); change(f, 'core-qualification/workflow-artifacts.json', mutate); f.seal(); assert.throws(() => verifyDual(f));
});
for (const root of ['', 'canary/']) {
  for (const field of ['sessionSubscribed', 'removedSessionHidesUsage', 'otherProviderHidesUsage', 'clientDisposalRemovesUsage',
    'applicationMountPreserved', 'syntheticSiblingPreserved', 'inheritedSessionScopeVerified', 'explicitUndefinedSessionScopeAbsent',
    'removedSessionRestoresUsage', 'closedSessionHidesUsage', 'closedSessionRestoresUsage', 'restoredProviderShowsUsage', 'subscriptionsReleased', 'syntheticContextDisposed']) {
    test(`dual rejects jointly rehashed ${root || 'primary/'}${field}=false`, t => {
      forbidChildren(t); const f = dualPackagedFixture(t);
      for (const file of [`${root}positive-usage.json`, `${root}functional-results.json`, ...(root ? [] : ['acceptance.json'])]) {
        change(f, file, v => { (v.cases ?? v.positiveCopilotUsage)[0][field] = false; });
      }
      f.seal(); assert.throws(() => verifyDual(f));
    });
  }
  for (const [name, mutate] of [
    ['runtime mismatch', v => { v.runtimeSha256 = '0'.repeat(64); }],
    ['source mismatch', v => { v.pluginSource.targetCommit = '0'.repeat(40); }],
    ['Client hash mismatch', v => { v.installedClientSha256 = '0'.repeat(64); }],
    ['quota2 legacy case', v => { v.cases[0].quotaReads = 2; }],
    ['wrong case count', v => { v.cases.pop(); }],
    ['provider order', v => { v.cases.reverse(); }],
    ['extra case key', v => { v.cases[0].extra = true; }],
    ['missing case key', v => { delete v.cases[0].subscriptionsReleased; }],
    ['selector error', v => { v.cases[0].selectorErrors = 1; }],
    ['forbidden Remote call', v => { v.cases[0].forbiddenRemoteCalls = 1; }],
    ['wrong text', v => { v.cases[0].usageText = '7 used'; }],
    ['not restored', v => { v.originalSignedOutApplicationRestored = false; }],
  ]) test(`dual rejects rehashed ${root || 'primary/'}positive ${name}`, t => {
    forbidChildren(t); const f = dualPackagedFixture(t); change(f, `${root}positive-usage.json`, mutate); f.seal(); assert.throws(() => verifyDual(f));
  });
}
test('dual rejects linked canary root without following its receipt graph', t => {
  forbidChildren(t); const f = dualPackagedFixture(t); const other = dualPackagedFixture(t);
  rmSync(join(f.directory, 'canary'), { recursive: true }); symlinkSync(join(other.directory, 'canary'), join(f.directory, 'canary'), 'junction');
  assert.throws(() => verifyDual(f), /native-reparse-path/); unlinkSync(join(f.directory, 'canary'));
});
for (const root of ['../escape', '/absolute', 'C:\\escape', '\\\\server\\share',
  'tests/fixtures/desktop-native-verified-release/../escape', 'tests/fixtures/desktop-native-verified-release/alias.',
  'tests/fixtures/desktop-native-verified-release/proof:stream']) test(`dual rejects unsafe declared root ${root}`, t => {
  forbidChildren(t); const f = dualPackagedFixture(t); f.lock.components.desktop.releaseChannel.nativeProvisioning.fixtureRoot = root;
  assert.throws(() => verifyDual(f));
});
test('dual rejects lexical and linked primary root aliases', t => {
  forbidChildren(t); const f = dualPackagedFixture(t); const other = dualPackagedFixture(t);
  assert.throws(() => readDualPackagedEvidence(f.lock, `${f.directory}/.`));
  const alias = join(other.directory, 'primary-link'); symlinkSync(f.directory, alias, 'junction');
  assert.throws(() => readDualPackagedEvidence(f.lock, alias), /native-reparse-path/); unlinkSync(alias);
});
for (const [name, file, mutate] of [
  ['Ops runUrl in public build', 'release.json', v => { v.build.runUrl = 'not-a-Core-build-field'; }],
  ['wrong Core build node', 'release.json', v => { v.build.nodeVersion = '0.0.0'; }],
  ['wrong Core build plan digest', 'build-receipt.json', v => { v.buildInputs.planSha256 = '0'.repeat(64); }],
  ['public source drift', 'release.json', v => { v.source.commit = '0'.repeat(40); }],
]) test(`dual rejects rehashed ${name} independently from Ops run fields`, t => {
  forbidChildren(t); const f = dualPackagedFixture(t); change(f, file, mutate);
  const channel = f.lock.components.desktop.releaseChannel;
  if (file === 'release.json') channel.manifestRawSha256 = f.digest(file); else channel.buildReceipt.sha256 = f.digest(file);
  dualSummary(f, v => { v.inputs[file === 'release.json' ? 'candidate.manifest' : 'candidate.receipt'] = f.digest(file); });
  assert.throws(() => verifyDual(f));
});
for (const field of ['head_sha', 'run_attempt', 'html_url']) test(`dual rejects rehashed wrong workflow ${field}`, t => {
  forbidChildren(t); const f = dualPackagedFixture(t); change(f, 'core-qualification/workflow-run.json', v => { v[field] = 'wrong'; });
  f.seal(); assert.throws(() => verifyDual(f));
});

// New explicit dual-v2 preparation only: every historical test above remains unchanged.
import { createDualV2Fixture, resealDualV2Fixture } from './helpers/native-dual-v2-fixture.mjs';
import { assertV2Native, assertV2Seed, assertV2Settings, reviewedClient35 } from '../tools/native-dual-v2-evidence.mjs';
const dualV2Added = ['ordinary.initial.settings', 'ordinary.restart.settings', 'ordinary.nativeComposer',
  'ordinary.nativeComposerSeed', 'packaged.nativeComposer', 'packaged.nativeComposerSeed'];
const dualV2Files = ['initial-settings-readonly.json', 'restart-settings-readonly.json', 'native-composer-geometry.json',
  'native-composer-seed.json', 'canary/initial-settings-readonly.json', 'canary/restart-settings-readonly.json',
  'canary/native-composer-geometry.json', 'canary/native-composer-seed.json'];
const verifyDualV2 = f => readDualPackagedEvidence(f.lock, f.directory);
function directNative(f, value = f.get('native-composer-geometry.json')) {
  const functional = f.get('functional-results.json');
  return assertV2Native(value, functional, functional.plugin, f.digest('native-composer-seed.json'), reviewedClient35);
}

test('dual-v2 exact51 raw graph and distinct owned families pass full read-only consumers (inert)', t => {
  forbidChildren(t); const f = createDualV2Fixture(t);
  const watched = [...dualV2Files, 'functional-results.json', 'acceptance.json', 'positive-usage.json',
    'canary/functional-results.json', 'canary/failure.json', 'canary/observer-cleanup.json', 'canary/packaged-suite.json',
    'core-qualification/qualification.json', 'release.json', 'build-receipt.json'];
  const before = watched.map(file => f.digest(file));
  assert.equal(packagedEvidenceFormat(f.lock), 'dual-ordinary-canary-v2');
  assert.equal(usesCombinedPackagedEvidence(f.lock), false);
  const accepted = verifyDualV2(f), canary = f.get('canary/functional-results.json');
  assert.equal(accepted.schemaVersion, 3); assert.equal(accepted.cleanupVerified, true);
  assert.notEqual(accepted.evidenceId, canary.evidenceId);
  for (const field of ['versionMenus', 'timeline', 'settingsAcceptance', 'nativeComposer']) assert.notDeepEqual(accepted[field], canary[field]);
  assert.notEqual(f.get('initial-packaged-graph.json').profile, f.get('canary/initial-packaged-graph.json').profile);
  const summary = f.get('core-qualification/qualification.json'); assert.equal(summary.schemaVersion, 2);
  assert.equal(Object.keys(summary.inputs).length, 51); for (const name of dualV2Added) assert.ok(summary.inputs[name]);
  assert.equal(verifyNativeReleaseEvidence(f.lock, f.directory).valid, true);
  assert.equal(accepted.nativeComposer.geometry[1].copilot.y > accepted.nativeComposer.geometry[1].usage.y, true);
  assert.deepEqual(watched.map(file => f.digest(file)), before);
});
test('dual-v2 fresh Ops family keeps independent native/settings/menus/paths/time and actual run IDs (inert)', t => {
  forbidChildren(t); const f = createDualV2Fixture(t), fresh = f.fresh();
  const accepted = verifyFreshOrdinaryPackagedEvidence(f.lock, fresh.directory, fresh.run);
  assert.equal(accepted.runId, '456'); assert.equal(accepted.runAttempt, '3');
  assert.equal(accepted.nativeComposer.runId, '456'); assert.equal(accepted.nativeComposer.runAttempt, '3');
  for (const field of ['evidenceId', 'versionMenus', 'timeline', 'settingsAcceptance', 'nativeComposer'])
    assert.notDeepEqual(accepted[field], f.get('acceptance.json')[field]);
  assert.equal(verifyFreshSettingsEvidence(f.lock, accepted, fresh.directory), undefined);
  assert.throws(() => verifyFreshOrdinaryPackagedEvidence(f.lock, fresh.directory, { runId: '123', runAttempt: '2' }));
});
for (const label of dualV2Added) test(`dual-v2 rejects missing exact51 addition ${label}`, t => {
  forbidChildren(t); const f = createDualV2Fixture(t); dualSummary(f, v => { delete v.inputs[label]; });
  assert.throws(() => verifyDualV2(f));
});
for (const [name, mutate] of [
  ['unknown52nd', v => { v.inputs['ordinary.invented'] = '0'.repeat(64); }],
  ['schema1 with51', v => { v.schemaVersion = 1; }],
  ['schema2 with45', v => { for (const label of dualV2Added) delete v.inputs[label]; }],
  ['swapped native families', v => { [v.inputs['ordinary.nativeComposer'], v.inputs['packaged.nativeComposer']] = [v.inputs['packaged.nativeComposer'], v.inputs['ordinary.nativeComposer']]; }],
  ['source mismatch', v => { v.sourceCommit = '0'.repeat(40); }],
]) test(`dual-v2 rejects rehashed summary ${name}`, t => {
  forbidChildren(t); const f = createDualV2Fixture(t); dualSummary(f, mutate); assert.throws(() => verifyDualV2(f));
});
for (const file of dualV2Files) {
  test(`dual-v2 rejects missing original ${file}`, t => {
    forbidChildren(t); const f = createDualV2Fixture(t); unlinkSync(join(f.directory, file)); assert.throws(() => verifyDualV2(f));
  });
  test(`dual-v2 rejects unpinned raw newline ${file}`, t => {
    forbidChildren(t); const f = createDualV2Fixture(t); writeFileSync(join(f.directory, file), readFileSync(join(f.directory, file), 'utf8') + '\n');
    assert.throws(() => verifyDualV2(f));
  });
}
for (const [name, mutate] of [
  ['v1 selector with new evidence', f => { f.lock.components.desktop.releaseChannel.nativeProvisioning.packagedAcceptance.format = 'dual-ordinary-canary-v1'; }],
  ['settings lock2', f => { f.lock.components.desktop.releaseChannel.nativeProvisioning.settingsAcceptance.schemaVersion = 2; }],
  ['legacy positive wrapper', f => { f.lock.components.desktop.releaseChannel.nativeProvisioning.usagePositiveAcceptance = { schemaVersion: 1 }; }],
  ['functional2', f => change(f, 'functional-results.json', v => { v.schemaVersion = 2; })],
  ['ordinary2', f => change(f, 'acceptance.json', v => { v.schemaVersion = 2; })],
  ['canary functional2', f => change(f, 'canary/functional-results.json', v => { v.schemaVersion = 2; })],
  ['retired top-level flags restored', f => change(f, 'acceptance.json', v => { v.modelRolesViewLoaded = true; v.currentWorkspaceReadOnly = true; })],
  ['new invented top-level flag', f => change(f, 'acceptance.json', v => { v.accountViewLoaded = true; })],
  ['final cleanup false', f => change(f, 'acceptance.json', v => { v.cleanupVerified = false; })],
]) test(`dual-v2 rejects rehashed family fence ${name}`, t => {
  forbidChildren(t); const f = createDualV2Fixture(t); mutate(f); f.seal(); assert.throws(() => verifyDualV2(f));
});
test('dual-v2 selector does not reinterpret old dual-v1 proof bytes', t => {
  forbidChildren(t); const f = dualPackagedFixture(t);
  f.lock.components.desktop.releaseChannel.nativeProvisioning.packagedAcceptance.format = 'dual-ordinary-canary-v2';
  assert.throws(() => verifyDualV2(f));
});
for (const prefix of ['', 'canary/']) {
  for (const field of ['evidenceId', 'sourceCommit', 'sourceTree', 'runId', 'runAttempt', 'planSha256',
    'runtimeSha256', 'executableSha256', 'provisioningSha256', 'capabilitySha256']) {
    test(`dual-v2 rejects jointly rehashed ${prefix || 'primary/'}native identity ${field}`, t => {
      forbidChildren(t); const f = createDualV2Fixture(t);
      change(f, prefix + 'native-composer-geometry.json', v => { v[field] = field === 'evidenceId' ? '33333333-4444-4555-8666-777777777777' : field === 'runId' || field === 'runAttempt' ? '999' : '0'.repeat(field === 'sourceCommit' || field === 'sourceTree' ? 40 : 64); });
      const attacked = f.get(prefix + 'native-composer-geometry.json')[field]; resealDualV2Fixture(f);
      assert.equal(f.get(prefix + 'functional-results.json').nativeComposer[field], attacked);
      assert.throws(() => verifyDualV2(f));
    });
  }
  for (const [name, mutate] of [
    ['native schema1', v => { v.schemaVersion = 1; }],
    ['wrong Client', v => { v.installedClientSha256 = '0'.repeat(64); }],
    ['wrong source tuple', v => { v.pluginSource.targetCommit = '0'.repeat(40); }],
    ['native unknown field', v => { v.extra = true; }],
    ['native missing scope', v => { delete v.scope; }],
    ['renderer error', v => { v.rendererErrors = ['inert error']; }],
    ['real model claim', v => { v.realModelRound = true; }],
    ['wrong quota scope', v => { v.quota = 'live'; }],
  ]) test(`dual-v2 rejects jointly rehashed ${prefix || 'primary/'}${name}`, t => {
    forbidChildren(t); const f = createDualV2Fixture(t); change(f, prefix + 'native-composer-geometry.json', mutate); f.seal(); assert.throws(() => verifyDualV2(f));
  });
  for (const [name, mutate] of [
    ['seed schema invented', v => { v.schemaVersion = 1; }],
    ['seed calls string', v => { v.seederModelCalls = '0'; }],
    ['seed calls model', v => { v.seederModelCalls = 1; }],
    ['seed wrong Session', v => { v.sessionId = 'other'; }],
    ['seed unregistered', v => { v.workspaceRegistered = false; }],
    ['seed live quota', v => { v.liveAccountQuota = true; }],
  ]) test(`dual-v2 rejects jointly rehashed ${prefix || 'primary/'}${name}`, t => {
    forbidChildren(t); const f = createDualV2Fixture(t); change(f, prefix + 'native-composer-seed.json', mutate); f.seal(); assert.throws(() => verifyDualV2(f));
  });
  for (const [name, mutate] of [
    ['account false', v => { v.accountViewLoaded = false; }],
    ['retirement false', v => { v.retiredModelRolesAbsent = false; }],
    ['legacy role key', v => { delete v.retiredModelRolesAbsent; v.modelRolesViewLoaded = true; }],
    ['settings schema2', v => { v.schemaVersion = 2; }],
    ['duplicate provider', v => { v.registeredSearchProviders.push('github-copilot-hosted'); }],
    ['empty provider', v => { v.registeredSearchProviders.push(''); }],
    ['oversized provider', v => { v.registeredSearchProviders.push('x'.repeat(257)); }],
    ['real search claim', v => { v.realSearch = true; }],
  ]) test(`dual-v2 rejects jointly rehashed ${prefix || 'primary/'}settings ${name}`, t => {
    forbidChildren(t); const f = createDualV2Fixture(t);
    for (const phase of ['initial', 'restart']) change(f, `${prefix}${phase}-settings-readonly.json`, mutate);
    f.seal(); assert.throws(() => verifyDualV2(f));
  });
  test(`dual-v2 rejects rehashed ${prefix || 'primary/'}within-family providers disagreement`, t => {
    forbidChildren(t); const f = createDualV2Fixture(t); change(f, prefix + 'restart-settings-readonly.json', v => v.registeredSearchProviders.push('inert-other'));
    f.seal(); assert.throws(() => verifyDualV2(f));
  });
  for (const [name, mutate] of [
    ['missing native event', v => { v.timeline.splice(v.timeline.findIndex(row => row.event === 'native-composer:application'), 1); }],
    ['duplicate native event', v => { v.timeline.push({ ...v.timeline.at(-1) }); }],
    ['native before restart close', v => { const rows = v.timeline.splice(-5); v.timeline.splice(1, 0, ...rows); v.timeline.forEach((row, i) => { row.milliseconds = i; }); }],
    ['native observed after close', v => { const row = v.timeline.at(-2); v.timeline[v.timeline.length - 2] = v.timeline.at(-1); v.timeline[v.timeline.length - 1] = row; v.timeline.forEach((entry, i) => { entry.milliseconds = i; }); }],
    ['negative elapsed', v => { v.timeline[0].milliseconds = -1; }],
    ['fractional negative elapsed', v => { v.timeline[0].milliseconds = -0.5; }],
  ]) test(`dual-v2 rejects jointly rehashed ${prefix || 'primary/'}timeline ${name}`, t => {
    forbidChildren(t); const f = createDualV2Fixture(t);
    for (const file of [prefix + 'functional-results.json', ...(prefix ? [] : ['acceptance.json'])]) change(f, file, mutate);
    f.seal(); assert.throws(() => verifyDualV2(f));
  });
  for (const field of ['sessionSubscribed', 'removedSessionHidesUsage', 'otherProviderHidesUsage', 'clientDisposalRemovesUsage',
    'applicationMountPreserved', 'syntheticSiblingPreserved', 'inheritedSessionScopeVerified', 'explicitUndefinedSessionScopeAbsent',
    'removedSessionRestoresUsage', 'closedSessionHidesUsage', 'closedSessionRestoresUsage', 'restoredProviderShowsUsage', 'subscriptionsReleased', 'syntheticContextDisposed']) {
    test(`dual-v2 retains jointly rehashed ${prefix || 'primary/'}positive ${field} guard`, t => {
      forbidChildren(t); const f = createDualV2Fixture(t); change(f, prefix + 'positive-usage.json', v => { v.cases[0][field] = false; });
      f.seal(); assert.throws(() => verifyDualV2(f));
    });
  }
  for (const [name, mutate] of [
    ['quota2', v => { v.cases[0].quotaReads = 2; }], ['case extra', v => { v.cases[0].extra = true; }],
    ['wrong amounts', v => { v.cases[0].usageText = '7 used'; }], ['swapped providers', v => { v.cases.reverse(); }],
    ['wrong policy Client', v => { v.installedClientSha256 = '0'.repeat(64); }],
  ]) test(`dual-v2 retains rehashed ${prefix || 'primary/'}positive ${name} guard`, t => {
    forbidChildren(t); const f = createDualV2Fixture(t); change(f, prefix + 'positive-usage.json', mutate); f.seal(); assert.throws(() => verifyDualV2(f));
  });
}
for (const [name, mutate, options] of [
  ['stale seed edge', f => change(f, 'native-composer-geometry.json', v => { v.seedSha256 = '0'.repeat(64); }), { seedEdge: false }],
  ['embedded native mismatch', f => change(f, 'acceptance.json', v => { v.nativeComposer.geometry[0].time.x++; }), { embedNative: false }],
  ['embedded settings mismatch', f => change(f, 'acceptance.json', v => { v.settingsAcceptance[0].registeredSearchProviders.push('extra'); }), { embedSettings: false }],
  ['native cross-family copy', f => f.put('native-composer-geometry.json', f.get('canary/native-composer-geometry.json')), {}],
  ['early observer failure', f => change(f, 'canary/failure.json', v => { v.timeline.at(-1).milliseconds = 0; }), {}],
  ['wrong canary failure marker', f => change(f, 'canary/failure.json', v => { v.error = 'download 403'; }), {}],
]) test(`dual-v2 rejects jointly rehashed ${name}`, t => {
  forbidChildren(t); const f = createDualV2Fixture(t); mutate(f); f.seal(options); assert.throws(() => verifyDualV2(f));
});
for (const phase of ['candidate', 'candidate-restart']) test(`dual-v2 rejects historical roles in installed ${phase}`, t => {
  forbidChildren(t); const f = createDualV2Fixture(t);
  change(f, `core-qualification/installed/${phase}.json`, v => {
    v.actualHostSettingsViews = { ...f.get('core-qualification/installed/baseline.json').actualHostSettingsViews,
      currentWorkspaceReadOnly: true, providerOnlySearchRouting: true, fallbackProviderLabel: true };
  }); f.seal(); assert.throws(() => verifyDualV2(f));
});
test('dual-v2 retains exact old B1 baseline instead of relabeling it settings3', t => {
  forbidChildren(t); const f = createDualV2Fixture(t), old = dualPackagedFixture(t);
  assert.equal(f.digest('core-qualification/installed/baseline.json'), old.digest('core-qualification/installed/baseline.json'));
  change(f, 'core-qualification/installed/baseline.json', v => { v.actualHostSettingsViews = f.get('initial-settings-readonly.json'); });
  f.seal(); assert.throws(() => verifyDualV2(f));
});

// Direct pure parser cases preserve NaN/Infinity rather than letting JSON coerce them to null.
for (const widthIndex of [0, 1]) for (const [name, mutate] of [
  ['x left of dock', g => { g.time.x = g.dock.x - 2; }],
  ['x right of dock', g => { g.copilot.x = g.dock.x + g.dock.width; }],
  ['y above dock', g => { g.time.y = g.dock.y - 2; }],
  ['y below dock', g => { g.copilot.y = g.dock.y + g.dock.height; }],
  ['overlap', g => { g.copilot = { ...g.usage }; }],
  ['NaN', g => { g.time.x = NaN; }], ['Infinity', g => { g.dock.height = Infinity; }],
  ['string coordinate', g => { g.time.x = '20'; }], ['zero width', g => { g.time.width = 0; }],
  ['negative height', g => { g.usage.height = -1; }], ['extra box key', g => { g.dock.extra = 1; }],
  ['missing geometry key', g => { delete g.time; }],
  ['style mismatch', g => { g.copilotStyle.color = 'red'; }],
  ['invalid px syntax', g => { g.nativeStyle.fontSize = g.copilotStyle.fontSize = 'badpx'; }],
  ['zero px', g => { g.nativeStyle.lineHeight = g.copilotStyle.lineHeight = '0px'; }],
  ['unbounded style', g => { g.nativeStyle.color = g.copilotStyle.color = 'x'.repeat(129); }],
]) test(`dual-v2 native pure geometry rejects ${widthIndex ? 400 : 1280} ${name}`, t => {
  forbidChildren(t); const f = createDualV2Fixture(t), value = f.get('native-composer-geometry.json'); mutate(value.geometry[widthIndex]);
  assert.throws(() => directNative(f, value));
});
for (const [name, mutate] of [
  ['extra geometry row', v => v.geometry.push(v.geometry[0])], ['swapped widths', v => v.geometry.reverse()],
  ['wide different row', v => { v.geometry[0].copilot.y += 2; }],
  ['wide usage before time allowed but copilot before usage forbidden', v => { const g = v.geometry[0]; g.copilot.x = g.time.x; g.copilot.width = 60; g.time.x = 350; }],
  ['native dialog false', v => { v.nativeDialogs.time.focusReturned = false; }],
  ['native dialog extra', v => { v.nativeDialogs.usage.extra = true; }],
  ['Copilot dialog invented opened', v => { v.copilotDialog.opened = true; }],
  ['Copilot epoch', v => { v.copilotDialog.epochTextCount = 1; }],
  ['Copilot missing focus', v => { delete v.copilotDialog.focusReturned; }],
]) test(`dual-v2 native pure contract rejects ${name}`, t => {
  forbidChildren(t); const f = createDualV2Fixture(t), value = f.get('native-composer-geometry.json'); mutate(value); assert.throws(() => directNative(f, value));
});
test('dual-v2 pure leaf success and one-pixel containment tolerance retain narrow wrap', t => {
  forbidChildren(t); const f = createDualV2Fixture(t), value = f.get('native-composer-geometry.json');
  assertV2Seed(f.get('native-composer-seed.json')); assertV2Settings(f.get('initial-settings-readonly.json'));
  value.geometry[1].time.x = value.geometry[1].dock.x - 1;
  value.geometry[1].time.y = value.geometry[1].dock.y - 1;
  assert.equal(directNative(f, value), undefined);
});
test('dual-v2 native vertical containment rejects all controls shifted together at both widths', t => {
  forbidChildren(t); const f = createDualV2Fixture(t);
  for (const index of [0, 1]) {
    const value = f.get('native-composer-geometry.json');
    for (const name of ['time', 'usage', 'copilot']) value.geometry[index][name].y += 1000;
    // Equal displacement preserves native wide inline rows and all pairwise separation.
    // The unchanged dock makes only vertical containment invalid (no invented viewport height).
    assert.throws(() => directNative(f, value));
  }
});
test('dual-v2 native fixed policy rejects self-consistent unknown source, Client and historical alpha33', t => {
  forbidChildren(t); const f = createDualV2Fixture(t), old = dualPackagedFixture(t);
  const functional = f.get('functional-results.json'), original = f.get('native-composer-geometry.json');
  const seedHash = f.digest('native-composer-seed.json');
  const source = structuredClone(functional.plugin); source.targetCommit = '0'.repeat(40);
  const wrongSource = structuredClone(original); wrongSource.pluginSource = source;
  assert.throws(() => assertV2Native(wrongSource, functional, source, seedHash, reviewedClient35));
  const wrongClient = structuredClone(original); wrongClient.installedClientSha256 = '0'.repeat(64);
  assert.throws(() => assertV2Native(wrongClient, functional, functional.plugin, seedHash, wrongClient.installedClientSha256));
  const oldPositive = old.get('positive-usage.json');
  const historical = structuredClone(original); historical.pluginSource = oldPositive.pluginSource;
  historical.installedClientSha256 = oldPositive.installedClientSha256;
  assert.throws(() => assertV2Native(historical, functional, historical.pluginSource, seedHash, historical.installedClientSha256));
});
test('dual-v2 rejects the maintained optional native1 wrapper instead of mixing families', t => {
  forbidChildren(t); const f = createDualV2Fixture(t), fresh = f.fresh();
  f.lock.components.desktop.releaseChannel.nativeProvisioning.nativeComposerAcceptance = {
    schemaVersion: 1, sha256: f.digest('native-composer-geometry.json'), installedClientSha256: reviewedClient35,
  };
  assert.throws(() => packagedEvidenceFormat(f.lock), /native-packaged-evidence-invalid/);
  assert.throws(() => verifyDualV2(f), /native-packaged-evidence-invalid/);
  assert.throws(() => verifyFreshOrdinaryPackagedEvidence(f.lock, fresh.directory, fresh.run), /native-packaged-evidence-invalid/);
  assert.throws(() => verifyNativeReleaseEvidence(f.lock, f.directory), /native-packaged-evidence-invalid/);
});
