// All alpha.2 inputs are generated inert copies. No executable/application is launched.
import assert from 'node:assert/strict';
import childProcess from 'node:child_process';
import { syncBuiltinESMExports } from 'node:module';
import { readFileSync, rmSync, symlinkSync, unlinkSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { test } from 'node:test';
import { packagedFixture } from './helpers/native-packaged-fixture.mjs';
import { usesCombinedPackagedEvidence, readCombinedPackagedEvidence, verifyFreshOrdinaryPackagedEvidence } from '../tools/native-packaged-evidence.mjs';
import { verifyNativeReleaseEvidence } from '../tools/verify-native-desktop.mjs';
import { verifyFreshSettingsEvidence, validateSourceIdentity } from './native-asar-release-smoke.mjs';
import { captureOpsCaller, withCoreFixtureEnvironment } from '../tools/native-core-fixture-caller.mjs';

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
for (const failure of [false, true]) test(`isolated Core invocation omits only unrelated SHA and restores on ${failure ? 'rejection' : 'success'}`, async t => {
  forbidChildren(t); const env = ambient(); const before = { ...env }; const caller = captureOpsCaller(env);
  const marker = new Error('private marker'); let invoked = false;
  const promise = withCoreFixtureEnvironment(caller, async () => {
    invoked = true; assert.equal(Object.hasOwn(env, 'GITHUB_SHA'), false);
    assert.deepEqual(env, Object.fromEntries(Object.entries(before).filter(([key]) => key !== 'GITHUB_SHA')));
    if (failure) throw marker; return 'finished';
  }, env);
  if (failure) await assert.rejects(promise, error => error === marker); else assert.equal(await promise, 'finished');
  assert.equal(invoked, true); assert.deepEqual(env, before);
});
for (const field of ['GITHUB_ACTIONS', 'GITHUB_REPOSITORY', 'GITHUB_SHA', 'GITHUB_RUN_ID', 'GITHUB_RUN_ATTEMPT']) {
  test(`invalid ${field} is rejected before Core invocation`, async t => {
    forbidChildren(t); const env = ambient(); const caller = captureOpsCaller(env); env[field] = 'wrong';
    let invoked = false; await assert.rejects(withCoreFixtureEnvironment(caller, () => { invoked = true; }, env), /caller-invalid/);
    assert.equal(invoked, false); assert.equal(env[field], 'wrong');
  });
}
test('missing caller SHA stays absent and cannot invoke Core', async t => {
  forbidChildren(t); const env = ambient(); const caller = captureOpsCaller(env); delete env.GITHUB_SHA;
  let invoked = false; await assert.rejects(withCoreFixtureEnvironment(caller, () => { invoked = true; }, env), /caller-invalid/);
  assert.equal(invoked, false); assert.equal(Object.hasOwn(env, 'GITHUB_SHA'), false);
});

test('fresh identity validation continues to reject a Core checkout that differs from lock', t => {
  forbidChildren(t); const f = packagedFixture(t); const d = f.lock.components.desktop; const build = d.releaseChannel.build;
  const identity = { head: d.source.commit, tree: d.source.tree, dirty: '', lockfileSha256: build.lockfileSha256,
    planSha256: build.planSha256, packageManager: `pnpm@${build.pnpmVersion}`, rootVersion: d.releaseChannel.upstreamVersion,
    desktopVersion: d.releaseChannel.upstreamVersion, nodeVersion: build.nodeVersion };
  assert.equal(validateSourceIdentity(f.lock, d.version, identity).sourceCommit, d.source.commit);
  for (const field of ['head', 'tree', 'dirty']) assert.throws(() => validateSourceIdentity(f.lock, d.version, { ...identity, [field]: 'foreign' }), /checkout-mismatch/);
});

test('default environment lifecycle restores this isolated Node test worker after a thrown undefined', async t => {
  forbidChildren(t);
  const values = ambient(); const saved = Object.fromEntries(Object.keys(values).map(key => [key, process.env[key]]));
  try {
    Object.assign(process.env, values); const caller = captureOpsCaller(); let invoked = false;
    await withCoreFixtureEnvironment(caller, () => {
      invoked = true; assert.equal(process.env.GITHUB_SHA, undefined);
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
