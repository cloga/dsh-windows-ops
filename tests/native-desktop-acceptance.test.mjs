import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { mkdtempSync, mkdirSync, readFileSync, rmSync, symlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { test } from 'node:test';
import { verifyNativeDesktopFiles, verifyNativeReleaseEvidence } from '../tools/verify-native-desktop.mjs';
import { fileURLToPath } from 'node:url';

const hash = (value, algorithm = 'sha256', encoding = 'hex') => createHash(algorithm).update(value).digest(encoding);
const formalRoot = fileURLToPath(new URL('./fixtures/desktop-native-verified-release/formal-cloga3/', import.meta.url));
const actualLock = () => JSON.parse(readFileSync(new URL('../deployments/windows-copilot.lock.json', import.meta.url), 'utf8'));

test('formal immutable evidence preserves legacy manifest false and startup receipt true', () => {
  const result = verifyNativeReleaseEvidence(actualLock(), formalRoot);
  assert.equal(result.valid, true);
  assert.equal(result.automaticStartupProvisioning, true);
  assert.equal(result.legacyUpdateManifestAutomaticProvisioning, false);
  assert.equal(result.modelResponseVerified, false);
});

for (const [name, mutate, code] of [
  ['candidate descriptor', (l) => { l.components.desktop.installedRuntimeDescriptor.sha256 = 'f012735da203eacca31ff4ee0df7f2dc7e0a0df5ee16df77845ab7a0062f242c'; }, 'installed-identity'],
  ['manifest provisioning upgraded in lock', (l) => { l.components.desktop.releaseChannel.pluginCompatibility.automaticProvisioning = true; }, 'capability'],
  ['startup provisioning disabled', (l) => { l.components.desktop.releaseChannel.nativeProvisioning.buildReceiptCompatibility.automaticProvisioning = false; }, 'capability'],
  ['different canonical plan', (l) => { l.components.desktop.releaseChannel.nativeProvisioning.plan.planSha256 = '0'.repeat(64); }, 'plan'],
  ['different plugin source', (l) => { l.components.copilotIntegration.source.commit = '0'.repeat(40); }, 'plugin'],
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
function write(path, value) {
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, typeof value === 'string' ? value : JSON.stringify(value));
}
function fixture(t) {
  const root = mkdtempSync(join(tmpdir(), 'native-desktop-acceptance-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const installRoot = join(root, 'install');
  const dshHome = join(root, 'home');
  const profile = join(dshHome, 'profiles', 'desktop');
  const lock = JSON.parse(readFileSync(new URL('../deployments/windows-copilot.lock.json', import.meta.url), 'utf8'));
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
    dependencyRegistry: 'https://registry.npmjs.org/',
    checksumManifest: { format: 'sha256sums', asset: checksum.name, assetId: checksum.assetId,
      url: checksum.url, size: checksum.size, sha256: checksum.sha256 } };
  const plan = { schemaVersion: 1, mode: 'exact', plugins: [{ required: true, source }] };
  const receiptCapability = { id: 'desktopNativeVerifiedRelease', schemaVersion: 1, sourceSchemaVersion: 1, receiptSchemaVersion: 1 };
  const capability = { id: 'desktopNativePluginProvisioning', schemaVersion: 1, planSchemaVersion: 1,
    stateSchemaVersion: 1, pluginCapability: receiptCapability };
  const planSha256 = hash(JSON.stringify(plan));
  lock.components.desktop.releaseChannel.managedCapability.provisioning = { capability, planSha256 };
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

for (const [name, change, expected] of [
  ['missing evidence', (f) => rmSync(join(f.profile, 'desktop-plugin-receipts.json')), 'native-evidence-missing'],
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
