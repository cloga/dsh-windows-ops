// All alpha.2 inputs are generated inert copies. No executable/application is launched.
import assert from 'node:assert/strict';
import childProcess from 'node:child_process';
import { syncBuiltinESMExports } from 'node:module';
import { readFileSync, rmSync, symlinkSync, unlinkSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { test } from 'node:test';
import { packagedFixture, packagedV2Fixture } from './helpers/native-packaged-fixture.mjs';
import { usesCombinedPackagedEvidence, readCombinedPackagedEvidence, verifyFreshOrdinaryPackagedEvidence } from '../tools/native-packaged-evidence.mjs';
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
