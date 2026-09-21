// INERT parser inputs only; never native, release or installed qualification evidence.
import assert from 'node:assert/strict';
import { readFileSync, unlinkSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import test from 'node:test';
import { packagedV2Fixture, packagedV3Fixture } from './helpers/native-packaged-fixture.mjs';
import { packagedEvidenceFormat, readCombinedPackagedEvidence, verifyFreshOrdinaryPackagedEvidence } from '../tools/native-packaged-evidence.mjs';
import { verifyNativeReleaseEvidence } from '../tools/verify-native-desktop.mjs';
import { verifyFreshSettingsEvidence, verifyFreshNativeComposerEvidence } from './native-asar-release-smoke.mjs';

const read = f => readCombinedPackagedEvidence(f.lock, f.directory);
const nativeMutation = (f, change) => {
  const value = f.get('native-composer-geometry.json'); change(value);
  f.put('native-composer-geometry.json', value);
  const functional = f.get('functional-results.json'); functional.nativeComposer = value;
  f.put('functional-results.json', functional); f.seal();
};
const reject = f => assert.throws(() => read(f));

test('explicit v3 accepts only the original-shaped inert graph through the formal reader', t => {
  const f = packagedV3Fixture(t);
  assert.equal(packagedEvidenceFormat(f.lock), 'combined-suite-v3');
  const accepted = read(f);
  assert.equal(accepted.schemaVersion, 3);
  assert.deepEqual(accepted.nativeComposer, f.get('native-composer-geometry.json'));
  assert.equal(f.get('core-qualification/qualification.json').inputs['packaged.nativeComposer'], f.digest('native-composer-geometry.json'));
  assert.doesNotThrow(() => verifyNativeReleaseEvidence(f.lock, f.directory));
});

test('fresh ordinary v3 validates its own run and pixels without reusing formal byte pins', t => {
  const f = packagedV3Fixture(t); const run = f.ordinary();
  const provisional = f.get('functional-results.json');
  provisional.evidenceId = '12345678-1234-4567-8123-123456789abc';
  provisional.nativeComposer.evidenceId = provisional.evidenceId;
  for (const item of provisional.nativeComposer.geometry) {
    for (const key of ['time', 'usage', 'copilot']) item[key].y += 17;
    item.nativeStyle = { fontSize: '.5px', lineHeight: '20.5px', color: 'rgb(99, 99, 99)' };
    item.copilotStyle = { ...item.nativeStyle };
  }
  for (const [index, phase] of ['initial', 'restart'].entries()) {
    const menu = f.get(`${phase}-version-menu.json`); menu.windowId = 800 + index;
    f.put(`${phase}-version-menu.json`, menu); provisional.versionMenus[index] = menu;
    const settings = f.get(`${phase}-settings-readonly.json`); settings.registeredSearchProviders.push('fresh-only-provider');
    f.put(`${phase}-settings-readonly.json`, settings); provisional.settingsAcceptance[index] = settings;
  }
  f.put('native-composer-geometry.json', provisional.nativeComposer);
  f.put('functional-results.json', provisional);
  f.put('acceptance.json', { ...provisional, scope: 'packaged-acceptance', normalAcceptanceCompleted: true, cleanupVerified: true });
  const accepted = verifyFreshOrdinaryPackagedEvidence(f.lock, f.directory, run);
  assert.doesNotThrow(() => verifyFreshSettingsEvidence(f.lock, accepted, f.directory));
  assert.doesNotThrow(() => verifyFreshNativeComposerEvidence(f.lock, accepted, f.directory));
  assert.throws(() => verifyFreshOrdinaryPackagedEvidence(f.lock, f.directory, { runId: '123', runAttempt: '2' }));
});

for (const field of ['usagePositiveAcceptance', 'nativeComposerAcceptance']) test(`v3 rejects the incompatible legacy ${field} declaration`, t => {
  const f = packagedV3Fixture(t); f.lock.components.desktop.releaseChannel.nativeProvisioning[field] = { schemaVersion: 1 };
  reject(f);
});
for (const format of ['combined-suite-v1', 'combined-suite-v2', 'dual-ordinary-canary-v1', undefined]) test(`v3 cannot be silently reinterpreted as ${format}`, t => {
  const f = packagedV3Fixture(t); f.lock.components.desktop.releaseChannel.nativeProvisioning.packagedAcceptance.format = format;
  reject(f);
});

test('v2 retains its closed alpha33 policy and rejects a v3 positive record', t => {
  const old = packagedV2Fixture(t), next = packagedV3Fixture(t);
  assert.equal(read(old).schemaVersion, 2);
  old.put('positive-usage.json', next.get('positive-usage.json')); old.seal(); reject(old);
});

for (const key of ['evidenceId', 'sourceCommit', 'sourceTree', 'runId', 'runAttempt', 'planSha256', 'runtimeSha256',
  'executableSha256', 'provisioningSha256', 'capabilitySha256']) test(`rehashing does not admit foreign native identity ${key}`, t => {
  const f = packagedV3Fixture(t);
  nativeMutation(f, value => { value[key] = key === 'evidenceId' ? '12345678-1234-4567-8123-123456789abc' :
    ['runId', 'runAttempt'].includes(key) ? '999' : '9'.repeat(key.endsWith('Sha256') ? 64 : 40); });
  reject(f);
});

const nativeKeys = ['schemaVersion', 'scope', 'evidenceId', 'sourceCommit', 'sourceTree', 'runId', 'runAttempt', 'planSha256',
  'runtimeSha256', 'executableSha256', 'provisioningSha256', 'capabilitySha256', 'sessionHistory', 'quota', 'pluginSource',
  'installedClientSha256', 'geometry', 'nativeDialogs', 'copilotDialog', 'rendererErrors', 'realModelRound', 'realOAuth'];
for (const key of nativeKeys) test(`v3 requires native field ${key} even after resealing`, t => {
  const f = packagedV3Fixture(t); nativeMutation(f, value => { delete value[key]; }); reject(f);
});
for (const [label, change] of [
  ['extra', value => { value.extra = true; }],
  ['schema', value => { value.schemaVersion = 3; }],
  ['scope', value => { value.scope = 'synthetic-only'; }],
  ['history', value => { value.sessionHistory = 'live-user-session'; }],
  ['quota', value => { value.quota = 'live'; }],
  ['errors', value => { value.rendererErrors = ['in-scope error']; }],
  ['model', value => { value.realModelRound = true; }],
  ['oauth', value => { value.realOAuth = true; }],
  ['client', value => { value.installedClientSha256 = 'f'.repeat(64); }],
  ['source', value => { value.pluginSource.assetId += 1; }],
  ['order', value => { value.geometry.reverse(); }],
  ['geometry-count', value => { value.geometry.pop(); }],
  ['dialogs-extra', value => { value.nativeDialogs.extra = {}; }],
  ['copilot-extra', value => { value.copilotDialog.extra = true; }],
]) test(`v3 rejects rehashed semantic native damage: ${label}`, t => {
  const f = packagedV3Fixture(t); nativeMutation(f, change); reject(f);
});
for (const width of [0, 1]) for (const key of ['dock', 'time', 'usage', 'copilot']) {
  for (const field of ['x', 'y', 'width', 'height']) test(`v3 rejects nonnumeric native geometry ${width}/${key}/${field}`, t => {
    const f = packagedV3Fixture(t); nativeMutation(f, value => { value.geometry[width][key][field] = '20'; }); reject(f);
  });
  for (const field of ['width', 'height']) test(`v3 rejects zero native geometry ${width}/${key}/${field}`, t => {
    const f = packagedV3Fixture(t); nativeMutation(f, value => { value.geometry[width][key][field] = 0; }); reject(f);
  });
}
for (const [label, change] of [
  ['overlap', geometry => { geometry.copilot = { ...geometry.usage }; }],
  ['outside-viewport', geometry => { geometry.copilot.x = -3; }],
  ['outside-dock', geometry => { geometry.dock.width = 50; }],
  ['wide-order', geometry => { geometry.copilot.x = 0; }],
  ['wide-center', geometry => { geometry.time.y = 80; }],
  ['extra-box-key', geometry => { geometry.time.z = 1; }],
  ['font', geometry => { geometry.nativeStyle.fontSize = geometry.copilotStyle.fontSize = 'auto'; }],
  ['zero-font', geometry => { geometry.nativeStyle.fontSize = geometry.copilotStyle.fontSize = '0px'; }],
  ['style-drift', geometry => { geometry.copilotStyle.color = 'red'; }],
  ['style-extra', geometry => { geometry.copilotStyle.weight = 'normal'; }],
]) test(`v3 preserves native geometric semantics: ${label}`, t => {
  const f = packagedV3Fixture(t); nativeMutation(f, value => change(value.geometry[0])); reject(f);
});
for (const name of ['time', 'usage']) for (const key of ['opened', 'closedOnEscape', 'focusReturned']) test(`v3 requires native ${name}/${key}`, t => {
  const f = packagedV3Fixture(t); nativeMutation(f, value => { value.nativeDialogs[name][key] = false; }); reject(f);
});
for (const key of ['signedOutObserved', 'focusReturned', 'sessionCreditsCount', 'resetCount', 'epochTextCount']) test(`v3 requires Copilot dialog ${key}`, t => {
  const f = packagedV3Fixture(t); nativeMutation(f, value => { value.copilotDialog[key] = typeof value.copilotDialog[key] === 'boolean' ? false : 1; }); reject(f);
});

for (const key of ['settingsAcceptance', 'nativeComposer']) test(`functional3 requires ${key}`, t => {
  const f = packagedV3Fixture(t), value = f.get('functional-results.json'); delete value[key]; f.put('functional-results.json', value); f.seal(); reject(f);
});
for (const key of ['modelRolesViewLoaded', 'currentWorkspaceReadOnly']) test(`functional3 rejects retired ${key}`, t => {
  const f = packagedV3Fixture(t), value = f.get('functional-results.json'); value[key] = true; f.put('functional-results.json', value); f.seal(); reject(f);
});
for (const damage of ['old-schema', 'role-field', 'not-ready', 'sidecar-mismatch', 'different-restart']) test(`settings3 rejects ${damage}`, t => {
  const f = packagedV3Fixture(t), value = f.get('functional-results.json');
  if (damage === 'old-schema') value.settingsAcceptance[0].schemaVersion = 2;
  if (damage === 'role-field') value.settingsAcceptance[0].modelRolesViewLoaded = true;
  if (damage === 'not-ready') value.settingsAcceptance[0].accountViewLoaded = false;
  if (damage === 'sidecar-mismatch') value.settingsAcceptance.forEach(row => row.registeredSearchProviders.push('not-in-file'));
  if (damage === 'different-restart') value.settingsAcceptance[1].registeredSearchProviders.push('changed');
  f.put('functional-results.json', value); f.seal(); reject(f);
});
for (const damage of ['missing', 'wrong-order', 'extra', 'duplicate-deferred', 'deferred-after-observed']) test(`native timeline rejects ${damage}`, t => {
  const f = packagedV3Fixture(t), value = f.get('functional-results.json');
  if (damage === 'missing') value.timeline = value.timeline.filter(row => row.event !== 'native-composer:observed');
  if (damage === 'wrong-order') value.timeline.reverse();
  if (damage === 'extra') value.timeline.push({ event: 'unknown' });
  if (damage === 'duplicate-deferred') value.timeline.splice(-2, 0, { event: 'native-composer:provider-deferred' }, { event: 'native-composer:provider-deferred' });
  if (damage === 'deferred-after-observed') value.timeline.splice(-1, 0, { event: 'native-composer:provider-deferred' });
  value.timeline.forEach((row, i) => { row.milliseconds = i; }); f.put('functional-results.json', value);
  const failure = f.get('failure.json'); failure.timeline = [...value.timeline, { event: 'failure', milliseconds: value.timeline.length }]; f.put('failure.json', failure);
  f.seal(); reject(f);
});
test('the one native deferred event is admitted only in its exact position', t => {
  const f = packagedV3Fixture(t), value = f.get('functional-results.json');
  value.timeline.splice(-2, 0, { event: 'native-composer:provider-deferred' }); value.timeline.forEach((row, i) => { row.milliseconds = i; });
  f.put('functional-results.json', value); const failure = f.get('failure.json');
  failure.timeline = [...value.timeline, { event: 'failure', milliseconds: value.timeline.length }]; f.put('failure.json', failure); f.seal();
  assert.doesNotThrow(() => read(f));
});
for (const file of ['installer-upgrade', 'baseline', 'candidate', 'candidate-restart', 'profile-cleanup', 'package-acceptance', 'acquisition']) test(`v3 still requires original installed ${file}`, t => {
  const f = packagedV3Fixture(t); unlinkSync(join(f.directory, `core-qualification/installed/${file}.json`)); reject(f);
});
test('v3 rejects old installed candidate settings without altering baseline evidence', t => {
  const f = packagedV3Fixture(t), value = f.get('core-qualification/installed/candidate.json');
  value.actualHostSettingsViews = f.get('core-qualification/installed/baseline.json').actualHostSettingsViews;
  f.put('core-qualification/installed/candidate.json', value); f.seal(); reject(f);
});
test('native original-byte hash is mandatory and whitespace remains original data', t => {
  const f = packagedV3Fixture(t), path = join(f.directory, 'native-composer-geometry.json');
  const bytes = readFileSync(path); writeFileSync(path, Buffer.concat([Buffer.from(' \n'), bytes]));
  reject(f); f.seal(); assert.doesNotThrow(() => read(f));
  assert.equal(f.get('core-qualification/qualification.json').inputs['packaged.nativeComposer'], f.digest('native-composer-geometry.json'));
});
for (const damage of ['missing', 'extra', 'wrong-hash']) test(`qualification v3 enforces the exact Core native input label: ${damage}`, t => {
  const f = packagedV3Fixture(t), summary = f.get('core-qualification/qualification.json');
  if (damage === 'missing') delete summary.inputs['packaged.nativeComposer'];
  if (damage === 'extra') summary.inputs['packaged.nativeComposer.extra'] = 'e'.repeat(64);
  if (damage === 'wrong-hash') summary.inputs['packaged.nativeComposer'] = 'e'.repeat(64);
  f.lock.components.desktop.releaseChannel.nativeProvisioning.packagedAcceptance.qualificationSha256 =
    f.put('core-qualification/qualification.json', summary);
  reject(f);
});
for (const file of ['native-composer-geometry.json', 'positive-usage.json']) test(`v3 never substitutes embedded data for absent ${file}`, t => {
  const f = packagedV3Fixture(t); unlinkSync(join(f.directory, file)); reject(f);
});
for (const field of ['commit', 'version', 'assetId', 'dependencyRegistry']) test(`new format cannot choose a different plugin policy: ${field}`, t => {
  const f = packagedV3Fixture(t), positive = f.get('positive-usage.json');
  positive.pluginSource[field === 'commit' ? 'targetCommit' : field] = field === 'assetId' ? 123 : 'another-value';
  f.put('positive-usage.json', positive); f.seal(); reject(f);
});
for (const damage of ['ordinary-in-formal', 'failure-in-ordinary', 'canary-flags']) test(`v3 proof scopes cannot be mixed: ${damage}`, t => {
  const f = packagedV3Fixture(t);
  if (damage === 'ordinary-in-formal') { f.put('acceptance.json', f.get('functional-results.json')); reject(f); }
  if (damage === 'failure-in-ordinary') {
    const run = f.ordinary(); f.put('failure.json', { schemaVersion: 2 });
    assert.throws(() => verifyFreshOrdinaryPackagedEvidence(f.lock, f.directory, run));
  }
  if (damage === 'canary-flags') {
    const value = f.get('functional-results.json'); value.normalAcceptanceCompleted = true;
    f.put('functional-results.json', value); f.seal(); reject(f);
  }
});

test('v3 rejects quota2 even when the inert positive and embedded cases agree', t => {
  const f = packagedV3Fixture(t), value = f.get('functional-results.json'), positive = f.get('positive-usage.json');
  value.positiveCopilotUsage[0].quotaReads = 2; positive.cases = value.positiveCopilotUsage;
  f.put('functional-results.json', value); f.put('positive-usage.json', positive); f.seal(); reject(f);
});
