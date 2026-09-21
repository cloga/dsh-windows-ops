import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { cpSync, lstatSync, mkdtempSync, mkdirSync, readFileSync, readdirSync, renameSync, rmdirSync, symlinkSync, unlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { test } from 'node:test';
import { verifyNativeDesktopFiles, verifyNativeReleaseEvidence } from '../tools/verify-native-desktop.mjs';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { spawn } from 'node:child_process';
import childProcess from 'node:child_process';
import { createRequire, syncBuiltinESMExports } from 'node:module';
import { preflightAsar, headerRuntimeInventory, probeEnvironment } from '../tools/native-asar-runtime.mjs';
import { limits, validateDescriptor } from '../tools/native-runtime-integrity.mjs';
import { probe as electronProbe } from '../tools/native-electron-probe.mjs';
import { readNativeProfileMetadata } from '../tools/native-profile-metadata.mjs';
import { packagedFixture, dualPackagedFixture } from './helpers/native-packaged-fixture.mjs';
import { settingsV3Fixture, settingsV3Negatives, nativeComposerFixture, composerNegatives } from './helpers/native-composer-fixture.mjs';
const asarReader = createRequire(import.meta.url)('../tools/vendor/asar-reader/reader.cjs');

const hash = (value, algorithm = 'sha256', encoding = 'hex') => createHash(algorithm).update(value).digest(encoding);
const actualLock = () => JSON.parse(readFileSync(new URL('../deployments/windows-copilot.lock.json', import.meta.url), 'utf8'));
const formalRoot = fileURLToPath(new URL('../' + actualLock().components.desktop.releaseChannel.nativeProvisioning.fixtureRoot.replaceAll('\\', '/') + '/', import.meta.url));

test('explicit settings schema3 accepts account readiness and retired roles without schema2 claims (inert)', t => {
  const f = settingsV3Fixture(t); assert.equal(verifyNativeReleaseEvidence(f.lock, f.directory).valid, true);
  assert.equal(actualLock().components.desktop.releaseChannel.nativeProvisioning.settingsAcceptance.schemaVersion, 3);
});
for (const [name, mutate] of settingsV3Negatives) {
  test(`formal settings schema3 rejects ${name} even with rehashed synthetic bytes`, t => {
    const f = settingsV3Fixture(t); mutate(f); f.save();
    assert.throws(() => verifyNativeReleaseEvidence(f.lock, f.directory), /native-release-settings-v3-mismatch/);
  });
}
test('formal schema3 authenticates bytes before semantic checks', t => {
  const f = settingsV3Fixture(t); const path = join(f.directory, 'restart-settings-readonly.json');
  writeFileSync(path, readFileSync(path, 'utf8') + '\n');
  assert.throws(() => verifyNativeReleaseEvidence(f.lock, f.directory), /native-release-file-hash-mismatch/);
});

test('optional formal native composer proof accepts source-owned fields in synthetic copies only', t => {
  const f = nativeComposerFixture(t); assert.equal(verifyNativeReleaseEvidence(f.lock, f.directory).valid, true);
  assert.equal(actualLock().components.desktop.releaseChannel.nativeProvisioning.nativeComposerAcceptance.schemaVersion, 1);
});
for (const [name, mutate] of composerNegatives) {
  test(`formal composer rejects rehashed ${name}`, t => {
    const f = nativeComposerFixture(t); mutate(f); f.save();
    assert.throws(() => verifyNativeReleaseEvidence(f.lock, f.directory), /native-release-composer-mismatch/);
  });
}
for (const proof of [null, false, {}, { schemaVersion: '1' }]) {
  test(`formal composer rejects malformed explicit proof ${JSON.stringify(proof)}`, t => {
    const f = nativeComposerFixture(t); f.native.nativeComposerAcceptance = proof;
    assert.throws(() => verifyNativeReleaseEvidence(f.lock, f.directory), /native-release-composer-mismatch/);
  });
}
test('formal composer authenticates its own raw file before semantic checks', t => {
  const f = nativeComposerFixture(t); const path = join(f.directory, 'native-composer-geometry.json');
  writeFileSync(path, readFileSync(path, 'utf8') + '\n');
  assert.throws(() => verifyNativeReleaseEvidence(f.lock, f.directory), /native-release-file-hash-mismatch/);
});
test('formal composer remains optional for explicitly unselected historical proof', t => {
  const f = nativeComposerFixture(t); delete f.native.nativeComposerAcceptance;
  unlinkSync(join(f.directory, 'native-composer-geometry.json'));
  assert.equal(verifyNativeReleaseEvidence(f.lock, f.directory).valid, true);
});

for (const bom of ['', '\uFEFF']) {
  test(`CLI waits for fragmented UTF-8 stdin${bom ? ' with BOM' : ''}`, async (t) => {
    const f = fixture(t);
    const script = fileURLToPath(new URL('../tools/verify-native-desktop.mjs', import.meta.url));
    const child = spawn(process.execPath, [script], { stdio: ['pipe', 'pipe', 'pipe'] });
    const output = [];
    const errors = [];
    child.stdout.on('data', (chunk) => output.push(chunk));
    child.stderr.on('data', (chunk) => errors.push(chunk));
    const completed = new Promise((resolve, reject) => {
      child.once('error', reject);
      child.once('close', (code) => resolve(code));
    });
    const bytes = Buffer.from(bom + JSON.stringify({ ...f, diagnosticLabel: '\u6d4b\u8bd5' }));
    // Deliberately split within the multibyte label and delay the final bytes.
    child.stdin.write(bytes.subarray(0, bytes.length - 4));
    await new Promise((resolve) => setTimeout(resolve, 30));
    child.stdin.end(bytes.subarray(bytes.length - 4));
    assert.equal(await completed, 0, Buffer.concat(errors).toString('utf8'));
    assert.equal(JSON.parse(Buffer.concat(output).toString('utf8')).valid, true);
  });
}

test('dual formal public reader dispatches only the explicit format and preserves legacy alpha1 (inert)', t => {
  const mocks = ['spawn', 'spawnSync', 'execFile', 'execFileSync'].map(name => t.mock.method(childProcess, name, () => { throw new Error('unexpected child'); }));
  syncBuiltinESMExports();
  t.after(() => { for (const mock of mocks) assert.equal(mock.mock.callCount(), 0); t.mock.restoreAll(); syncBuiltinESMExports(); });
  const f = dualPackagedFixture(t);
  const result = verifyNativeReleaseEvidence(f.lock, f.directory);
  assert.equal(result.valid, true); assert.equal(result.formalEvidenceLimits.archiveMembershipVerified, false);
  const legacy = verifyNativeReleaseEvidence(actualLock(), formalRoot);
  assert.equal(legacy.valid, true); assert.equal(Object.hasOwn(legacy, 'formalEvidenceLimits'), false);
  f.lock.components.desktop.releaseChannel.nativeProvisioning.packagedAcceptance.format = 'unknown-dual';
  assert.throws(() => verifyNativeReleaseEvidence(f.lock, f.directory), /native-packaged-evidence-invalid/);
});

test('formal immutable evidence preserves legacy manifest false and startup receipt true', () => {
  const result = verifyNativeReleaseEvidence(actualLock(), formalRoot);
  assert.equal(result.valid, true);
  assert.equal(result.automaticStartupProvisioning, true);
  assert.equal(result.legacyUpdateManifestAutomaticProvisioning, false);
  assert.equal(result.modelResponseVerified, false);
});

test('current formal native composer proof binds exact source and same-run schema3 evidence', () => {
  const lock = actualLock(); const native = lock.components.desktop.releaseChannel.nativeProvisioning;
  assert.equal(native.packagedAcceptance, undefined, 'Plugin35 does not select alpha2 dual evidence');
  assert.equal(native.settingsAcceptance.schemaVersion, 3);
  assert.deepEqual(native.nativeComposerAcceptance, { schemaVersion: 1,
    sha256: '91f92a072b1c4ef80cba49e0c90fb6b03dc3d8e025dd0c6d9347e3296fff4ad3',
    installedClientSha256: '7b4566ef30e1c3c11e64aee527cea8bc5adbf0f22ca356cc8bd3ab07661fd368' });
  const bytes = readFileSync(join(formalRoot, 'native-composer-geometry.json'));
  assert.equal(hash(bytes), native.nativeComposerAcceptance.sha256);
  const value = JSON.parse(bytes); const accepted = JSON.parse(readFileSync(join(formalRoot, 'acceptance.json')));
  assert.equal(value.sourceCommit, lock.components.desktop.source.commit);
  assert.deepEqual(value, accepted.nativeComposer); assert.deepEqual(value.rendererErrors, []);
  assert.deepEqual(value.geometry.map(x => x.viewportWidth), [1280, 400]);
  assert.equal(value.copilotDialog.sessionCreditsCount, 0); assert.equal(value.copilotDialog.epochTextCount, 0);
  assert.equal(verifyNativeReleaseEvidence(lock, formalRoot).valid, true);
});

test('current cloga.18 lock cannot consume the preserved cloga.17 formal generation', () => {
  const historical = fileURLToPath(new URL('./fixtures/desktop-native-verified-release/formal-cloga016-17/', import.meta.url));
  assert.throws(() => verifyNativeReleaseEvidence(actualLock(), historical), /native-release-file-hash-mismatch/);
});

for (const [name, mutate, code] of [
  ['historical cloga.16 source', (l) => { l.components.desktop.source.commit = '2c4f20904887240f83f776c79d8d69a42ce6c1e6'; }, 'source'],
  ['historical cloga.16 sequence', (l) => { l.components.desktop.releaseChannel.sequence = 27; }, 'source'],
  ['historical cloga.16 positive proof', (l) => { l.components.desktop.releaseChannel.nativeProvisioning.usagePositiveAcceptance.sha256 = 'a1515b7ee5af44ff8e7ad86fa07ce8faedaa13f157d02ad99e4a4f99ee174b45'; }, 'file-hash'],
  ['historical cloga.5 source', (l) => { l.components.desktop.source.commit = '29f1863f5457470bacd12de00e987b8bdd6f4b2f'; }, 'source'],
  ['historical cloga.5 sequence', (l) => { l.components.desktop.releaseChannel.sequence = 6; }, 'source'],
  ['historical cloga.5 installer', (l) => { l.components.desktop.artifact.sha256 = 'f39c5dba008385614428e89c3e28f85f0d3aeb24cc0f7992ac1c63c3082c717c'; }, 'installed-identity'],
  ['historical cloga.5 receipt bytes', (l) => { l.components.desktop.releaseChannel.buildReceipt.sha256 = 'd083232d6ac98736935529c352259f97abe19b45cb522d730b0488b1b7777515'; }, 'file-hash'],
  ['historical cloga.5 receipt self digest', (l) => { l.components.desktop.releaseChannel.buildReceipt.receiptSha256 = 'f25b04be3ce7718fbecb6398115fdf311aa804271f8bfedfbc38c3d1b51cd98b'; }, 'source'],
  ['historical cloga.7 source', (l) => { l.components.desktop.source.commit = '293b5a79f533005d99cd60cb00b9ecf810187401'; }, 'source'],
  ['historical cloga.7 sequence', (l) => { l.components.desktop.releaseChannel.sequence = 9; }, 'source'],
  ['historical cloga.7 installer', (l) => { l.components.desktop.artifact.sha256 = '290b587cdab3ffa315ba1796ccabd436096f996abaa144652e33457fd65a3b93'; }, 'installed-identity'],
  ['historical cloga.7 receipt bytes', (l) => { l.components.desktop.releaseChannel.buildReceipt.sha256 = '697c937714a89e7d58fe2fc0096681ee11a493f16174e3c02e18de1eca87c8e7'; }, 'file-hash'],
  ['historical cloga.7 descriptor', (l) => { l.components.desktop.installedRuntimeDescriptor.sha256 = 'ccb45e7c151318c0f239de2dafa64dcec05b8fdff6347cfbc7ed3b2de3264092'; }, 'installed-identity'],
  ['candidate descriptor', (l) => { l.components.desktop.installedRuntimeDescriptor.sha256 = 'f012735da203eacca31ff4ee0df7f2dc7e0a0df5ee16df77845ab7a0062f242c'; }, 'installed-identity'],
  ['manifest provisioning upgraded in lock', (l) => { l.components.desktop.releaseChannel.pluginCompatibility.automaticProvisioning = true; }, 'capability'],
  ['startup provisioning disabled', (l) => { l.components.desktop.releaseChannel.nativeProvisioning.buildReceiptCompatibility.automaticProvisioning = false; }, 'capability'],
  ['different canonical plan', (l) => { l.components.desktop.releaseChannel.nativeProvisioning.plan.planSha256 = '0'.repeat(64); }, 'plan'],
  ['different plugin source', (l) => { l.components.copilotIntegration.source.commit = '0'.repeat(40); }, 'positive-usage'],
  ['modified raw fixture identity', (l) => { l.components.desktop.releaseChannel.buildReceipt.sha256 = '0'.repeat(64); }, 'file-hash'],
  ['defective historical helper', (l) => { l.components.desktop.releaseChannel.nativeProvisioning.helperSha256 = '92c396c690f9e507ae4bacd8c158c4c236ec542ee04c30f603c6832a594a5830'; }, 'helper'],
  ['missing standalone ACK', (l) => { l.components.desktop.releaseChannel.nativeProvisioning.helperAcceptance.validSyntheticHandoffAcknowledged = false; }, 'helper'],
]) {
  test(`formal evidence rejects ${name}`, () => {
    const lock = actualLock();
    mutate(lock);
    assert.throws(() => verifyNativeReleaseEvidence(lock, formalRoot), new RegExp(`native-release-${code}-mismatch`));
  });
}

test('formal actual profile receipt and state agree with the exact source plan', () => {
  const read = (name) => JSON.parse(readFileSync(join(formalRoot, name), 'utf8'));
  const plan = read('desktop-provisioning.json');
  const receipt = read('initial-desktop-plugin-receipts.json').receipts['dsh-github-copilot'];
  const state = read('initial-desktop-plugin-provisioning-state.json');
  assert.deepEqual(receipt.source, plan.plugins[0].source);
  assert.deepEqual(state.plugins[0].receipt, receipt);
  assert.deepEqual(state.plugins[0].source, receipt.source);
  assert.equal(state.planSha256, actualLock().components.desktop.releaseChannel.nativeProvisioning.plan.planSha256);
  assert.equal(state.composition, 'active');
  assert.deepEqual(receipt.states, { staged: true, health: 'passed', activated: true, rolledBack: false, verified: true });
  assert.equal(receipt.releaseId, actualLock().components.copilotIntegration.package.artifact.releaseId);
});

test('formal plugin dependency registry differs from the frozen workspace build registry', () => {
  const read = (name) => JSON.parse(readFileSync(join(formalRoot, name), 'utf8'));
  const plan = read('desktop-provisioning.json');
  assert.equal(plan.plugins[0].source.dependencyRegistry, 'https://packagefeedproxy.microsoft.io/npm/');
  assert.equal(read('release.json').build.packageRegistry, 'https://registry.npmjs.org/');
  assert.equal(read('build-receipt.json').buildInputs.packageRegistry, 'https://registry.npmjs.org/');
  assert.equal(actualLock().components.desktop.releaseChannel.build.packageRegistry, 'https://registry.npmjs.org/');
  assert.equal(plan.plugins[0].source.version, '0.4.0-alpha.35');
  assert.equal(read('release.json').upstreamVersion, '0.1.6-alpha.1');
});

// Use primitive wide-path APIs: Node 24.13 recursive cp/rm can corrupt Unicode
// paths on this Windows carrier. Never follow a fixture junction during cleanup.
function removeFixturePath(path) {
  const stat = lstatSync(path, { throwIfNoEntry: false });
  if (!stat) return;
  if (stat.isDirectory() && !stat.isSymbolicLink()) {
    for (const name of readdirSync(path)) removeFixturePath(join(path, name));
    rmdirSync(path);
  } else unlinkSync(path);
}
function write(path, value) {
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, typeof value === 'string' ? value : JSON.stringify(value));
}

for (const [field, value] of [['ancestorSdkJunction', false], ['ancestorSdkLoaded', true],
  ['ancestorSdkLoaded', 'false']]) {
  test(`formal migration evidence rejects ${field}=${JSON.stringify(value)}`, (t) => {
    const directory = mkdtempSync(join(tmpdir(), 'native-isolation-evidence-'));
    t.after(() => removeFixturePath(directory, { recursive: true, force: true }));
    cpSync(formalRoot, directory, { recursive: true });
    const path = join(directory, 'acceptance.json');
    const acceptance = JSON.parse(readFileSync(path, 'utf8'));
    acceptance[field] = value;
    write(path, acceptance);
    const lock = actualLock();
    lock.components.desktop.releaseChannel.nativeProvisioning.ancestorIsolation.acceptanceSha256 = hash(readFileSync(path));
    assert.throws(() => verifyNativeReleaseEvidence(lock, directory), /native-release-ancestor-isolation-mismatch/);
  });
}
test('formal paired .6 release proves read-only settings views before and after isolated restart', () => {
  const read = name => JSON.parse(readFileSync(join(formalRoot, name), 'utf8'));
  const acceptance = read('acceptance.json');
  assert.equal(Object.hasOwn(acceptance, 'modelRolesViewLoaded'), false);
  assert.equal(acceptance.settingsAcceptance[0].retiredModelRolesAbsent, true);
  assert.equal(acceptance.searchProviderCatalogLoaded, true);
  assert.equal(acceptance.realSearch, false);
  const initial = read('initial-settings-readonly.json');
  const restart = read('restart-settings-readonly.json');
  for (const settings of [initial, restart]) {
    assert.deepEqual(settings, { schemaVersion: 3, accountViewLoaded: true, retiredModelRolesAbsent: true,
      searchProviderCatalogLoaded: true, providerOnlySearchRouting: true, fallbackProviderLabel: true,
      registeredSearchProviders: ['deepseek-official', 'github-copilot-hosted'], realSearch: false });
  }
  const contract = actualLock().components.desktop.releaseChannel.nativeProvisioning.settingsAcceptance;
  assert.equal(contract.initialSha256, hash(readFileSync(join(formalRoot, 'initial-settings-readonly.json'))));
  assert.equal(contract.restartSha256, hash(readFileSync(join(formalRoot, 'restart-settings-readonly.json'))));
  assert.equal(verifyNativeReleaseEvidence(actualLock(), formalRoot).valid, true);
});

for (const [name, mutate] of [
  ['missing settings contract', native => { delete native.settingsAcceptance; }],
  ['false settings contract', native => { native.settingsAcceptance = false; }],
]) {
  test(`formal paired settings reject ${name}`, () => {
    const lock = actualLock(); mutate(lock.components.desktop.releaseChannel.nativeProvisioning);
    assert.throws(() => verifyNativeReleaseEvidence(lock, formalRoot), /native-release-settings-mismatch/);
  });
}
for (const [field, value] of [['modelRolesViewLoaded', false], ['searchProviderCatalogLoaded', 'true'], ['realSearch', true]]) {
  test(`formal paired acceptance rejects settings flag ${field}=${JSON.stringify(value)}`, t => {
    const root = mkdtempSync(join(tmpdir(), 'native-settings-acceptance-negative-'));
    t.after(() => removeFixturePath(root)); cpSync(formalRoot, root, { recursive: true });
    const path = join(root, 'acceptance.json'); const acceptance = JSON.parse(readFileSync(path));
    acceptance[field] = value; write(path, acceptance);
    const lock = actualLock();
    lock.components.desktop.releaseChannel.nativeProvisioning.ancestorIsolation.acceptanceSha256 = hash(readFileSync(path));
    assert.throws(() => verifyNativeReleaseEvidence(lock, root), /native-release-settings-v3-mismatch/);
  });
}
for (const phase of ['initial', 'restart']) {
  test(`formal paired settings reject tampered ${phase} bytes before semantic checks`, t => {
    const root = mkdtempSync(join(tmpdir(), 'native-settings-hash-negative-'));
    t.after(() => removeFixturePath(root)); cpSync(formalRoot, root, { recursive: true });
    const path = join(root, `${phase}-settings-readonly.json`);
    write(path, readFileSync(path, 'utf8') + '\n');
    assert.throws(() => verifyNativeReleaseEvidence(actualLock(), root), /native-release-file-hash-mismatch/);
  });
}
for (const [name, mutate] of [
  ['model roles not loaded', settings => { settings.modelRolesViewLoaded = false; }],
  ['string catalog flag', settings => { settings.searchProviderCatalogLoaded = 'true'; }],
  ['real search claim', settings => { settings.realSearch = true; }],
  ['missing hosted registration', settings => { settings.registeredSearchProviders = ['deepseek-official']; }],
  ['duplicate registration', settings => { settings.registeredSearchProviders.push('github-copilot-hosted'); }],
  ['empty registration', settings => { settings.registeredSearchProviders.push(''); }],
  ['non-string registration', settings => { settings.registeredSearchProviders.push(7); }],
  ['different restart catalog', settings => { settings.registeredSearchProviders.push('synthetic-extra-provider'); }],
]) {
  test(`formal paired settings reject rehashed ${name}`, t => {
    const root = mkdtempSync(join(tmpdir(), 'native-settings-semantic-negative-'));
    t.after(() => removeFixturePath(root)); cpSync(formalRoot, root, { recursive: true });
    const path = join(root, 'restart-settings-readonly.json'); const settings = JSON.parse(readFileSync(path));
    mutate(settings); write(path, settings);
    const lock = actualLock();
    lock.components.desktop.releaseChannel.nativeProvisioning.settingsAcceptance.restartSha256 = hash(readFileSync(path));
    assert.throws(() => verifyNativeReleaseEvidence(lock, root), /native-release-settings-v3-mismatch/);
  });
}

function providerNavigationFixture(t) {
  const root = mkdtempSync(join(tmpdir(), 'native-provider-navigation-evidence-'));
  t.after(() => removeFixturePath(root)); cpSync(formalRoot, root, { recursive: true });
  const lock = actualLock();
  delete lock.components.desktop.releaseChannel.nativeProvisioning.usagePositiveAcceptance; // Inert settings fixture, not copied positive success.
  delete lock.components.desktop.releaseChannel.nativeProvisioning.nativeComposerAcceptance;
  const proof = lock.components.desktop.releaseChannel.nativeProvisioning.settingsAcceptance;
  proof.schemaVersion = 2;
  const acceptancePath = join(root, 'acceptance.json');
  const acceptance = JSON.parse(readFileSync(acceptancePath)); const versionMenus = [];
  delete acceptance.settingsAcceptance; delete acceptance.nativeComposer;
  Object.assign(acceptance, { modelRolesViewLoaded: true, currentWorkspaceReadOnly: true,
    manageCompatibilityDisclosureAbsent: true, providerOnlySearchRouting: true,
    verificationNavigationExercised: false, manualVerificationAddressObserved: false });
  for (const phase of ['initial', 'restart']) {
    const path = join(root, `${phase}-settings-readonly.json`);
    const settings = { modelRolesViewLoaded: true, currentWorkspaceReadOnly: true,
      searchProviderCatalogLoaded: true, providerOnlySearchRouting: true, fallbackProviderLabel: true,
      registeredSearchProviders: ['deepseek-official', 'github-copilot-hosted'], realSearch: false };
    write(path, settings); proof[`${phase}Sha256`] = hash(readFileSync(path));
    const versionMenu = { applicationMenuLabel: 'Application', aboutMenuLabel: `About Desktop ${lock.components.desktop.version}…`,
      desktopVersion: lock.components.desktop.version, aboutDispatchCount: 1, nativeModalOpened: false };
    const versionPath = join(root, `${phase}-version-menu.json`); write(versionPath, versionMenu);
    proof[`${phase}VersionMenuSha256`] = hash(readFileSync(versionPath)); versionMenus.push(versionMenu);
  }
  const usageCapability = { id: 'account-quota-composer-usage', required: true,
    evidenceScope: 'synthetic-quota-and-public-remote-ui-contracts-not-live-account-access',
    signedOutNetworkRegressionDeclared: true, lifecycleRegressionDeclared: true };
  const signedOut = { usageTriggerCount: 0, accountUsageTextCount: 0, usageSurfaceAbsent: true,
    hostQuotaRequestInstrumentation: 'not-available-in-packaged-smoke' };
  const usageProof = { schemaVersion: 1 }; const observations = [];
  for (const phase of ['initial', 'restart']) {
    const path = join(root, `${phase}-usage-readonly.json`); write(path, { capability: usageCapability, signedOut });
    usageProof[`${phase}Sha256`] = hash(readFileSync(path)); observations.push(signedOut);
  }
  lock.components.desktop.releaseChannel.nativeProvisioning.usageAcceptance = usageProof;
  Object.assign(acceptance, { versionMenus, copilotUsageCapability: usageCapability,
    signedOutCopilotUsage: observations, hostQuotaNoNetworkEvidence: 'immutable-plugin-ci-regression-only',
    liveAccountQuota: false, timeline: [
      { event: 'initial:account' }, { event: 'initial:usage-readonly' },
      { event: 'restart:account' }, { event: 'restart:usage-readonly' },
    ] });
  write(acceptancePath, acceptance);
  lock.components.desktop.releaseChannel.nativeProvisioning.ancestorIsolation.acceptanceSha256 = hash(readFileSync(acceptancePath));
  return { root, lock };
}

test('schema 2 accepts hash-bound provider-only navigation evidence without real calls', t => {
  const { root, lock } = providerNavigationFixture(t);
  assert.equal(verifyNativeReleaseEvidence(lock, root).valid, true);
});

for (const [field, value] of [['manageCompatibilityDisclosureAbsent', false], ['providerOnlySearchRouting', false],
  ['verificationNavigationExercised', true], ['manualVerificationAddressObserved', true]]) {
  test(`schema 2 rejects main acceptance ${field}=${value}`, t => {
    const { root, lock } = providerNavigationFixture(t);
    const path = join(root, 'acceptance.json'); const acceptance = JSON.parse(readFileSync(path));
    acceptance[field] = value; write(path, acceptance);
    lock.components.desktop.releaseChannel.nativeProvisioning.ancestorIsolation.acceptanceSha256 = hash(readFileSync(path));
    assert.throws(() => verifyNativeReleaseEvidence(lock, root), /native-release-settings-mismatch/);
  });
}
for (const field of ['currentWorkspaceReadOnly', 'providerOnlySearchRouting', 'fallbackProviderLabel']) {
  test(`schema 2 rejects per-phase ${field}=false`, t => {
    const { root, lock } = providerNavigationFixture(t);
    const path = join(root, 'restart-settings-readonly.json'); const settings = JSON.parse(readFileSync(path));
    settings[field] = false; write(path, settings);
    lock.components.desktop.releaseChannel.nativeProvisioning.settingsAcceptance.restartSha256 = hash(readFileSync(path));
    assert.throws(() => verifyNativeReleaseEvidence(lock, root), /native-release-settings-mismatch/);
  });
}
for (const [mode, mutate, rehash] of [
  ['tampered bytes', (path) => write(path, readFileSync(path, 'utf8') + '\n'), false],
  ['typed dispatch count', (path) => { const value = JSON.parse(readFileSync(path)); value.aboutDispatchCount = '1'; write(path, value); }, true],
  ['wrong version', (path) => { const value = JSON.parse(readFileSync(path)); value.desktopVersion = '0.1.6-wrong'; write(path, value); }, true],
  ['phase mismatch', (path) => { const value = JSON.parse(readFileSync(path)); value.aboutMenuLabel += ' mismatch'; write(path, value); }, true],
]) {
  test(`schema 2 rejects version-menu ${mode}`, t => {
    const { root, lock } = providerNavigationFixture(t);
    const path = join(root, 'restart-version-menu.json'); mutate(path);
    if (rehash) lock.components.desktop.releaseChannel.nativeProvisioning.settingsAcceptance.restartVersionMenuSha256 = hash(readFileSync(path));
    assert.throws(() => verifyNativeReleaseEvidence(lock, root), /native-release-(?:file-hash|settings)-mismatch/);
  });
}
for (const [mode, mutate] of [
  ['live quota claim', ({ acceptance }) => { acceptance.liveAccountQuota = true; }],
  ['wrong evidence scope', ({ acceptance }) => { acceptance.copilotUsageCapability.evidenceScope = 'live'; }],
  ['usage trigger', ({ usage }) => { usage.signedOut.usageTriggerCount = 1; }],
  ['invented usage text', ({ usage }) => { usage.signedOut.accountUsageTextCount = 1; }],
  ['wrong instrumentation boundary', ({ usage }) => { usage.signedOut.hostQuotaRequestInstrumentation = 'observed'; }],
  ['usage before account', ({ acceptance }) => { acceptance.timeline = [{ event: 'initial:usage-readonly' }, { event: 'initial:account' }, { event: 'restart:account' }, { event: 'restart:usage-readonly' }]; }],
]) {
  test(`usage evidence rejects ${mode}`, t => {
    const { root, lock } = providerNavigationFixture(t);
    const acceptancePath = join(root, 'acceptance.json'); const acceptance = JSON.parse(readFileSync(acceptancePath));
    const usagePath = join(root, 'initial-usage-readonly.json'); const usage = JSON.parse(readFileSync(usagePath));
    mutate({ acceptance, usage }); write(acceptancePath, acceptance); write(usagePath, usage);
    lock.components.desktop.releaseChannel.nativeProvisioning.ancestorIsolation.acceptanceSha256 = hash(readFileSync(acceptancePath));
    lock.components.desktop.releaseChannel.nativeProvisioning.usageAcceptance.initialSha256 = hash(readFileSync(usagePath));
    assert.throws(() => verifyNativeReleaseEvidence(lock, root), /native-release-usage-mismatch/);
  });
}

// Entirely synthetic/rehashed temporary copies: never published release evidence.
function positiveUsageFixture(t) {
  const fixture = providerNavigationFixture(t);
  const { root, lock } = fixture;
  const accepted = JSON.parse(readFileSync(join(root, 'acceptance.json')));
  const positive = {
    runtimeSha256: lock.components.desktop.installedRuntimeDescriptor.sha256,
    installedClientSha256: hash('inert unit Client bytes, not a published artifact'),
    pluginSource: accepted.plugin,
    cases: ['github-copilot', 'github-copilot-preview'].map(provider => ({
      scope: 'packaged-renderer-released-client-synthetic-session-and-quota', provider,
      usageText: '7 used', quotaReads: 2, sessionSubscribed: true,
      removedSessionHidesUsage: true, otherProviderHidesUsage: true, clientDisposalRemovesUsage: true,
      selectorErrors: 0, forbiddenRemoteCalls: 0, hostTransport: 'not-provided-to-isolated-fixture',
      applicationMountPreserved: true, syntheticSiblingPreserved: true,
    })),
    originalSignedOutApplicationRestored: true, hostTransport: 'not-provided-to-isolated-fixture',
  };
  accepted.positiveCopilotUsage = positive.cases;
  accepted.positiveUsageHostTransport = positive.hostTransport;
  accepted.timeline.push(...['restart:packaged-graph', 'restart:positive-usage', 'restart:closed'].map(event => ({ event })));
  const proof = { schemaVersion: 1, installedClientSha256: positive.installedClientSha256 };
  lock.components.desktop.releaseChannel.nativeProvisioning.usagePositiveAcceptance = proof;
  const save = () => {
    write(join(root, 'positive-usage.json'), positive);
    proof.sha256 = hash(readFileSync(join(root, 'positive-usage.json')));
    write(join(root, 'acceptance.json'), accepted);
    lock.components.desktop.releaseChannel.nativeProvisioning.ancestorIsolation.acceptanceSha256 = hash(readFileSync(join(root, 'acceptance.json')));
  };
  save(); return { ...fixture, accepted, positive, proof, save };
}

test('optional positive proof accepts both synthetic routes without altering formal proof', t => {
  const original = actualLock().components.desktop.releaseChannel.nativeProvisioning.usagePositiveAcceptance;
  const { lock, root } = positiveUsageFixture(t);
  assert.equal(verifyNativeReleaseEvidence(lock, root).valid, true);
  assert.deepEqual(actualLock().components.desktop.releaseChannel.nativeProvisioning.usagePositiveAcceptance, original);
});
test('current formal release requires hash-bound positive canonical and preview evidence', () => {
  const lock = actualLock();
  const proof = lock.components.desktop.releaseChannel.nativeProvisioning.usagePositiveAcceptance;
  assert.equal(proof.schemaVersion, 1);
  assert.equal(proof.sha256, '931370e7c0d2b7408553d51f0c45d7416955151aa4e06ec8b5757f4671377354');
  assert.equal(proof.installedClientSha256, '7b4566ef30e1c3c11e64aee527cea8bc5adbf0f22ca356cc8bd3ab07661fd368');
  assert.equal(hash(readFileSync(join(formalRoot, 'positive-usage.json'))), proof.sha256);
  assert.equal(verifyNativeReleaseEvidence(lock, formalRoot).valid, true);
});
for (const field of ['sessionSubscribed', 'removedSessionHidesUsage', 'otherProviderHidesUsage',
  'clientDisposalRemovesUsage', 'applicationMountPreserved', 'syntheticSiblingPreserved']) {
  for (const value of [false, 'true', 1, null]) {
    test(`positive proof rejects preview ${field}=${JSON.stringify(value)} even rehashed`, t => {
      const f = positiveUsageFixture(t); f.positive.cases[1][field] = value; f.save();
      assert.throws(() => verifyNativeReleaseEvidence(f.lock, f.root), /native-release-positive-usage-mismatch/);
    });
  }
}
for (const [name, mutate] of [
  ['wrong scope', f => { f.positive.cases[0].scope = 'live-account'; }],
  ['missing preview', f => { f.positive.cases.pop(); }],
  ['duplicate canonical', f => { f.positive.cases[1].provider = 'github-copilot'; }],
  ['non-Copilot route', f => { f.positive.cases[0].provider = 'other-provider'; }],
  ['missing usage text', f => { f.positive.cases[0].usageText = ''; }],
  ['wrong quota count', f => { f.positive.cases[0].quotaReads = 1; }],
  ['string quota count', f => { f.positive.cases[0].quotaReads = '2'; }],
  ['selector failure', f => { f.positive.cases[0].selectorErrors = 1; }],
  ['string selector count', f => { f.positive.cases[0].selectorErrors = '0'; }],
  ['remote call', f => { f.positive.cases[0].forbiddenRemoteCalls = 1; }],
  ['string remote count', f => { f.positive.cases[0].forbiddenRemoteCalls = '0'; }],
  ['case Host transport', f => { f.positive.cases[0].hostTransport = 'provided'; }],
  ['runtime mismatch', f => { f.positive.runtimeSha256 = '0'.repeat(64); }],
  ['Client mismatch', f => { f.positive.installedClientSha256 = '0'.repeat(64); }],
  ['source mismatch', f => { f.positive.pluginSource = { ...f.accepted.plugin, version: 'wrong' }; }],
  ['main cases mismatch', f => { f.accepted.positiveCopilotUsage = []; }],
  ['main Host transport', f => { f.accepted.positiveUsageHostTransport = 'provided'; }],
  ['positive Host transport', f => { f.positive.hostTransport = 'provided'; }],
  ['string restoration', f => { f.positive.originalSignedOutApplicationRestored = 'true'; }],
  ['missing restoration', f => { delete f.positive.originalSignedOutApplicationRestored; }],
  ['positive event missing', f => { f.accepted.timeline = f.accepted.timeline.filter(x => x.event !== 'restart:positive-usage'); }],
  ['positive before account', f => { f.accepted.timeline.unshift(f.accepted.timeline.splice(-2, 1)[0]); }],
  ['duplicate positive event', f => { f.accepted.timeline.push({ event: 'restart:positive-usage' }); }],
  ['wrong proof schema', f => { f.proof.schemaVersion = 2; }],
  ['invalid Client digest', f => { f.proof.installedClientSha256 = ''; }],
]) {
  test(`positive proof rejects ${name} (synthetic rehashed copies)`, t => {
    const f = positiveUsageFixture(t); mutate(f); f.save();
    assert.throws(() => verifyNativeReleaseEvidence(f.lock, f.root), /native-release-positive-usage-mismatch/);
  });
}
for (const proof of [null, false, {}, { schemaVersion: '1' }]) {
  test(`positive proof rejects malformed explicit contract ${JSON.stringify(proof)}`, t => {
    const f = positiveUsageFixture(t);
    f.lock.components.desktop.releaseChannel.nativeProvisioning.usagePositiveAcceptance = proof;
    assert.throws(() => verifyNativeReleaseEvidence(f.lock, f.root), /native-release-positive-usage-mismatch/);
  });
}
test('positive proof authenticates bytes before evaluating observations', t => {
  const f = positiveUsageFixture(t);
  write(join(f.root, 'positive-usage.json'), readFileSync(join(f.root, 'positive-usage.json'), 'utf8') + '\n');
  assert.throws(() => verifyNativeReleaseEvidence(f.lock, f.root), /native-release-file-hash-mismatch/);
});
test('explicit positive proof cannot replace signed-out usage schema 1', t => {
  const f = positiveUsageFixture(t); delete f.lock.components.desktop.releaseChannel.nativeProvisioning.usageAcceptance;
  assert.throws(() => verifyNativeReleaseEvidence(f.lock, f.root), /native-release-positive-usage-mismatch/);
});
test('signed-out usage requires deterministic phase equality even when both phases rehash', t => {
  const f = positiveUsageFixture(t); const path = join(f.root, 'restart-usage-readonly.json');
  const usage = JSON.parse(readFileSync(path)); usage.signedOut.unexpectedPhaseDifference = true;
  f.accepted.signedOutCopilotUsage[1] = usage.signedOut; write(path, usage);
  f.lock.components.desktop.releaseChannel.nativeProvisioning.usageAcceptance.restartSha256 = hash(readFileSync(path)); f.save();
  assert.throws(() => verifyNativeReleaseEvidence(f.lock, f.root), /native-release-usage-mismatch/);
});

test('settings evidence rejects an unknown schema version', t => {
  const { root, lock } = providerNavigationFixture(t);
  lock.components.desktop.releaseChannel.nativeProvisioning.settingsAcceptance.schemaVersion = 4;
  assert.throws(() => verifyNativeReleaseEvidence(lock, root), /native-release-settings-mismatch/);
});

for (const mode of ['valid', 'missing-contract', 'false-contract', 'false-roles', 'string-catalog', 'real-search',
  'initial-tamper', 'restart-tamper', 'missing-hosted-provider', 'installer-upgrade-claim']) {
  test(`alpha.2 settings gate ${mode} (inert rehashed copy, not release evidence)`, t => {
    const f = packagedFixture(t); noChild(t);
    const { lock, directory: root } = f; const native = lock.components.desktop.releaseChannel.nativeProvisioning;
    const path = join(root, 'functional-results.json'); const acceptance = JSON.parse(readFileSync(path));
    if (mode === 'missing-contract') delete native.settingsAcceptance;
    if (mode === 'false-contract') native.settingsAcceptance = false;
    if (mode === 'false-roles') acceptance.modelRolesViewLoaded = false;
    if (mode === 'string-catalog') acceptance.searchProviderCatalogLoaded = 'true';
    if (mode === 'real-search') acceptance.realSearch = true;
    if (mode === 'installer-upgrade-claim') acceptance.installerUpgradeVerified = true;
    write(path, acceptance); f.seal();
    if (mode.endsWith('-tamper')) write(join(root, `${mode.split('-')[0]}-settings-readonly.json`), '{}');
    if (mode === 'missing-hosted-provider') {
      const settingsPath = join(root, 'restart-settings-readonly.json');
      const settings = JSON.parse(readFileSync(settingsPath)); settings.registeredSearchProviders = ['deepseek-official'];
      write(settingsPath, settings); native.settingsAcceptance.restartSha256 = hash(readFileSync(settingsPath));
    }
    if (mode === 'valid') {
      assert.equal(acceptance.installerUpgradeVerified, false);
      assert.equal(verifyNativeReleaseEvidence(lock, root).valid, true);
    } else {
      assert.throws(() => verifyNativeReleaseEvidence(lock, root), /native-packaged-evidence-invalid/);
    }
  });
}

test('formal .6 graph records actual ASAR inventory and Node mode, not legacy SDK fields', () => {
  const graph = JSON.parse(readFileSync(join(formalRoot, 'initial-packaged-graph.json')));
  assert.equal(graph.resolutionMode, 'runtime'); assert.equal(graph.runAsNode, '1');
  assert.equal(graph.electronVersion, '44.0.0'); assert.equal(graph.nodeVersion, '24.18.1');
  assert.equal(graph.google, undefined); assert.equal(graph.sdk, undefined);
  assert.equal(verifyNativeReleaseEvidence(actualLock(), formalRoot).valid, true);
});
for (const [field, value] of [['resolutionMode', 'link'], ['runAsNode', '0'], ['electronNoAsarPresent', true],
  ['nodeVersion', null], ['electronVersion', null], ['runtimeRoot', 'C:\\wrong-runtime'], ['cwd', 'C:\\wrong-profile']]) {
  test(`formal .6 graph rejects malformed ${field} in an altered data copy`, t => {
    const root = mkdtempSync(join(tmpdir(), 'native-formal-graph-negative-'));
    t.after(() => removeFixturePath(root)); cpSync(formalRoot, root, { recursive: true });
    const path = join(root, 'initial-packaged-graph.json'); const graph = JSON.parse(readFileSync(path));
    graph[field] = value; write(path, graph);
    const lock = actualLock(); lock.components.desktop.releaseChannel.nativeProvisioning.ancestorIsolation.initialGraphSha256 = hash(readFileSync(path));
    assert.throws(() => verifyNativeReleaseEvidence(lock, root), /native-release-ancestor-graph-mismatch/);
  });
}

function fixture(t, dependencyRegistry = 'https://registry.npmjs.org/', withPolicy = false) {
  const root = mkdtempSync(join(tmpdir(), 'native-desktop-acceptance-'));
  t.after(() => removeFixturePath(root, { recursive: true, force: true }));
  const installRoot = join(root, 'install spaces % # \u6d4b\u8bd5');
  const dshHome = join(root, 'home');
  const profile = join(dshHome, 'profiles', 'desktop');
  const lock = JSON.parse(readFileSync(new URL('../deployments/windows-copilot.lock.json', import.meta.url), 'utf8'));
  // This fixture deliberately exercises the legacy .5 physical contract even
  // after the reviewed deployment lock advances to the genuine .6 ASAR release.
  lock.components.desktop.version = '0.1.5-synthetic-local.1';
  lock.components.desktop.releaseChannel.version = '0.1.5-synthetic-local.1';
  lock.components.desktop.releaseChannel.upstreamVersion = '0.1.5-rc.2';
  lock.components.desktop.installedRuntimeDescriptor.relativePath = 'resources/dsh/desktop-runtime.json';
  const bytes = 'synthetic archive for the filesystem-only test; payload attestation is separate';
  const artifact = lock.components.copilotIntegration.package.artifact;
  artifact.size = Buffer.byteLength(bytes);
  artifact.sha256 = hash(bytes);
  artifact.integrity = `sha512-${hash(bytes, 'sha512', 'base64')}`;
  const checksum = artifact.checksumManifest;
  const source = { schemaVersion: 1, type: 'githubRelease', owner: 'cloga', repo: 'dsh-github-copilot',
    tag: artifact.releaseTag, asset: artifact.name, assetId: artifact.assetId, packageName: 'dsh-github-copilot',
    version: lock.components.copilotIntegration.package.version, size: artifact.size, sha256: artifact.sha256,
    integrity: artifact.integrity, targetCommit: lock.components.copilotIntegration.source.commit,
    dependencyRegistry,
    checksumManifest: { format: 'sha256sums', asset: checksum.name, assetId: checksum.assetId,
      url: checksum.url, size: checksum.size, sha256: checksum.sha256 } };
  const plan = { schemaVersion: 1, mode: 'exact', plugins: [{ required: true, source }] };
  const receiptCapability = { id: 'desktopNativeVerifiedRelease', schemaVersion: 1, sourceSchemaVersion: 1, receiptSchemaVersion: 1 };
  const capability = { id: 'desktopNativePluginProvisioning', schemaVersion: 1, planSchemaVersion: 1,
    stateSchemaVersion: 1, pluginCapability: receiptCapability };
  const planSha256 = hash(JSON.stringify(plan));
  lock.components.desktop.releaseChannel.managedCapability.provisioning = { capability, planSha256 };
  lock.components.desktop.releaseChannel.nativeProvisioning.plan.planSha256 = planSha256;
  const receipt = { schemaVersion: 1, capability: receiptCapability, source, releaseId: artifact.releaseId,
    assetId: artifact.assetId, packageName: source.packageName, version: source.version,
    artifactSha256: artifact.sha256, states: { staged: true, health: 'passed', activated: true, rolledBack: false, verified: true } };
  const state = { schemaVersion: 1, capability, planSha256, composition: 'active',
    plugins: [{ name: source.packageName, version: source.version, required: true, status: 'active', source, receipt }],
    removed: [], rolledBack: false, verified: true };
  write(join(installRoot, 'resources', 'managed-update', 'capability.json'), lock.components.desktop.releaseChannel.managedCapability);
  const helperBytes = 'synthetic helper, never executed';
  lock.components.desktop.releaseChannel.nativeProvisioning.helperSha256 = hash(helperBytes);
  write(join(installRoot, 'resources', 'managed-update', 'helper.mjs'), helperBytes);
  write(join(installRoot, 'resources', 'desktop-provisioning', 'plan.json'), plan);
  write(join(profile, 'desktop-plugin-provisioning-state.json'), state);
  write(join(profile, 'desktop-plugin-receipts.json'), { schemaVersion: 1, receipts: { [source.packageName]: receipt } });
  write(join(profile, 'package.json'), { name: '@deepseek-ai/dsh-desktop-runtime', private: true, version: '0.1.5-rc.2',
    dependencies: { [source.packageName]: `file:.desktop-plugin-artifacts/${artifact.sha256}.tgz` },
    dsh: { profile: { bundles: ['@deepseek-ai/dsh-base', '@deepseek-ai/dsh-web-app', source.packageName] } } });
  write(join(profile, '.desktop-plugin-artifacts', `${artifact.sha256}.tgz`), bytes);
  write(join(profile, 'node_modules', source.packageName, 'package.json'), { name: source.packageName, version: source.version });
  const runtimeFile = 'synthetic host entry';
  const runtimePath = 'node_modules/@deepseek-ai/dsh-desktop-host/lib/index.js';
  const runtimeFiles = { [runtimePath]: runtimeFile,
    'node_modules/@deepseek-ai/dsh-desktop-host/package.json': JSON.stringify({ name: '@deepseek-ai/dsh-desktop-host', version: '0.1.5-rc.2' }) };
  if (withPolicy) {
    runtimeFiles['node_modules/@deepseek-ai/dsh-desktop-host/register-module-resolution-policy.mjs'] = 'synthetic policy; never imported';
  }
  for (const name of ['@deepseek-ai/dsh-authorization', '@deepseek-ai/schemastery']) {
    runtimeFiles[`node_modules/${name}/package.json`] = JSON.stringify({ name, version: '1.0.0', main: 'lib/index.js' });
    runtimeFiles[`node_modules/${name}/lib/index.js`] = 'export const fixture = true;';
  }
  for (const [path, body] of Object.entries(runtimeFiles)) write(join(installRoot, 'resources', 'dsh', path), body);
  symlinkSync(join(installRoot, 'resources', 'dsh', 'node_modules', '@deepseek-ai'),
    join(profile, 'node_modules', '@deepseek-ai'), 'junction');
  const descriptor = { schemaVersion: 1, release: { version: '0.1.5-rc.2' }, platform: 'win32', arch: 'x64', sharedPackages: [],
    files: Object.entries(runtimeFiles).sort(([a], [b]) => a < b ? -1 : a > b ? 1 : 0)
      .map(([path, body]) => ({ path, bytes: Buffer.byteLength(body), sha256: hash(body), executable: false })) };
  write(join(installRoot, 'resources', 'dsh', 'desktop-runtime.json'), descriptor);
  lock.components.desktop.installedRuntimeDescriptor.sha256 = hash(JSON.stringify(descriptor));
  return { lock, installRoot, dshHome, profile, source, state, receipt, plan };
}

test('native file acceptance binds exact inventory without claiming live functionality', (t) => {
  const input = fixture(t);
  const result = verifyNativeDesktopFiles(input);
  assert.equal(result.valid, true);
  assert.equal(result.mutated, false);
  assert.equal(result.functional.valid, false);
  assert.equal(result.functional.status, 'manual-verification-required');
  assert.equal(result.functional.modelResponseVerified, false);
});

test('native registry follows the exact lock-attested plan rather than a fixed endpoint', (t) => {
  const input = fixture(t, 'https://packagefeedproxy.microsoft.io/npm/');
  assert.equal(verifyNativeDesktopFiles(input).valid, true);
});

for (const registry of [null, '']) {
  test(`native registry cannot be ${JSON.stringify(registry)} even in an attested plan`, (t) => {
    const input = fixture(t, registry);
    assert.equal(verifyNativeDesktopFiles(input).provisioning.reason, 'native-plan-source-mismatch');
  });
}

for (const [name, change, expected] of [
  ['missing evidence', (f) => removeFixturePath(join(f.profile, 'desktop-plugin-receipts.json')), 'native-evidence-missing'],
  ['wrong receipt release', (f) => {
    f.receipt.releaseId++;
    write(join(f.profile, 'desktop-plugin-receipts.json'), { schemaVersion: 1, receipts: { [f.source.packageName]: f.receipt } });
  }, 'native-state-receipt-mismatch'],
  ['string boolean', (f) => {
    f.state.verified = 'true';
    write(join(f.profile, 'desktop-plugin-provisioning-state.json'), f.state);
  }, 'native-provisioning-state-invalid'],
  ['wrong plan source', (f) => {
    f.plan.plugins[0].source.version = '0.4.0-alpha.18';
    write(join(f.installRoot, 'resources', 'desktop-provisioning', 'plan.json'), f.plan);
  }, 'native-plan-hash-mismatch'],
  ['substituted registry', (f) => {
    f.plan.plugins[0].source.dependencyRegistry = 'https://unapproved.invalid/npm/';
    write(join(f.installRoot, 'resources', 'desktop-provisioning', 'plan.json'), f.plan);
  }, 'native-plan-hash-mismatch'],
  ['registry substituted in plan and capability without release plan attestation', (f) => {
    f.plan.plugins[0].source.dependencyRegistry = 'https://unapproved.invalid/npm/';
    f.lock.components.desktop.releaseChannel.managedCapability.provisioning.planSha256 = hash(JSON.stringify(f.plan));
    write(join(f.installRoot, 'resources', 'desktop-provisioning', 'plan.json'), f.plan);
    write(join(f.installRoot, 'resources', 'managed-update', 'capability.json'),
      f.lock.components.desktop.releaseChannel.managedCapability);
  }, 'native-plan-hash-mismatch'],
  ['receipt registry differs from attested plan even when state copies that receipt', (f) => {
    f.receipt.source = { ...f.source, dependencyRegistry: 'https://unapproved.invalid/npm/' };
    write(join(f.profile, 'desktop-plugin-receipts.json'), { schemaVersion: 1, receipts: { [f.source.packageName]: f.receipt } });
    write(join(f.profile, 'desktop-plugin-provisioning-state.json'), f.state);
  }, 'native-receipt-invalid'],
  ['state registry differs from attested plan', (f) => {
    f.state.plugins[0].source = { ...f.source, dependencyRegistry: 'https://unapproved.invalid/npm/' };
    write(join(f.profile, 'desktop-plugin-provisioning-state.json'), f.state);
  }, 'native-state-receipt-mismatch'],
  ['state plan digest differs from attested plan', (f) => {
    f.state.planSha256 = '0'.repeat(64);
    write(join(f.profile, 'desktop-plugin-provisioning-state.json'), f.state);
  }, 'native-provisioning-state-invalid'],
  ['corrupt local artifact', (f) => write(join(f.profile, '.desktop-plugin-artifacts', `${f.source.sha256}.tgz`), 'corrupt'), 'native-local-artifact-mismatch'],
  ['corrupt installed helper', (f) => write(join(f.installRoot, 'resources', 'managed-update', 'helper.mjs'), 'corrupt'), 'native-helper-hash-mismatch'],
  ['profile disabled', (f) => {
    const path = join(f.profile, 'package.json');
    const manifest = JSON.parse(readFileSync(path, 'utf8'));
    manifest.dsh.profile.bundles.pop();
    write(path, manifest);
  }, 'native-profile-composition-mismatch'],
  ['unlocked capability', (f) => { delete f.lock.components.desktop.releaseChannel.managedCapability.provisioning; }, 'native-provisioning-capability-not-locked'],
]) {
  test(`native provisioning rejects ${name}`, (t) => {
    const input = fixture(t);
    change(input);
    const result = verifyNativeDesktopFiles(input);
    assert.equal(result.valid, false);
    assert.equal(result.provisioning.reason, expected);
    assert.equal(result.functional.valid, false);
  });
}

test('runtime inventory detects added files rather than trusting the descriptor hash alone', (t) => {
  const input = fixture(t);
  write(join(input.installRoot, 'resources', 'dsh', 'extra.js'), 'extra');
  const result = verifyNativeDesktopFiles(input);
  assert.equal(result.runtime.reason, 'native-runtime-tree-mismatch');
});

test('only attested runtime inventory selects the exact Node preload file URL', (t) => {
  const input = fixture(t, undefined, true);
  const policy = join(input.installRoot, 'resources', 'dsh', 'node_modules', '@deepseek-ai',
    'dsh-desktop-host', 'register-module-resolution-policy.mjs');
  const runtime = verifyNativeDesktopFiles(input).runtime;
  assert.equal(runtime.valid, true);
  assert.equal(runtime.moduleResolutionPolicyUrl, pathToFileURL(policy).href);
  assert.match(runtime.moduleResolutionPolicyUrl, /%20/);
  assert.match(runtime.moduleResolutionPolicyUrl, /%25/);
  assert.match(runtime.moduleResolutionPolicyUrl, /%23/);
  assert.match(runtime.moduleResolutionPolicyUrl, /%E6%B5%8B%E8%AF%95/);
  write(policy, 'tampered');
  const changed = verifyNativeDesktopFiles(input).runtime;
  assert.equal(changed.valid, false);
  assert.equal(changed.moduleResolutionPolicyUrl, undefined);
});

test('an extra policy file cannot enable preload mode for the old inventory', (t) => {
  const input = fixture(t);
  assert.equal(verifyNativeDesktopFiles(input).runtime.moduleResolutionPolicyUrl, null);
  write(join(input.installRoot, 'resources', 'dsh', 'node_modules', '@deepseek-ai',
    'dsh-desktop-host', 'register-module-resolution-policy.mjs'), 'unattested');
  const runtime = verifyNativeDesktopFiles(input).runtime;
  assert.equal(runtime.reason, 'native-runtime-tree-mismatch');
  assert.equal(runtime.moduleResolutionPolicyUrl, undefined);
});

test('native inventory rejects a private copy of a required Host peer even at the same version', (t) => {
  const input = fixture(t);
  const peerRoot = join(input.profile, 'node_modules', input.source.packageName, 'node_modules', '@deepseek-ai', 'dsh-authorization');
  write(join(peerRoot, 'package.json'), { name: '@deepseek-ai/dsh-authorization', version: '1.0.0', main: 'lib/index.js' });
  write(join(peerRoot, 'lib', 'index.js'), 'export const fixture = true;');
  assert.equal(verifyNativeDesktopFiles(input).provisioning.reason, 'native-shared-peer-resolution-mismatch');
});

test('canonical plan identity is independent of serialized source key order', (t) => {
  const input = fixture(t);
  input.plan.plugins[0].source = Object.fromEntries(Object.entries(input.source).reverse());
  write(join(input.installRoot, 'resources', 'desktop-provisioning', 'plan.json'), input.plan);
  assert.equal(verifyNativeDesktopFiles(input).valid, true);
});

test('raw parser errors and file contents never enter evidence output', (t) => {
  const input = fixture(t);
  write(join(input.profile, 'desktop-plugin-receipts.json'), 'fixture-private-do-not-report');
  const result = verifyNativeDesktopFiles(input);
  assert.equal(result.provisioning.reason, 'native-evidence-unreadable');
  assert.ok(!JSON.stringify(result).includes('fixture-private'));
});

// Generated SYNTHETIC LOCAL integrity fixtures, not functional runtime/release proof.
const syntheticRoot = fileURLToPath(new URL('./fixtures/native-asar-synthetic/', import.meta.url));
function asarFixture(t) {
  const input = fixture(t);
  unlinkSync(join(input.profile, 'node_modules', '@deepseek-ai'));
  removeFixturePath(join(input.installRoot, 'resources', 'dsh'), { recursive: true });
  writeFileSync(join(input.installRoot, 'resources', 'app.asar'), readFileSync(join(syntheticRoot, 'app.asar')));
  const native = 'app.asar.unpacked/dsh/node_modules/fixture-native/fixture.node';
  mkdirSync(dirname(join(input.installRoot, 'resources', native)), { recursive: true });
  writeFileSync(join(input.installRoot, 'resources', native), readFileSync(join(syntheticRoot, native)));
  assert.deepEqual(readFileSync(join(input.installRoot, 'resources/app.asar.unpacked/dsh/node_modules/fixture-native/fixture.node')),
    readFileSync(join(syntheticRoot, 'app.asar.unpacked/dsh/node_modules/fixture-native/fixture.node')));
  const identity = JSON.parse(readFileSync(join(syntheticRoot, 'identity.json'), 'utf8'));
  assert.equal(identity.syntheticOnly, true); assert.equal(identity.runtimeProof, false);
  input.lock.components.desktop.installedRuntimeDescriptor = { relativePath: 'resources\\app.asar\\dsh\\desktop-runtime.json', sha256: identity.descriptorSha256 };
  input.lock.components.desktop.version = identity.version;
  input.lock.components.desktop.releaseChannel.version = identity.version;
  input.lock.components.desktop.releaseChannel.upstreamVersion = identity.version;
  const executable = join(input.installRoot, input.lock.components.desktop.installedExecutable.relativePath);
  write(executable, 'SYNTHETIC CARRIER BYTES - NEVER EXECUTED');
  input.lock.components.desktop.installedExecutable.sha256 = hash(readFileSync(executable));
  input.diagnosticRoot = dirname(input.installRoot);
  return input;
}
function noChild(t) {
  let count = 0;
  t.mock.method(childProcess, 'spawnSync', () => { count++; throw new Error('unexpected-launch'); });
  syncBuiltinESMExports();
  t.after(() => { t.mock.restoreAll(); syncBuiltinESMExports(); assert.equal(count, 0, 'invalid evidence must launch zero children'); });
}
const archivePath = f => join(f.installRoot, 'resources', 'app.asar');
const sidecarPath = f => join(f.installRoot, 'resources', 'app.asar.unpacked', 'dsh');

test('synthetic ASAR passes ONLY header/sidecar integrity, not runtime proof', t => {
  const f = asarFixture(t); noChild(t);
  const result = preflightAsar(f.lock, f.installRoot);
  assert.equal(result.unpackedCount, 1); assert.equal(result.descriptor.files.length, 18);
  assert.equal(result.archiveSha256, hash(readFileSync(archivePath(f))));
  assert.equal(result.runtimeRoot, join(archivePath(f), 'dsh'));
  for (const encoded of ['%20', '%25', '%23', '%E6%B5%8B%E8%AF%95']) assert.ok(result.moduleResolutionPolicyUrl.includes(encoded));
});

for (const [name, mutate, expected] of [
  ['wrong exe hash', f => { f.lock.components.desktop.installedExecutable.sha256 = '0'.repeat(64); }, 'native-carrier-hash-mismatch'],
  ['missing exe', f => removeFixturePath(join(f.installRoot, f.lock.components.desktop.installedExecutable.relativePath)), 'native-evidence-missing'],
  ['traversed exe', f => { f.lock.components.desktop.installedExecutable.relativePath = '../other.exe'; }, 'native-invalid-relative-path'],
  ['absolute exe', f => { f.lock.components.desktop.installedExecutable.relativePath = 'C:/other.exe'; }, 'native-invalid-relative-path'],
  ['ADS exe', f => { f.lock.components.desktop.installedExecutable.relativePath = 'carrier.exe:secret'; }, 'native-invalid-relative-path'],
  ['unknown layout no fallback', f => { f.lock.components.desktop.installedRuntimeDescriptor.relativePath = 'resources/other/desktop-runtime.json'; }, 'native-runtime-layout-unsupported'],
  ['traversed layout', f => { f.lock.components.desktop.installedRuntimeDescriptor.relativePath = 'resources/app.asar/dsh/../desktop-runtime.json'; }, 'native-runtime-layout-unsupported'],
  ['descriptor hash', f => { f.lock.components.desktop.installedRuntimeDescriptor.sha256 = '0'.repeat(64); }, 'native-runtime-descriptor-mismatch'],
  ['release drift', f => { f.lock.components.desktop.releaseChannel.upstreamVersion = '0.1.6-wrong'; }, 'native-runtime-descriptor-invalid'],
  ['mixed legacy version with ASAR layout', f => { f.lock.components.desktop.releaseChannel.upstreamVersion = '0.1.5-rc.2'; }, 'native-runtime-layout-unsupported'],
  ['truncated header', f => writeFileSync(archivePath(f), Buffer.from([4, 0, 0])), 'native-asar-header-invalid'],
  ['oversized header', f => { const b = readFileSync(archivePath(f)); b.writeUInt32LE(limits.header + 4, 4); writeFileSync(archivePath(f), b); }, 'native-asar-header-limit'],
  ['header beyond archive', f => { const b = readFileSync(archivePath(f)); b.writeUInt32LE(b.length * 4, 4); writeFileSync(archivePath(f), b); }, 'native-asar-header-limit'],
  ['malformed parser', f => { const b = readFileSync(archivePath(f)); b[16] = 0x21; writeFileSync(archivePath(f), b); }, 'native-evidence-unreadable'],
  ['missing and extra packed path', f => { const b = readFileSync(archivePath(f)); const at = b.indexOf(Buffer.from('"index.js"')); assert.ok(at > 0); b.write('"other.js"', at); writeFileSync(archivePath(f), b); }, 'native-asar-header-inventory-mismatch'],
  ['header traversal path', f => { const b = readFileSync(archivePath(f)); const at = b.indexOf(Buffer.from('"lib"')); assert.ok(at > 0); b.write('".. "', at); writeFileSync(archivePath(f), b); }, 'native-invalid-relative-path'],
  ['orphan unpacked native', f => write(join(sidecarPath(f), 'orphan.node'), 'invisible virtually'), 'native-asar-sidecar-mismatch'],
  ['orphan unpacked ordinary file', f => write(join(sidecarPath(f), 'orphan.txt'), 'invisible virtually'), 'native-asar-sidecar-mismatch'],
  ['packed-only shadow', f => write(join(sidecarPath(f), 'node_modules/@deepseek-ai/dsh/package.json'), 'shadow'), 'native-asar-sidecar-mismatch'],
  ['outside sidecar scope', f => write(join(f.installRoot, 'resources/app.asar.unpacked/other/extra.node'), 'outside'), 'native-asar-sidecar-outside-runtime'],
  ['missing unpacked file', f => removeFixturePath(join(sidecarPath(f), 'node_modules/fixture-native/fixture.node')), 'native-asar-sidecar-mismatch'],
  ['missing sidecar', f => removeFixturePath(join(f.installRoot, 'resources/app.asar.unpacked'), { recursive: true }), 'native-asar-sidecar-mismatch'],
  ['same-size unpacked change', f => { const p = join(sidecarPath(f), 'node_modules/fixture-native/fixture.node'); const b = readFileSync(p); b[0] ^= 1; writeFileSync(p, b); }, 'native-asar-sidecar-mismatch'],
  ['sidecar junction', f => { const p = join(sidecarPath(f), 'node_modules/fixture-native'); removeFixturePath(p, { recursive: true }); symlinkSync(f.profile, p, 'junction'); }, 'native-reparse-or-inventory-limit'],
  ['dangling sidecar junction', f => { const p = join(f.installRoot, 'resources/app.asar.unpacked'); removeFixturePath(p, { recursive: true }); symlinkSync(join(f.diagnosticRoot, 'absent'), p, 'junction'); }, 'native-reparse-path'],
  ['dangling dsh junction', f => { const p = sidecarPath(f); removeFixturePath(p, { recursive: true }); symlinkSync(join(f.diagnosticRoot, 'absent'), p, 'junction'); }, 'native-reparse-path'],
  ['resources junction', f => { const p = join(f.installRoot, 'resources'); const target = join(f.diagnosticRoot, 'resources-target'); renameSync(p, target); symlinkSync(target, p, 'junction'); }, 'native-reparse-path'],
  ['UNC root', f => { f.installRoot = '\\\\server\\share\\install'; }, 'native-invalid-physical-path'],
]) {
  test(`ASAR rejects ${name} BEFORE child launch (synthetic)`, t => {
    const f = asarFixture(t); noChild(t); mutate(f);
    const result = verifyNativeDesktopFiles(f);
    assert.equal(result.valid, false); assert.equal(result.runtime.reason, expected);
    assert.equal(result.functional.modelResponseVerified, false);
  });
}

for (const [name, mutate] of [
  ['link', h => { h.header.files.dsh.files.bad = { link: 'outside' }; }],
  ['case alias', h => { h.header.files.DSH = h.header.files.dsh; }],
  ['traversal', h => { h.header.files.dsh.files['..'] = { size: 0, offset: '0' }; }],
  ['inherited unpack mismatch', h => { const dir = h.header.files.dsh.files.node_modules.files['fixture-native']; dir.unpacked = true; delete dir.files['fixture.node'].unpacked; }],
  ['negative size', h => { h.header.files.dsh.files['desktop-runtime.json'].size = -1; }],
  ['unsafe offset', h => { h.header.files.dsh.files['desktop-runtime.json'].offset = '9007199254740992'; }],
]) {
  test(`maintained header rejects ${name} (synthetic metadata)`, () => {
    const archive = join(syntheticRoot, 'app.asar'); const raw = asarReader.getRawHeader(archive); mutate(raw);
    assert.throws(() => headerRuntimeInventory(raw, readFileSync(archive).length), /native-/);
  });
}

test('consistent inherited unpack flags agree with reader semantics', () => {
  const archive = join(syntheticRoot, 'app.asar'); const raw = asarReader.getRawHeader(archive);
  raw.header.files.dsh.files.node_modules.files['fixture-native'].unpacked = true;
  assert.equal(headerRuntimeInventory(raw, readFileSync(archive).length).filter(f => f.unpacked).length, 1);
});

for (const [name, mutate] of [
  ['duplicate', d => d.files.push(d.files[0])],
  ['case alias', d => d.files.push({ ...d.files[0], path: d.files[0].path.toUpperCase() })],
  ['traversal', d => { d.files[0].path = '../outside'; }],
  ['missing shared identity', d => { d.sharedPackages = d.sharedPackages.filter(p => p.name !== '@deepseek-ai/dsh'); }],
  ['protocol', d => { d.release.hostProtocolVersion = 0; }],
  ['version', d => { d.release.nodeVersion = 'not-a-version'; }],
  ['unsafe size', d => { d.files[0].bytes = Number.MAX_SAFE_INTEGER; }],
]) {
  test(`strict descriptor rejects ${name} (synthetic)`, t => {
    const f = asarFixture(t); const snapshot = preflightAsar(f.lock, f.installRoot);
    const d = structuredClone(snapshot.descriptor); mutate(d); const bytes = Buffer.from(JSON.stringify(d));
    assert.throws(() => validateDescriptor(bytes, hash(bytes), snapshot.descriptor.release.version), /native-/);
  });
}

// Rework only a temporary SYNTHETIC descriptor, preserving the archive envelope.
// This is validator/pre-launch coverage, never alpha.2 package or runtime proof.
for (const [version, protocol, valid] of [
  ['0.1.6-alpha.1', 3, true], ['0.1.6-alpha.1', 4, false],
  ['0.1.6-alpha.2', 4, true], ['0.1.6-alpha.2', 3, false],
  ['0.1.6-alpha.3', 4, false], ['0.1.6-alpha.2.cloga1', 4, false],
  ['0.1.6-alpha.2+build', 4, false],
  ['0.1.6-synthetic-local.1', 3, true], ['0.1.6-synthetic-local.1', 4, false],
  ...[undefined, '4', null, false, 4.5, {}, [4]].map(protocol => ['0.1.6-alpha.2', protocol, false]),
]) {
  test(`exact Core ${version}/protocol ${JSON.stringify(protocol)} ${valid ? 'passes integrity only' : 'rejects before launch'} (synthetic)`, t => {
    const f = asarFixture(t); noChild(t);
    const archive = archivePath(f); const raw = asarReader.getRawHeader(archive);
    const entry = raw.header.files.dsh.files['desktop-runtime.json'];
    const descriptor = JSON.parse(asarReader.extractFile(archive, 'dsh/desktop-runtime.json', false));
    descriptor.release.version = version; descriptor.release.hostProtocolVersion = protocol;
    for (const shared of descriptor.sharedPackages) {
      if (['@deepseek-ai/dsh', '@deepseek-ai/dsh-desktop-host'].includes(shared.name)) shared.version = version;
    }
    const bytes = Buffer.from(JSON.stringify(descriptor));
    assert.ok(bytes.length <= entry.size);
    const padded = Buffer.alloc(entry.size, ' '); bytes.copy(padded);
    const contents = readFileSync(archive); padded.copy(contents, 8 + raw.headerSize + Number(entry.offset));
    writeFileSync(archive, contents); asarReader.uncache(archive);
    f.lock.components.desktop.releaseChannel.upstreamVersion = version;
    f.lock.components.desktop.installedRuntimeDescriptor.sha256 = hash(padded);
    if (valid) {
      assert.equal(validateDescriptor(padded, hash(padded), version).release.hostProtocolVersion, protocol);
      assert.equal(preflightAsar(f.lock, f.installRoot).descriptor.release.hostProtocolVersion, protocol);
      // Neither a different independently pinned version nor hash may select this descriptor.
      assert.throws(() => validateDescriptor(padded, hash(padded), '0.1.6-mismatched'), /native-runtime-descriptor-invalid/);
      assert.throws(() => validateDescriptor(padded, '0'.repeat(64), version), /native-runtime-descriptor-mismatch/);
      f.lock.components.desktop.releaseChannel.upstreamVersion = '0.1.6-mismatched';
      assert.equal(verifyNativeDesktopFiles(f).runtime.reason, 'native-runtime-descriptor-invalid');
      f.lock.components.desktop.releaseChannel.upstreamVersion = version;
      f.lock.components.desktop.installedRuntimeDescriptor.sha256 = '0'.repeat(64);
      assert.equal(verifyNativeDesktopFiles(f).runtime.reason, 'native-runtime-descriptor-mismatch');
    } else {
      assert.throws(() => validateDescriptor(padded, hash(padded), version), /native-runtime-descriptor-invalid/);
      const result = verifyNativeDesktopFiles(f);
      assert.equal(result.valid, false); assert.equal(result.runtime.reason, 'native-runtime-descriptor-invalid');
      assert.equal(result.functional.modelResponseVerified, false);
    }
  });
}

test('preflight rereads header after archive replacement, never cached metadata', t => {
  const f = asarFixture(t); preflightAsar(f.lock, f.installRoot);
  const b = readFileSync(archivePath(f)); b.writeUInt32LE(0xffffffff, 4); writeFileSync(archivePath(f), b);
  assert.throws(() => preflightAsar(f.lock, f.installRoot), /native-asar-header-limit/);
});

test('Node-mode environment allowlist excludes case variants and secrets', t => {
  const f = asarFixture(t);
  const env = probeEnvironment(f.diagnosticRoot, { NODE_OPTIONS: 'secret-sentinel', node_path: 'secret-sentinel',
    Electron_No_Asar: 'secret-sentinel', DSH_HOME: 'secret-sentinel', DSH_MODEL: 'secret-sentinel',
    OPENAI_API_KEY: 'secret-sentinel', GH_TOKEN: 'secret-sentinel', npm_config_registry: 'secret-sentinel', PATH: 'secret-sentinel' });
  assert.equal(env.ELECTRON_RUN_AS_NODE, '1'); assert.equal(env.TEMP, f.diagnosticRoot);
  assert.ok(!JSON.stringify(env).includes('secret-sentinel'));
  assert.deepEqual(Object.keys(env).sort(), ['ELECTRON_RUN_AS_NODE', 'HOME', 'TEMP', 'TMP', 'USERPROFILE']);
});

for (const [name, childResult, expected] of [
  ['timeout', { error: { code: 'ETIMEDOUT' }, status: null }, 'native-probe-timeout'],
  ['unavailable Electron', { error: { code: 'ENOENT' }, status: null }, 'native-probe-failed'],
  ['nonzero', { status: 1, stdout: 'secret-sentinel', stderr: 'secret-sentinel' }, 'native-probe-failed'],
  ['noisy', { status: 0, stdout: 'log\n{}', stderr: '' }, 'native-probe-output-invalid'],
  ['truncated', { status: 0, stdout: '{', stderr: '' }, 'native-probe-output-invalid'],
  ['oversized', { status: 0, stdout: 'x'.repeat(limits.output + 1), stderr: '' }, 'native-probe-output-invalid'],
  ['stderr', { status: 0, stdout: '{}', stderr: 'secret-sentinel' }, 'native-probe-output-invalid'],
  ['unbound valid boolean', { status: 0, stdout: '{"valid":true}', stderr: '' }, 'native-probe-output-invalid'],
]) {
  test(`bounded protocol rejects ${name}; no ready claims (synthetic mock)`, t => {
    const f = asarFixture(t); let count = 0;
    t.mock.method(childProcess, 'spawnSync', (exe, args, options) => {
      count++; assert.equal(exe, join(f.installRoot, f.lock.components.desktop.installedExecutable.relativePath));
      assert.equal(options.shell, false); assert.equal(options.windowsHide, true);
      assert.equal(options.timeout, 30000); assert.equal(options.maxBuffer, limits.output);
      assert.equal(options.env.ELECTRON_RUN_AS_NODE, '1');
      assert.ok(args.includes('--max-old-space-size=512')); assert.ok(args.includes('--experimental-import-meta-resolve'));
      assert.ok(!args.includes('--import')); assert.equal(JSON.parse(options.input).profile, f.profile);
      return childResult;
    });
    syncBuiltinESMExports(); t.after(() => { t.mock.restoreAll(); syncBuiltinESMExports(); });
    const result = verifyNativeDesktopFiles(f);
    assert.equal(count, 1); assert.equal(result.valid, false); assert.equal(result.runtime.reason, expected);
    assert.ok(!JSON.stringify(result).includes('secret-sentinel'));
  });
}

test('mixed ASAR-era version cannot use legacy physical checks as fallback', t => {
  const f = fixture(t); noChild(t);
  f.lock.components.desktop.releaseChannel.upstreamVersion = '0.1.6-synthetic-local.1';
  assert.equal(verifyNativeDesktopFiles(f).runtime.reason, 'native-runtime-layout-unsupported');
});

test('plain Node is not an Electron carrier and cannot reach runtime imports', async () => {
  await assert.rejects(electronProbe({ schemaVersion: 1 }), /native-probe-carrier-invalid/);
});

for (const [name, mutate] of [
  ['missing disposal', o => { o.resolverDisposed = false; }],
  ['unresolved peers', o => { o.peerCount = 1; }],
  ['wrong file count', o => { o.fileCount++; }],
  ['wrong archive correlation', o => { o.archiveSha256 = '0'.repeat(64); }],
  ['wrong descriptor correlation', o => { o.descriptorSha256 = '0'.repeat(64); }],
  ['CJS-only evidence', o => { o.mode = 'metadata-cjs'; }],
  ['extra output field', o => { o.untrusted = true; }],
]) {
  test(`synthetic child claim rejected for ${name}, not resolver success evidence`, t => {
    const f = asarFixture(t);
    t.mock.method(childProcess, 'spawnSync', (exe, args, options) => {
      const input = JSON.parse(options.input);
      const output = { schemaVersion: 1, valid: true, mode: 'metadata-cjs-esm', resolverDisposed: true,
        peerCount: 2, fileCount: 18, archiveSha256: input.archiveSha256, descriptorSha256: input.descriptorSha256 };
      mutate(output); return { status: 0, stdout: JSON.stringify(output), stderr: '' };
    });
    syncBuiltinESMExports(); t.after(() => { t.mock.restoreAll(); syncBuiltinESMExports(); });
    const result = verifyNativeDesktopFiles(f);
    assert.equal(result.valid, false); assert.equal(result.runtime.reason, 'native-probe-output-invalid');
  });
}

test('concurrent carrier replacement invalidates even a synthetic correlated child claim', t => {
  const f = asarFixture(t);
  t.mock.method(childProcess, 'spawnSync', (exe, args, options) => {
    const input = JSON.parse(options.input); writeFileSync(exe, 'concurrent replacement');
    return { status: 0, stderr: '', stdout: JSON.stringify({ schemaVersion: 1, valid: true,
      mode: 'metadata-cjs-esm', resolverDisposed: true, peerCount: 2, fileCount: 18,
      archiveSha256: input.archiveSha256, descriptorSha256: input.descriptorSha256 }) };
  });
  syncBuiltinESMExports(); t.after(() => { t.mock.restoreAll(); syncBuiltinESMExports(); });
  const result = verifyNativeDesktopFiles(f);
  assert.equal(result.valid, false); assert.equal(result.runtime.reason, 'native-carrier-hash-mismatch');
});

function changeProfile(f, change) {
  const path = join(f.profile, 'package.json'); const manifest = JSON.parse(readFileSync(path)); change(manifest); write(path, manifest);
}
function explicitOwners(f, owner = 'release') {
  const path = join(f.profile, 'desktop-plugin-receipts.json'); const store = JSON.parse(readFileSync(path));
  store.owners = Object.fromEntries(Object.keys(store.receipts).map(name => [name, owner])); write(path, store);
}
function userReceipt(f, owner = 'user') {
  const name = 'synthetic-user-extra'; const bytes = 'synthetic extra bytes, not a package';
  const receipt = structuredClone(f.receipt);
  Object.assign(receipt.source, { owner: 'fixture', repo: name, tag: 'v1.0.0', asset: 'extra.tgz', assetId: 42,
    packageName: name, version: '1.0.0', size: Buffer.byteLength(bytes), sha256: hash(bytes),
    integrity: `sha512-${hash(bytes, 'sha512', 'base64')}`, targetCommit: 'b'.repeat(40) });
  receipt.source.checksumManifest.url = `https://github.com/fixture/${name}/releases/download/v1.0.0/SHA256SUMS`;
  Object.assign(receipt, { releaseId: 43, assetId: 42, packageName: name, version: '1.0.0', artifactSha256: receipt.source.sha256 });
  const path = join(f.profile, 'desktop-plugin-receipts.json'); const store = JSON.parse(readFileSync(path));
  store.receipts[name] = receipt;
  if (owner !== null) store.owners = { [f.source.packageName]: 'user', [name]: owner };
  write(path, store);
  write(join(f.profile, '.desktop-plugin-artifacts', `${receipt.artifactSha256}.tgz`), bytes);
  changeProfile(f, manifest => { manifest.dependencies[name] = `file:.desktop-plugin-artifacts/${receipt.artifactSha256}.tgz`;
    manifest.dsh.profile.bundles.splice(2, 0, name); });
  return receipt;
}

for (const [name, change, owner] of [
  ['explicit required user owner', f => explicitOwners(f, 'user'), 'user'],
  ['user-verified receipt before required bundle', f => userReceipt(f), 'user'],
  ['legacy extra receipt infers only required release owner', f => userReceipt(f, null), 'release'],
  ['registry extras preserve tail order', f => changeProfile(f, m => { m.dependencies['z-user'] = '1.2.3'; m.dependencies['a-user'] = '2.0.0';
    m.dsh.profile.bundles.splice(2, 0, 'z-user'); m.dsh.profile.bundles.push('a-user'); }), 'release'],
  ['snapshot metadata is not archive-health proof', f => {
    changeProfile(f, m => { m.dependencies['user-snapshot'] = `file:.desktop-plugin-artifacts/${'c'.repeat(64)}.tgz`; m.dsh.profile.bundles.push('user-snapshot'); });
    write(join(f.profile, 'desktop-plugin-package-locks.json'), { schemaVersion: 1, packages: { 'user-snapshot': {
      packageName: 'user-snapshot', version: '1.0.0', spec: 'github:fixture/snapshot#main', resolved: 'git+https://github.com/fixture/snapshot.git',
      sha256: 'c'.repeat(64), integrity: `sha512-${hash('synthetic snapshot metadata', 'sha512', 'base64')}` } } });
  }, 'release'],
  ['corrupt user archive bytes remain explicitly unattested', f => { const r = userReceipt(f); write(join(f.profile, '.desktop-plugin-artifacts', `${r.artifactSha256}.tgz`), 'corrupt inert extra'); }, 'user'],
]) {
  test(`.6 metadata permits ${name}, but no synthetic runtime success claimed`, t => {
    const f = asarFixture(t); change(f);
    const metadata = readNativeProfileMetadata(f.profile, f.plan);
    assert.equal(metadata.requiredPluginOwner, owner); assert.equal(metadata.userExtras.contentsAttested, false);
    let calls = 0;
    t.mock.method(childProcess, 'spawnSync', (exe, args, options) => {
      calls++; const input = JSON.parse(options.input);
      assert.equal(input.profileMetadataSha256, metadata.snapshotSha256); assert.equal(input.planSha256, metadata.planSha256);
      return { status: 1, stderr: '', stdout: '{"schemaVersion":1,"valid":false,"reason":"native-runtime-api-invalid"}' };
    });
    syncBuiltinESMExports(); t.after(() => { t.mock.restoreAll(); syncBuiltinESMExports(); });
    const result = verifyNativeDesktopFiles(f);
    assert.equal(calls, 1); assert.equal(result.valid, false); assert.equal(result.runtime.reason, 'native-runtime-api-invalid');
    assert.equal(result.functional.modelResponseVerified, false);
  });
}

for (const [name, change, reason] of [
  ['off-plan release-owned receipt', f => userReceipt(f, 'release'), 'native-release-owned-extra'],
  ['missing required owner', f => { explicitOwners(f); const path = join(f.profile, 'desktop-plugin-receipts.json'); const s = JSON.parse(readFileSync(path)); s.owners = {}; write(path, s); }, 'native-receipt-owner-invalid'],
  ['invalid owner value', f => explicitOwners(f, 'trusted'), 'native-receipt-owner-invalid'],
  ['user receipt forged healthy state', f => { userReceipt(f); const path = join(f.profile, 'desktop-plugin-receipts.json'); const s = JSON.parse(readFileSync(path)); s.receipts['synthetic-user-extra'].states.verified = false; write(path, s); }, 'native-receipt-invalid'],
  ['required disabled', f => changeProfile(f, m => { m.dsh.profile.bundles.pop(); }), 'native-profile-composition-mismatch'],
  ['built-in prefix reordered', f => changeProfile(f, m => { [m.dsh.profile.bundles[0], m.dsh.profile.bundles[1]] = [m.dsh.profile.bundles[1], m.dsh.profile.bundles[0]]; }), 'native-profile-composition-mismatch'],
  ['duplicate enabled bundle', f => changeProfile(f, m => { m.dsh.profile.bundles.push(m.dsh.profile.bundles[2]); }), 'native-profile-composition-mismatch'],
  ['missing user verified backing', f => { const r = userReceipt(f); unlinkSync(join(f.profile, '.desktop-plugin-artifacts', `${r.artifactSha256}.tgz`)); }, 'native-user-dependency-metadata-invalid'],
]) {
  test(`.6 rejects ${name} before any child (synthetic metadata)`, t => {
    const f = asarFixture(t); noChild(t); change(f);
    const result = verifyNativeDesktopFiles(f);
    assert.equal(result.valid, false); assert.equal(result.provisioning.reason, reason);
  });
}

test('.5 retains exact receipt inventory, even when .6 would classify extra as user-owned', t => {
  const f = fixture(t); userReceipt(f);
  assert.equal(verifyNativeDesktopFiles(f).provisioning.reason, 'native-receipt-inventory-mismatch');
});

test('source receipt drift blocks ASAR launch with sound synthetic runtime inventory', t => {
  const f = asarFixture(t); noChild(t);
  f.receipt.source = { ...f.source, targetCommit: '0'.repeat(40) };
  write(join(f.profile, 'desktop-plugin-receipts.json'), { schemaVersion: 1, receipts: { [f.source.packageName]: f.receipt } });
  const result = verifyNativeDesktopFiles(f);
  assert.equal(result.valid, false); assert.equal(result.provisioning.reason, 'native-state-receipt-mismatch');
});
