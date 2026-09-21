// INERT UNIT INPUTS ONLY. Passing these tests is not release/runtime qualification.
import assert from 'node:assert/strict';
import childProcess, { spawnSync } from 'node:child_process';
import { existsSync, mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { syncBuiltinESMExports } from 'node:module';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { test } from 'node:test';
import { releasePlan, validateReleaseMetadata, validateSourceIdentity, discoverApplication, runReleaseSmoke, verifySource,
  validateApplicationPackageMetadata, readApplicationPackageIdentity, verifyFreshSettingsEvidence,
  verifyFreshPositiveUsageClient } from './native-asar-release-smoke.mjs';
import { hashFile, sha256 } from '../tools/native-runtime-integrity.mjs';
const lockPath = fileURLToPath(new URL('../deployments/windows-copilot.lock.json', import.meta.url));
const actualLock = () => JSON.parse(readFileSync(lockPath, 'utf8'));
function inertLock() {
  const lock = actualLock(); const d = lock.components.desktop;
  d.version = '0.1.6-inert-unit.1'; d.releaseChannel.version = d.version;
  d.releaseChannel.upstreamVersion = '0.1.6-inert-unit.1';
  d.installedRuntimeDescriptor.relativePath = 'resources/app.asar/dsh/desktop-runtime.json';
  d.source.releaseTag = `dsh-desktop-v${d.version}`; d.releaseChannel.source.tag = d.source.releaseTag;
  d.artifact.url = `https://github.com/cloga/deepseek-harness/releases/download/${d.source.releaseTag}/${d.artifact.name}`;
  d.releaseChannel.manifestUrl = `https://github.com/cloga/deepseek-harness/releases/download/${d.source.releaseTag}/release.json`;
  return lock;
}
function metadata(lock) {
  const d = lock.components.desktop; const plan = releasePlan(lock, d.version);
  return { release: { id: d.artifact.releaseId, tag_name: plan.sourceTag, immutable: true, draft: false, prerelease: true,
    assets: plan.assets.map(a => ({ id: a.id, name: a.name, size: a.bytes ?? 1024, state: 'uploaded',
      digest: `sha256:${a.sha256}`, browser_download_url: `https://github.com/${plan.sourceRepository}/releases/download/${plan.sourceTag}/${a.name}` })) },
    chain: { ref: { ref: `refs/tags/${plan.sourceTag}`, object: { type: 'commit', sha: plan.sourceCommit } },
      tags: [], commit: { sha: plan.sourceCommit, tree: { sha: plan.sourceTree } } } };
}
function identity(lock) {
  const d = lock.components.desktop; const build = d.releaseChannel.build;
  return { head: d.source.commit, tree: d.source.tree, dirty: '', lockfileSha256: build.lockfileSha256, planSha256: build.planSha256,
    packageManager: `pnpm@${build.pnpmVersion}`, rootVersion: d.releaseChannel.upstreamVersion,
    desktopVersion: d.releaseChannel.upstreamVersion, nodeVersion: build.nodeVersion };
}
function temporary(t) {
  const root = mkdtempSync(join(tmpdir(), 'ops-inert-release-unit-'));
  t.after(() => rmSync(root, { recursive: true, force: true })); return root;
}
function forbidChildren(t) {
  let calls = 0;
  t.mock.method(childProcess, 'spawnSync', () => { calls++; throw new Error('unexpected child'); });
  syncBuiltinESMExports();
  t.after(() => { t.mock.restoreAll(); syncBuiltinESMExports(); assert.equal(calls, 0, 'validation failure must execute zero subprocesses'); });
}

// Alpha.2 now uses the explicit full proof fixture in native-packaged-evidence.test.mjs.
for (const upstream of ['0.1.6-alpha.1'])
for (const mode of ['valid', 'missing-contract', 'false-contract', 'false-roles', 'string-catalog', 'real-search', 'initial-tamper', 'restart-tamper']) {
  test(`fresh settings gate ${upstream}/${mode} binds copied leaves without execution (inert inputs)`, t => {
    const lock = actualLock(), output = temporary(t); forbidChildren(t);
    const legacyProof = lock.components.desktop.releaseChannel.nativeProvisioning.settingsAcceptance;
    delete legacyProof.schemaVersion; delete legacyProof.initialVersionMenuSha256; delete legacyProof.restartVersionMenuSha256;
    delete lock.components.desktop.releaseChannel.nativeProvisioning.usageAcceptance;
    lock.components.desktop.releaseChannel.upstreamVersion = upstream;
    const fixture = fileURLToPath(new URL('../' + lock.components.desktop.releaseChannel.nativeProvisioning.fixtureRoot.replaceAll('\\', '/') + '/', import.meta.url));
    for (const phase of ['initial', 'restart']) {
      const name = `${phase}-settings-readonly.json`;
      writeFileSync(join(output, name), readFileSync(join(fixture, name)));
    }
    const accepted = { modelRolesViewLoaded: true, searchProviderCatalogLoaded: true, realSearch: false };
    if (mode === 'missing-contract') delete lock.components.desktop.releaseChannel.nativeProvisioning.settingsAcceptance;
    if (mode === 'false-contract') lock.components.desktop.releaseChannel.nativeProvisioning.settingsAcceptance = false;
    if (mode === 'false-roles') accepted.modelRolesViewLoaded = false;
    if (mode === 'string-catalog') accepted.searchProviderCatalogLoaded = 'true';
    if (mode === 'real-search') accepted.realSearch = true;
    if (mode.endsWith('-tamper')) writeFileSync(join(output, `${mode.split('-')[0]}-settings-readonly.json`), '{}');
    if (mode === 'valid') assert.equal(verifyFreshSettingsEvidence(lock, accepted, output), undefined);
    else assert.throws(() => verifyFreshSettingsEvidence(lock, accepted, output), /source-settings-acceptance-incomplete/);
  });
}

function providerNavigationSourceEvidence(t) {
  const lock = actualLock(), output = temporary(t), channel = lock.components.desktop.releaseChannel;
  const proof = channel.nativeProvisioning.settingsAcceptance; proof.schemaVersion = 2;
  const versionMenus = [];
  for (const phase of ['initial', 'restart']) {
    const settings = { modelRolesViewLoaded: true, currentWorkspaceReadOnly: true,
      searchProviderCatalogLoaded: true, providerOnlySearchRouting: true, fallbackProviderLabel: true,
      registeredSearchProviders: ['deepseek-official', 'github-copilot-hosted'], realSearch: false };
    const path = join(output, `${phase}-settings-readonly.json`); writeFileSync(path, JSON.stringify(settings));
    proof[`${phase}Sha256`] = hashFile(path);
    const versionMenu = { applicationMenuLabel: 'Application', aboutMenuLabel: `About Desktop ${channel.version}…`,
      desktopVersion: channel.version, aboutDispatchCount: 1, nativeModalOpened: false };
    const versionPath = join(output, `${phase}-version-menu.json`); writeFileSync(versionPath, JSON.stringify(versionMenu));
    proof[`${phase}VersionMenuSha256`] = hashFile(versionPath); versionMenus.push(versionMenu);
  }
  const capability = { id: 'account-quota-composer-usage', required: true,
    evidenceScope: 'synthetic-quota-and-public-remote-ui-contracts-not-live-account-access',
    signedOutNetworkRegressionDeclared: true, lifecycleRegressionDeclared: true };
  const signedOut = { usageTriggerCount: 0, accountUsageTextCount: 0, usageSurfaceAbsent: true,
    hostQuotaRequestInstrumentation: 'not-available-in-packaged-smoke' };
  const usageProof = { schemaVersion: 1 }; const observations = [];
  for (const phase of ['initial', 'restart']) {
    const path = join(output, `${phase}-usage-readonly.json`); writeFileSync(path, JSON.stringify({ capability, signedOut }));
    usageProof[`${phase}Sha256`] = hashFile(path); observations.push(signedOut);
  }
  channel.nativeProvisioning.usageAcceptance = usageProof;
  const accepted = { versionMenus, modelRolesViewLoaded: true, searchProviderCatalogLoaded: true,
    manageCompatibilityDisclosureAbsent: true, providerOnlySearchRouting: true,
    copilotUsageCapability: capability, signedOutCopilotUsage: observations,
    hostQuotaNoNetworkEvidence: 'immutable-plugin-ci-regression-only', liveAccountQuota: false,
    timeline: [{ event: 'initial:account' }, { event: 'initial:usage-readonly' },
      { event: 'restart:account' }, { event: 'restart:usage-readonly' }],
    realOAuth: false, verificationNavigationExercised: false, manualVerificationAddressObserved: false,
    realModelRound: false, realSearch: false };
  return { lock, output, accepted };
}

test('fresh schema 2 provider-navigation evidence is exact and call-free', t => {
  forbidChildren(t); const { lock, output, accepted } = providerNavigationSourceEvidence(t);
  assert.equal(verifyFreshSettingsEvidence(lock, accepted, output), undefined);
});
for (const [field, value] of [['manageCompatibilityDisclosureAbsent', false], ['providerOnlySearchRouting', false],
  ['verificationNavigationExercised', true], ['manualVerificationAddressObserved', true]]) {
  test(`fresh schema 2 rejects main ${field}=${value}`, t => {
    forbidChildren(t); const { lock, output, accepted } = providerNavigationSourceEvidence(t); accepted[field] = value;
    assert.throws(() => verifyFreshSettingsEvidence(lock, accepted, output), /source-settings-acceptance-incomplete/);
  });
}
for (const field of ['currentWorkspaceReadOnly', 'providerOnlySearchRouting', 'fallbackProviderLabel']) {
  test(`fresh schema 2 rejects per-phase ${field}=false`, t => {
    forbidChildren(t); const { lock, output, accepted } = providerNavigationSourceEvidence(t);
    const path = join(output, 'restart-settings-readonly.json'); const settings = JSON.parse(readFileSync(path));
    settings[field] = false; writeFileSync(path, JSON.stringify(settings));
    lock.components.desktop.releaseChannel.nativeProvisioning.settingsAcceptance.restartSha256 = hashFile(path);
    assert.throws(() => verifyFreshSettingsEvidence(lock, accepted, output), /source-settings-acceptance-incomplete/);
  });
}
for (const [mode, mutate, rehash] of [
  ['tampered bytes', (path) => writeFileSync(path, readFileSync(path, 'utf8') + '\n'), false],
  ['typed dispatch count', (path) => { const value = JSON.parse(readFileSync(path)); value.aboutDispatchCount = '1'; writeFileSync(path, JSON.stringify(value)); }, true],
  ['wrong version', (path) => { const value = JSON.parse(readFileSync(path)); value.desktopVersion = '0.1.6-wrong'; writeFileSync(path, JSON.stringify(value)); }, true],
  ['phase mismatch', (path) => { const value = JSON.parse(readFileSync(path)); value.aboutMenuLabel += ' mismatch'; writeFileSync(path, JSON.stringify(value)); }, true],
]) {
  test(`fresh schema 2 rejects version-menu ${mode}`, t => {
    forbidChildren(t); const { lock, output, accepted } = providerNavigationSourceEvidence(t);
    const path = join(output, 'restart-version-menu.json'); mutate(path);
    if (rehash) lock.components.desktop.releaseChannel.nativeProvisioning.settingsAcceptance.restartVersionMenuSha256 = hashFile(path);
    assert.throws(() => verifyFreshSettingsEvidence(lock, accepted, output), /source-settings-acceptance-incomplete/);
  });
}

for (const [mode, mutate] of [
  ['live quota claim', ({ accepted }) => { accepted.liveAccountQuota = true; }],
  ['usage trigger', ({ usage }) => { usage.signedOut.usageTriggerCount = 1; }],
  ['usage before account', ({ accepted }) => { accepted.timeline = [{ event: 'initial:usage-readonly' }, { event: 'initial:account' }, { event: 'restart:account' }, { event: 'restart:usage-readonly' }]; }],
]) {
  test(`fresh usage evidence rejects ${mode}`, t => {
    forbidChildren(t); const { lock, output, accepted } = providerNavigationSourceEvidence(t);
    const path = join(output, 'initial-usage-readonly.json'); const usage = JSON.parse(readFileSync(path));
    mutate({ accepted, usage }); writeFileSync(path, JSON.stringify(usage));
    lock.components.desktop.releaseChannel.nativeProvisioning.usageAcceptance.initialSha256 = hashFile(path);
    assert.throws(() => verifyFreshSettingsEvidence(lock, accepted, output), /source-usage-acceptance-incomplete/);
  });
}

function positiveSourceEvidence(t) {
  const f = providerNavigationSourceEvidence(t);
  const native = f.lock.components.desktop.releaseChannel.nativeProvisioning;
  const formal = fileURLToPath(new URL('../' + native.fixtureRoot.replaceAll('\\', '/') + '/', import.meta.url));
  f.accepted.plugin = JSON.parse(readFileSync(join(formal, 'desktop-provisioning.json'))).plugins[0].source;
  const positive = { runtimeSha256: f.lock.components.desktop.installedRuntimeDescriptor.sha256,
    installedClientSha256: sha256('inert unit Client bytes; never published'), pluginSource: f.accepted.plugin,
    cases: ['github-copilot', 'github-copilot-preview'].map(provider => ({
      scope: 'packaged-renderer-released-client-synthetic-session-and-quota', provider, usageText: '7 used',
      quotaReads: 2, sessionSubscribed: true, removedSessionHidesUsage: true, otherProviderHidesUsage: true,
      clientDisposalRemovesUsage: true, selectorErrors: 0, forbiddenRemoteCalls: 0,
      hostTransport: 'not-provided-to-isolated-fixture', applicationMountPreserved: true, syntheticSiblingPreserved: true,
    })), originalSignedOutApplicationRestored: true, hostTransport: 'not-provided-to-isolated-fixture' };
  f.accepted.positiveCopilotUsage = positive.cases; f.accepted.positiveUsageHostTransport = positive.hostTransport;
  f.accepted.timeline.push(...['restart:packaged-graph', 'restart:positive-usage', 'restart:closed'].map(event => ({ event })));
  const proof = { schemaVersion: 1, installedClientSha256: positive.installedClientSha256 };
  native.usagePositiveAcceptance = proof;
  const save = () => {
    writeFileSync(join(f.output, 'positive-usage.json'), JSON.stringify(positive));
    proof.sha256 = hashFile(join(f.output, 'positive-usage.json'));
  };
  save(); return { ...f, positive, proof, save };
}
test('fresh optional positive proof accepts synthetic cases only, with existing settings/usage gates', t => {
  forbidChildren(t); const f = positiveSourceEvidence(t);
  assert.equal(verifyFreshSettingsEvidence(f.lock, f.accepted, f.output), undefined);
});
for (const [name, mutate] of [
  ['preview removed', f => { f.positive.cases.pop(); }],
  ['main cases differ', f => { f.accepted.positiveCopilotUsage = []; }],
  ['Client hash differs', f => { f.positive.installedClientSha256 = '0'.repeat(64); }],
  ['runtime hash differs', f => { f.positive.runtimeSha256 = '0'.repeat(64); }],
  ['source differs', f => { f.positive.pluginSource = { ...f.accepted.plugin, targetCommit: '0'.repeat(40) }; }],
  ['live quota claim', f => { f.accepted.liveAccountQuota = true; }],
  ['restoration is string', f => { f.positive.originalSignedOutApplicationRestored = 'true'; }],
  ['wrong host boundary', f => { f.positive.hostTransport = 'live'; }],
  ['missing restart event', f => { f.accepted.timeline.pop(); }],
  ['positive event too early', f => { f.accepted.timeline.unshift(f.accepted.timeline.splice(-2, 1)[0]); }],
  ['unknown schema', f => { f.proof.schemaVersion = '1'; }],
  ['missing signed-out proof', f => { delete f.lock.components.desktop.releaseChannel.nativeProvisioning.usageAcceptance; }],
  ['missing settings despite old sequence', f => {
    const c = f.lock.components.desktop.releaseChannel; c.sequence = 1; delete c.nativeProvisioning.settingsAcceptance;
  }],
  ...['sessionSubscribed', 'removedSessionHidesUsage', 'otherProviderHidesUsage', 'clientDisposalRemovesUsage',
    'applicationMountPreserved', 'syntheticSiblingPreserved'].flatMap(field => [false, 'true'].map(value =>
    [`${field}=${value}`, f => { f.positive.cases[1][field] = value; }])),
  ...['quotaReads', 'selectorErrors', 'forbiddenRemoteCalls'].map(field =>
    [`string ${field}`, f => { f.positive.cases[1][field] = String(f.positive.cases[1][field]); }]),
]) {
  test(`fresh positive proof rejects ${name} without execution (inert rehashed input)`, t => {
    forbidChildren(t); const f = positiveSourceEvidence(t); mutate(f); f.save();
    assert.throws(() => verifyFreshSettingsEvidence(f.lock, f.accepted, f.output), /native-release-positive-usage-mismatch/);
  });
}
test('fresh positive proof rejects changed bytes rather than trusting success fields', t => {
  forbidChildren(t); const f = positiveSourceEvidence(t);
  writeFileSync(join(f.output, 'positive-usage.json'), JSON.stringify(f.positive) + '\n');
  assert.throws(() => verifyFreshSettingsEvidence(f.lock, f.accepted, f.output), /source-positive-usage-acceptance-incomplete/);
});
test('fresh signed-out usage requires phase equality with matching main leaves', t => {
  forbidChildren(t); const f = positiveSourceEvidence(t);
  const path = join(f.output, 'restart-usage-readonly.json'); const usage = JSON.parse(readFileSync(path));
  usage.signedOut.unexpectedPhaseDifference = true; f.accepted.signedOutCopilotUsage[1] = usage.signedOut;
  writeFileSync(path, JSON.stringify(usage));
  f.lock.components.desktop.releaseChannel.nativeProvisioning.usageAcceptance.restartSha256 = hashFile(path);
  assert.throws(() => verifyFreshSettingsEvidence(f.lock, f.accepted, f.output), /source-usage-acceptance-incomplete/);
});
test('fresh positive opt-in independently hashes Client bytes without executing them', t => {
  forbidChildren(t); const f = positiveSourceEvidence(t); const profile = join(f.output, 'profile');
  const directory = join(profile, 'node_modules/dsh-github-copilot/lib'); mkdirSync(directory, { recursive: true });
  const path = join(directory, 'client.js'); writeFileSync(path, 'inert unit Client bytes; never published');
  assert.equal(verifyFreshPositiveUsageClient(f.lock, profile), undefined);
  writeFileSync(path, 'changed inert Client bytes');
  assert.throws(() => verifyFreshPositiveUsageClient(f.lock, profile), /source-positive-usage-client-mismatch/);
  assert.throws(() => verifyFreshPositiveUsageClient(f.lock, join(f.output, 'absent')), /ENOENT/);
  delete f.lock.components.desktop.releaseChannel.nativeProvisioning.usagePositiveAcceptance;
  assert.equal(verifyFreshPositiveUsageClient(f.lock, join(f.output, 'absent')), undefined);
  const source = readFileSync(new URL('./native-asar-release-smoke.mjs', import.meta.url), 'utf8');
  assert.ok(source.includes('verifyFreshPositiveUsageClient(lock, paths.profile)'));
});

test('historical alpha.1 below sequence 12 keeps optional fresh settings gate (inert)', t => {
  const lock = actualLock(); const channel = lock.components.desktop.releaseChannel; forbidChildren(t);
  channel.upstreamVersion = '0.1.6-alpha.1'; channel.sequence = 11;
  delete channel.nativeProvisioning.settingsAcceptance;
  assert.equal(verifyFreshSettingsEvidence(lock, {}, join(temporary(t), 'absent')), undefined);
  channel.nativeProvisioning.settingsAcceptance = false;
  assert.throws(() => verifyFreshSettingsEvidence(lock, {}, join(temporary(t), 'absent')), /source-settings-acceptance-incomplete/);
});

test('physical .5 lock request fails the release gate before effects (inert)', async t => {
  const lock = actualLock();
  lock.components.desktop.version = '0.1.5-inert-unit.1';
  lock.components.desktop.releaseChannel.upstreamVersion = '0.1.5-inert-unit.1';
  lock.components.desktop.installedRuntimeDescriptor.relativePath = 'resources/dsh/desktop-runtime.json';
  const root = temporary(t); forbidChildren(t);
  assert.throws(() => releasePlan(lock, lock.components.desktop.version), /asar-lock-required|layout-unsupported/);
  await assert.rejects(runReleaseSmoke({ lock, confirmation: lock.components.desktop.version, sourceRoot: join(root, 'source'),
    application: join(root, 'never.exe'), output: join(root, 'never-output'), evidenceRoot: join(root, 'absent-evidence') }), /native-/);
  assert.equal(existsSync(join(root, 'never-output')), false);
});

for (const [label, mutate] of [
  ['confirmation', (l, c) => c + '-wrong'],
  ['repository substitution', l => { l.components.desktop.source.repository = 'https://github.com/other/source'; }],
  ['source mismatch', l => { l.components.desktop.releaseChannel.source.commit = '0'.repeat(40); }],
  ['mutable release', l => { l.components.desktop.artifact.releaseImmutable = false; }],
  ['installer traversal', l => { l.components.desktop.artifact.name = '../other.exe'; }],
  ['asset-id alias', l => { l.components.desktop.releaseChannel.manifestAssetId = l.components.desktop.artifact.assetId; }],
  ['unhashed installer', l => { l.components.desktop.artifact.sha256 = ''; }],
  ['floating Node', l => { l.components.desktop.releaseChannel.build.nodeVersion = '24.x'; }],
  ['floating pnpm', l => { l.components.desktop.releaseChannel.build.pnpmVersion = 'latest'; }],
  ['insecure registry', l => { l.components.desktop.releaseChannel.build.packageRegistry = 'http://registry.npmjs.org/'; }],
  ['credential-bearing registry', l => { l.components.desktop.releaseChannel.build.packageRegistry = 'https://fixture-secret@registry.npmjs.org/'; }],
  ['injected version', l => { l.components.desktop.version = '0.1.6-evil/../../'; }],
]) {
  test(`pre-acquisition rejects ${label} (inert lock)`, t => {
    forbidChildren(t); const lock = inertLock(); const confirmation = mutate(lock, lock.components.desktop.version) ?? lock.components.desktop.version;
    assert.throws(() => releasePlan(lock, confirmation), /native-/);
  });
}

test('inert metadata shape validates only identities, not runtime success', () => {
  const lock = inertLock(); const { release, chain } = metadata(lock);
  const result = validateReleaseMetadata(lock, lock.components.desktop.version, release, chain);
  assert.equal(result.sourceCommit, lock.components.desktop.source.commit);
  assert.equal(Object.hasOwn(result, 'valid'), false);
});
for (const [label, mutate] of [
  ['mutable metadata', (r, c) => { r.immutable = false; }],
  ['draft', r => { r.draft = true; }],
  ['release id', r => { r.id++; }],
  ['wrong tag', r => { r.tag_name += '-wrong'; }],
  ['tag commit', (r, c) => { c.ref.object.sha = '0'.repeat(40); }],
  ['commit tree', (r, c) => { c.commit.tree.sha = '0'.repeat(40); }],
  ['unresolved annotated tag', (r, c) => { c.ref.object.type = 'tag'; }],
  ['asset duplicate', r => { r.assets.push({ ...r.assets[0] }); }],
  ['asset id', r => { r.assets[0].id++; }],
  ['asset size', r => { r.assets[0].size++; }],
  ['asset digest', r => { r.assets[0].digest = 'sha256:' + '0'.repeat(64); }],
  ['asset origin', r => { r.assets[0].browser_download_url = 'https://untrusted.invalid/installer.exe'; }],
  ['absent digest', r => { delete r.assets[0].digest; }],
]) {
  test(`release metadata rejects ${label} before acquisition (inert)`, t => {
    forbidChildren(t); const lock = inertLock(); const { release, chain } = metadata(lock); mutate(release, chain);
    assert.throws(() => validateReleaseMetadata(lock, lock.components.desktop.version, release, chain), /native-/);
  });
}
test('bounded annotated tag chain must end at exact locked commit/tree', () => {
  const lock = inertLock(); const { release, chain } = metadata(lock);
  const target = chain.ref.object; chain.ref.object = { type: 'tag', sha: 'a'.repeat(40) };
  chain.tags.push({ sha: 'a'.repeat(40), object: target });
  assert.equal(validateReleaseMetadata(lock, lock.components.desktop.version, release, chain).sourceCommit, target.sha);
  chain.tags[0].sha = 'b'.repeat(40);
  assert.throws(() => validateReleaseMetadata(lock, lock.components.desktop.version, release, chain), /tag-evidence-invalid/);
});

for (const field of ['head', 'tree', 'dirty', 'lockfileSha256', 'planSha256', 'packageManager', 'rootVersion', 'desktopVersion', 'nodeVersion']) {
  test(`source identity rejects ${field} drift without importing source (inert)`, t => {
    forbidChildren(t); const lock = inertLock(); const observed = identity(lock); observed[field] = 'deliberately-invalid';
    assert.throws(() => validateSourceIdentity(lock, lock.components.desktop.version, observed), /native-/);
  });
}

test('matching commit/tree cannot hide a nonignored untracked source shadow (inert)', t => {
  forbidChildren(t); const lock = inertLock(); const observed = identity(lock);
  observed.dirty = '?? apps/desktop/tests/fixtures/shadow.ts';
  assert.throws(() => validateSourceIdentity(lock, lock.components.desktop.version, observed), /checkout-mismatch/);
  const driver = readFileSync(new URL('./native-asar-release-smoke.mjs', import.meta.url), 'utf8');
  assert.ok(driver.includes("['status', '--porcelain', '--untracked-files=all']"));
  assert.ok(!driver.includes('--untracked-files=no'));
});

test('missing evidence/source and ambiguous extracted layout cause no source import or child', async t => {
  const root = temporary(t); const lock = inertLock(); forbidChildren(t);
  assert.throws(() => verifySource(lock, lock.components.desktop.version, join(root, 'missing-source')), /ENOENT/);
  const extracted = join(root, 'extracted'); mkdirSync(extracted);
  assert.throws(() => discoverApplication(lock, lock.components.desktop.version, extracted), /application-inventory-mismatch/);
  for (const folder of ['one', 'two']) {
    mkdirSync(join(extracted, folder)); writeFileSync(join(extracted, folder, lock.components.desktop.installedExecutable.relativePath), 'inert not executable');
  }
  assert.throws(() => discoverApplication(lock, lock.components.desktop.version, extracted), /application-inventory-mismatch/);
  await assert.rejects(runReleaseSmoke({ lock, confirmation: lock.components.desktop.version, sourceRoot: root,
    application: join(root, 'unused.exe'), output: join(root, 'not-created'), evidenceRoot: join(root, 'missing-evidence') }), /ENOENT|native-/);
  assert.equal(existsSync(join(root, 'not-created')), false);
});

test('a valid-shaped inert .6 request cannot enable local UI execution', async t => {
  forbidChildren(t); const root = temporary(t); const lock = inertLock();
  const old = process.env.GITHUB_ACTIONS; delete process.env.GITHUB_ACTIONS;
  try {
    await assert.rejects(runReleaseSmoke({ lock, confirmation: lock.components.desktop.version, sourceRoot: root,
      application: join(root, 'never.exe'), output: join(root, 'never-output'), evidenceRoot: root }), /ci-run-required|windows-required/);
    assert.equal(existsSync(join(root, 'never-output')), false);
  } finally { if (old === undefined) delete process.env.GITHUB_ACTIONS; else process.env.GITHUB_ACTIONS = old; }
});

test('a CI label cannot authorize paths outside private runner temp (inert)', async t => {
  forbidChildren(t); const root = temporary(t); const lock = inertLock();
  const oldActions = process.env.GITHUB_ACTIONS; const oldTemp = process.env.RUNNER_TEMP;
  process.env.GITHUB_ACTIONS = 'true'; process.env.RUNNER_TEMP = root;
  try {
    await assert.rejects(runReleaseSmoke({ lock, confirmation: lock.components.desktop.version, sourceRoot: root,
      application: join(root, 'never.exe'), output: join(root, 'never-output'), evidenceRoot: root }), /private-run-path-required|windows-required/);
    assert.equal(existsSync(join(root, 'never-output')), false);
  } finally {
    if (oldActions === undefined) delete process.env.GITHUB_ACTIONS; else process.env.GITHUB_ACTIONS = oldActions;
    if (oldTemp === undefined) delete process.env.RUNNER_TEMP; else process.env.RUNNER_TEMP = oldTemp;
  }
});

test('application package full identity is data-only, not PE numeric version or runtime proof', t => {
  forbidChildren(t); const lock = inertLock();
  const bytes = Buffer.from(JSON.stringify({ name: lock.components.desktop.releaseChannel.identity.packageName,
    version: lock.components.desktop.version, private: true, extra: 'fixture-do-not-report' }));
  const result = validateApplicationPackageMetadata(bytes, lock);
  assert.deepEqual(result, { applicationPackageName: lock.components.desktop.releaseChannel.identity.packageName,
    applicationPackageVersion: lock.components.desktop.version, applicationPackageSha256: sha256(bytes) });
  assert.ok(!JSON.stringify(result).includes('fixture-do-not-report'));
});
for (const [label, data] of [
  ['PE-only numeric version', { name: 'cloga-deepseek-harness-desktop', version: '0.1.6.0' }],
  ['wrong full suffix', { name: 'cloga-deepseek-harness-desktop', version: '0.1.6-inert-unit.2' }],
  ['wrong package name', { name: 'unreviewed-package', version: '0.1.6-inert-unit.1' }],
  ['missing name/version', {}], ['non-object', []],
]) {
  test(`root package identity rejects ${label} before any child (inert)`, t => {
    forbidChildren(t);
    assert.throws(() => validateApplicationPackageMetadata(Buffer.from(JSON.stringify(data)), inertLock()), /application-package-identity-mismatch/);
  });
}
test('root package parser rejects malformed/oversized data without reporting contents', t => {
  forbidChildren(t);
  for (const bytes of [Buffer.from('fixture-private-malformed'), Buffer.alloc(1024 * 1024 + 1), Buffer.alloc(0)]) {
    assert.throws(() => validateApplicationPackageMetadata(bytes, inertLock()), { message: 'native-release-smoke-application-package-invalid' });
  }
});
test('maintained ASAR reader rejects missing root package metadata without extracting or launching', t => {
  forbidChildren(t);
  const archive = fileURLToPath(new URL('./fixtures/native-asar-synthetic/app.asar', import.meta.url));
  assert.throws(() => readApplicationPackageIdentity(inertLock(), { archive, archiveSha256: hashFile(archive) }), /application-package-invalid/);
  assert.throws(() => readApplicationPackageIdentity(inertLock(), { archive, archiveSha256: '0'.repeat(64) }), /application-archive-changed/);
});

test('manual workflow preserves acquisition, token and source-loader boundaries (static)', () => {
  const workflow = readFileSync(new URL('../.github/workflows/native-asar-release.yml', import.meta.url), 'utf8');
  assert.match(workflow, /^on:\s*\n\s+workflow_dispatch:/m);
  assert.match(workflow, /^  workflow_call:/m);
  assert.ok(workflow.includes("if: ${{ github.event_name == 'workflow_dispatch' }}"));
  assert.ok(!/^\s*(push|pull_request|pull_request_target|release|workflow_run|schedule):/m.test(workflow));
  const caller = readFileSync(new URL('../.github/workflows/plugin-catalog.yml', import.meta.url), 'utf8');
  assert.ok(caller.includes("if: ${{ github.event_name == 'workflow_dispatch' && inputs.qualify_native_asar == true }}"));
  assert.ok(caller.includes('uses: ./.github/workflows/native-asar-release.yml'));
  assert.ok(caller.includes('needs: [validate, repository-content, repository-policy]'));
  assert.match(caller, /qualify_native_asar:[\s\S]*?type: boolean[\s\S]*?default: false/u);
  assert.ok(!caller.includes('secrets: inherit'));
  assert.ok(caller.includes("cancel-in-progress: ${{ github.event_name != 'workflow_dispatch' || !inputs.qualify_native_asar }}"));
  assert.ok(caller.includes("&& 'native-qualification' || 'checks'"));
  assert.ok(workflow.includes('group: native-asar-release-${{ github.ref }}'));
  assert.ok(!workflow.includes('group: plugin-catalog-'));
  assert.match(workflow, /permissions:\s*\n\s+contents: read/);
  assert.ok(!/contents: write|write-all|secrets\./u.test(workflow));
  for (const action of ['actions/checkout@d23441a48e516b6c34aea4fa41551a30e30af803',
    'actions/setup-node@249970729cb0ef3589644e2896645e5dc5ba9c38',
    'pnpm/action-setup@b906affcce14559ad1aafd4ab0e942779e9f58b1',
    'actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02']) assert.ok(workflow.includes(action), action);
  assert.equal((workflow.match(/GH_TOKEN: \$\{\{ github.token \}\}/gu) ?? []).length, 3);
  assert.ok(workflow.indexOf('--verify-metadata') < workflow.indexOf('/releases/assets/'));
  assert.ok(workflow.indexOf('--verify-acquisition') < workflow.indexOf('fetch --quiet --no-tags --depth=1'));
  assert.ok(workflow.includes('pnpm install --frozen-lockfile'));
  assert.ok(workflow.includes('pnpm run build:lib:host'));
  assert.ok(workflow.includes('node --import tsx/esm'));
  assert.ok(workflow.includes('/output/qualification.json'));
  // Alpha.2-only summary v2 binds the true Ops caller, not the independently verified Core checkout.
  assert.ok(workflow.includes("$alpha2 = $lock.components.desktop.releaseChannel.upstreamVersion -ceq '0.1.6-alpha.2'"));
  assert.ok(workflow.includes('$schema = if ($alpha2) { 2 } else { 1 }'));
  for (const [leaf, environment] of [['repository', 'GITHUB_REPOSITORY'], ['sourceCommit', 'GITHUB_SHA'], ['runId', 'GITHUB_RUN_ID'], ['runAttempt', 'GITHUB_RUN_ATTEMPT']]) {
    assert.ok(workflow.includes(`$caller.${leaf} -cne $env:${environment}`));
  }
  assert.ok(workflow.includes("'repository,runAttempt,runId,sourceCommit'"));
  assert.ok(!workflow.includes('$env:GITHUB_SHA ='));
  const driver = readFileSync(new URL('./native-asar-release-smoke.mjs', import.meta.url), 'utf8');
  assert.ok(driver.indexOf('verifySource(lock, confirmation, sourceRoot);') < driver.indexOf('const caller ='));
  assert.ok(driver.includes('else await withCoreFixtureEnvironment(caller, invokeCore);'));
  assert.ok(driver.includes('verifyFreshOrdinaryPackagedEvidence(lock, sourceOutput, caller)'));
  assert.ok(!driver.includes('localGit(opsRoot'));
  assert.ok(!/Start-Process|& \$installer(?:\s|$)|& \$application(?:\s|$)/mu.test(workflow));
  const cleanup = workflow.slice(workflow.indexOf('- name: Remove private source'));
  assert.ok(cleanup.includes('ReparsePoint'));
  assert.ok(!/Get-ChildItem[^\n]*-Recurse|Remove-Item[^\n]*-Recurse/u.test(cleanup));
  assert.match(cleanup, /Directory\]::Delete\([^\n]*\$false\)/u);
});

test('CLI has no implicit run or confirmation bypass and sanitizes failures', () => {
  const script = fileURLToPath(new URL('./native-asar-release-smoke.mjs', import.meta.url));
  for (const args of [[], ['--plan', '--lock', lockPath, '--confirm-version', actualLock().components.desktop.version + '-deliberately-invalid']]) {
    const result = spawnSync(process.execPath, [script, ...args], { shell: false, encoding: 'utf8', timeout: 30000, maxBuffer: 16384 });
    assert.equal(result.status, 1); assert.equal(result.stderr, '');
    const data = JSON.parse(result.stdout); assert.equal(data.valid, false); assert.equal(data.modelResponseVerified, false);
    assert.match(data.reason, /^native-/);
  }
});
