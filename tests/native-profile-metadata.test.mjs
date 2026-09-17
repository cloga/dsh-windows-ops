// SYNTHETIC METADATA ONLY. No installed/runtime package is imported or qualified.
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import fs, { lstatSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmdirSync, symlinkSync, unlinkSync, writeFileSync } from 'node:fs';
import { syncBuiltinESMExports } from 'node:module';
import { tmpdir } from 'node:os';
import { basename, dirname, join } from 'node:path';
import { test } from 'node:test';
import { inferLegacyOwnership, readNativeProfileMetadata, validateNativeProfileMetadata } from '../tools/native-profile-metadata.mjs';

const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const sri = `sha512-${Buffer.alloc(64, 1).toString('base64')}`;
const receiptCap = () => ({ id: 'desktopNativeVerifiedRelease', schemaVersion: 1, sourceSchemaVersion: 1, receiptSchemaVersion: 1 });
const stateCap = () => ({ id: 'desktopNativePluginProvisioning', schemaVersion: 1, planSchemaVersion: 1, stateSchemaVersion: 1, pluginCapability: receiptCap() });
const spec = digest => `file:.desktop-plugin-artifacts/${digest}.tgz`;
function source(name = 'synthetic-required') {
  return { schemaVersion: 1, type: 'githubRelease', owner: 'fixture-owner', repo: 'fixture-repo', tag: 'v1.2.3',
    asset: 'synthetic-package.tgz', assetId: 10, packageName: name, version: '1.2.3', size: 7, sha256: hash(name), integrity: sri,
    targetCommit: 'a'.repeat(40), dependencyRegistry: 'https://registry.npmjs.org/',
    checksumManifest: { format: 'sha256sums', asset: 'SHA256SUMS', assetId: 11,
      url: 'https://github.com/fixture-owner/fixture-repo/releases/download/v1.2.3/SHA256SUMS', size: 7, sha256: 'b'.repeat(64), integrity: sri } };
}
function receipt(name) {
  const s = source(name);
  return { schemaVersion: 1, capability: receiptCap(), source: s, releaseId: 12, assetId: s.assetId,
    packageName: s.packageName, version: s.version, artifactSha256: s.sha256,
    states: { staged: true, health: 'passed', activated: true, rolledBack: false, verified: true } };
}
function fixture(name = 'synthetic-required') {
  const s = source(name); const r = receipt(name);
  const plan = { schemaVersion: 1, mode: 'exact', plugins: [{ required: true, source: structuredClone(s) }] };
  return { name, plan, metadata: {
    manifest: { name: '@deepseek-ai/dsh-desktop-runtime', private: true, version: 'synthetic-profile',
      dependencies: { [name]: spec(s.sha256) }, dsh: { profile: { bundles: ['@deepseek-ai/dsh-base', '@deepseek-ai/dsh-web-app', name] } } },
    state: { schemaVersion: 1, capability: stateCap(), planSha256: hash(JSON.stringify(plan)), composition: 'active',
      plugins: [{ name, version: s.version, required: true, status: 'active', source: structuredClone(s), receipt: structuredClone(r) }],
      removed: [], rolledBack: false, verified: true },
    store: { schemaVersion: 1, receipts: { [name]: r }, owners: { [name]: 'release' } },
  } };
}
const check = (f, options = { hasReceiptArtifact: () => true }) => validateNativeProfileMetadata(f.metadata, f.plan, options);
function addReceipt(f, name = 'synthetic-user', owner = 'user') {
  const r = receipt(name); f.metadata.store.receipts[name] = r;
  if (Object.hasOwn(f.metadata.store, 'owners')) f.metadata.store.owners[name] = owner;
  return r;
}
function snapshot(name = 'synthetic-source') {
  return { packageName: name, version: '2.0.0-alpha.1', spec: 'git+https://example.invalid/synthetic.git#fixture',
    resolved: 'https://example.invalid/synthetic.tgz', commit: 'c'.repeat(40), sha256: hash(name), integrity: sri };
}
function addSnapshot(f, name = 'synthetic-source') {
  const s = snapshot(name); f.metadata.snapshots ??= { schemaVersion: 1, packages: {} };
  f.metadata.snapshots.packages[name] = s; return s;
}
const reverse = value => Object.fromEntries(Object.entries(value).reverse());
const error = code => ({ message: code });

for (const name of ['synthetic-required', 'dsh-github-copilot']) {
  test(`generic one-required plan metadata (${name}); not runtime proof`, () => {
    const f = fixture(name); const result = check(f);
    assert.equal(result.planSha256, hash(JSON.stringify(f.plan)));
    assert.equal(result.requiredPluginOwner, 'release'); assert.equal(result.ownershipSource, 'explicit');
    assert.deepEqual(result.userExtras, { dependencyCount: 0, receiptCount: 0, enabledBundleCount: 0, contentsAttested: false });
  });
}
test('explicit current required user ownership is allowed by source inventory semantics', () => {
  const f = fixture(); f.metadata.store.owners[f.name] = 'user';
  assert.equal(check(f).requiredPluginOwner, 'user');
});
test('user-tail order, exact deps, disabled/detached receipts and root-less bundle metadata are preserved', () => {
  const f = fixture();
  f.metadata.manifest.dsh.profile.bundles.splice(2, 0, 'user-first');
  f.metadata.manifest.dsh.profile.bundles.push('user-last');
  f.metadata.manifest.dependencies['user-first'] = '4.0.0-rc.2';
  f.metadata.manifest.dependencies['user-disabled'] = '1.0.0';
  addReceipt(f, 'user-detached');
  // user-last deliberately has no dependency or installed root: metadata alone
  // must not invent that condition; the parent probe owns usable-root validation.
  const result = check(f);
  assert.deepEqual(result.manifest.dsh.profile.bundles, ['@deepseek-ai/dsh-base', '@deepseek-ai/dsh-web-app',
    'user-first', f.name, 'user-last']);
  assert.deepEqual(result.userExtras, { dependencyCount: 2, receiptCount: 1, enabledBundleCount: 2, contentsAttested: false });
});
test('receipt top/states extra fields and shuffled source keys normalize; caps keep source order', () => {
  const f = fixture(); const raw = f.metadata.store.receipts[f.name];
  raw.unused = 'synthetic-unused'; raw.states.unused = true;
  raw.source = reverse(raw.source); raw.source.checksumManifest = reverse(raw.source.checksumManifest);
  f.plan.plugins[0].source = reverse(f.plan.plugins[0].source);
  f.metadata.state.unused = 'source permits top-level state extras';
  const result = check(f);
  assert.equal(result.planSha256, f.metadata.state.planSha256);
  assert.equal(Object.hasOwn(result.store.receipts[f.name], 'unused'), false);
  assert.equal(Object.hasOwn(result.store.receipts[f.name].states, 'unused'), false);
  assert.equal(Object.hasOwn(result.state, 'unused'), false);
});
test('profile version is a source-owned string, not an invented semver constraint', () => {
  const f = fixture(); f.metadata.manifest.version = ''; assert.equal(check(f).manifest.version, '');
});

for (const [label, mutate, code] of [
  ['store unknown field', f => { f.metadata.store.unused = true; }, 'native-receipt-store-invalid'],
  ['store array', f => { f.metadata.store.receipts = []; }, 'native-receipt-store-invalid'],
  ['owners missing key', f => { f.metadata.store.owners = {}; }, 'native-receipt-owner-invalid'],
  ['owners extra key', f => { f.metadata.store.owners.extra = 'user'; }, 'native-receipt-owner-invalid'],
  ['owners equal-length wrong key', f => { f.metadata.store.owners = { wrong: 'user' }; }, 'native-receipt-owner-invalid'],
  ['owners unknown value', f => { f.metadata.store.owners[f.name] = 'system'; }, 'native-receipt-owner-invalid'],
  ['owners null not legacy', f => { f.metadata.store.owners = null; }, 'native-receipt-owner-invalid'],
  ['owners array', f => { f.metadata.store.owners = []; }, 'native-receipt-owner-invalid'],
  ['release-owned extra', f => { addReceipt(f, 'other-release', 'release'); }, 'native-release-owned-extra'],
  ['missing required receipt', f => { delete f.metadata.store.receipts[f.name]; delete f.metadata.store.owners[f.name]; }, 'native-state-receipt-mismatch'],
  ['required state receipt drift', f => { f.metadata.store.receipts[f.name].releaseId++; }, 'native-state-receipt-mismatch'],
  ['required source drift', f => { f.plan.plugins[0].source.targetCommit = 'd'.repeat(40); f.metadata.state.planSha256 = hash(JSON.stringify(f.plan)); }, 'native-state-receipt-mismatch'],
  ['required dependency drift', f => { f.metadata.manifest.dependencies[f.name] = '1.2.3'; }, 'native-state-receipt-mismatch'],
  ['wrong current plan hash', f => { f.metadata.state.planSha256 = '0'.repeat(64); }, 'native-provisioning-state-invalid'],
  ['duplicate result', f => { f.metadata.state.plugins.push(structuredClone(f.metadata.state.plugins[0])); }, 'native-provisioning-state-invalid'],
  ['state invalid extra plugin field', f => { f.metadata.state.plugins[0].unused = true; }, 'native-provisioning-state-invalid'],
  ['state active message', f => { f.metadata.state.plugins[0].message = 'not allowed for active'; }, 'native-provisioning-state-invalid'],
  ['state active phase', f => { f.metadata.state.plugins[0].phase = 'health'; }, 'native-provisioning-state-invalid'],
  ['state boolean as string', f => { f.metadata.state.verified = 'true'; }, 'native-provisioning-state-invalid'],
  ['state cap key order', f => { f.metadata.state.capability = reverse(f.metadata.state.capability); }, 'native-provisioning-state-invalid'],
  ['receipt cap key order', f => { f.metadata.store.receipts[f.name].capability = reverse(receiptCap()); }, 'native-receipt-invalid'],
  ['duplicate removed', f => { f.metadata.state.removed = ['old', 'old']; }, 'native-provisioning-state-invalid'],
  ['invalid removed name', f => { f.metadata.state.removed = ['../old']; }, 'native-provisioning-state-invalid'],
  ['wrong bundle prefix', f => { f.metadata.manifest.dsh.profile.bundles.reverse(); }, 'native-profile-composition-mismatch'],
  ['duplicate bundle', f => { f.metadata.manifest.dsh.profile.bundles.push(f.name); }, 'native-profile-composition-mismatch'],
  ['invalid extra bundle', f => { f.metadata.manifest.dsh.profile.bundles.push('../outside'); }, 'native-profile-composition-mismatch'],
  ['disabled required bundle', f => { f.metadata.manifest.dsh.profile.bundles.pop(); }, 'native-profile-composition-mismatch'],
]) {
  test(`metadata rejects ${label} (synthetic)`, () => {
    const f = fixture(); mutate(f); assert.throws(() => check(f), error(code));
  });
}

for (const [label, mutate] of [
  ['non-GitHub source', r => { r.source = { schemaVersion: 1, type: 'packageSpec', spec: 'example' }; }],
  ['source extra key', r => { r.source.unused = true; }],
  ['invalid owner', r => { r.source.owner = 'owner/path'; }],
  ['invalid repo', r => { r.source.repo = 'repo/path'; }],
  ['mutable latest tag', r => { r.source.tag = 'LaTeSt'; }],
  ['unsafe asset', r => { r.source.asset = '../asset.tgz'; }],
  ['nonpositive asset id', r => { r.source.assetId = 0; r.assetId = 0; }],
  ['oversize source artifact', r => { r.source.size = 64 * 1024 * 1024 + 1; }],
  ['invalid digest', r => { r.source.sha256 = 'B'.repeat(64); r.artifactSha256 = r.source.sha256; }],
  ['noncanonical version', r => { r.source.version = 'v1.2.3'; r.version = r.source.version; }],
  ['build metadata version', r => { r.source.version = '1.2.3+build'; r.version = r.source.version; }],
  ['invalid target commit', r => { r.source.targetCommit = 'main'; }],
  ['insecure registry', r => { r.source.dependencyRegistry = 'http://registry.npmjs.org/'; }],
  ['credential registry', r => { r.source.dependencyRegistry = 'https://fixture-secret@registry.npmjs.org/'; }],
  ['query registry', r => { r.source.dependencyRegistry = 'https://registry.npmjs.org/?private=value'; }],
  ['checksum extra key', r => { r.source.checksumManifest.unused = true; }],
  ['checksum URL substitution', r => { r.source.checksumManifest.url = 'https://example.invalid/SHA256SUMS'; }],
  ['invalid SHA512 length', r => { r.source.integrity = 'sha512-YQ=='; }],
  ['noncanonical SHA512 padding bits', r => { r.source.integrity = sri.slice(0, -3) + 'B=='; }],
  ['nonpositive release id', r => { r.releaseId = 0; }],
  ['receipt package mismatch', r => { r.packageName = 'another'; }],
  ['receipt asset mismatch', r => { r.assetId++; }],
  ['receipt digest mismatch', r => { r.artifactSha256 = '0'.repeat(64); }],
  ['receipt states boolean', r => { r.states.verified = 'true'; }],
]) {
  test(`detached user receipt still rejects ${label} (synthetic)`, () => {
    const f = fixture(); const r = addReceipt(f); mutate(r);
    assert.throws(() => check(f), error('native-receipt-invalid'));
  });
}
test('user receipt optional checksum/integrity/registry and source-allowed registry path remain valid', () => {
  const f = fixture(); const r = addReceipt(f);
  delete r.source.checksumManifest; delete r.source.integrity; r.source.dependencyRegistry = 'https://registry.npmjs.org/a/path';
  assert.equal(check(f).userExtras.receiptCount, 1);
});
test('checksum URL uses source encodeURIComponent rules, not raw plus', () => {
  const f = fixture(); const r = addReceipt(f); r.source.tag = 'v1.2.3+fixture';
  r.source.checksumManifest.url = 'https://github.com/fixture-owner/fixture-repo/releases/download/v1.2.3%2Bfixture/SHA256SUMS';
  assert.equal(check(f).userExtras.receiptCount, 1);
  r.source.checksumManifest.url = r.source.checksumManifest.url.replace('%2B', '+');
  assert.throws(() => check(f), error('native-receipt-invalid'));
});

for (const value of ['1.0.0', '0.0.0', '1.2.3-rc.1', '1.2.3-01a', '9007199254740991.0.0', '1.2.3-90071992547409910']) {
  test(`canonical exact user dependency ${value} accepted as metadata only`, () => {
    const f = fixture(); f.metadata.manifest.dependencies.user = value;
    assert.equal(check(f).userExtras.contentsAttested, false);
  });
}
for (const value of ['^1.2.3', '~1.2.3', 'latest', '1.2', '01.2.3', '1.2.3-01', 'v1.2.3', ' 1.2.3',
  '1.2.3+build', '9007199254740992.0.0', 'file:../escape.tgz', 'git+https://example.invalid/unlocked.git', '1.2.3-' + 'a'.repeat(256)]) {
  test(`noncanonical/unlocked user dependency ${value.slice(0, 40)} rejected`, () => {
    const f = fixture(); f.metadata.manifest.dependencies.user = value;
    assert.throws(() => check(f), error('native-user-dependency-metadata-invalid'));
  });
}
test('user receipt artifact dependency requires presence, never claims payload digest checked', () => {
  const f = fixture(); const r = addReceipt(f); f.metadata.manifest.dependencies[r.packageName] = spec(r.artifactSha256);
  assert.throws(() => check(f, { hasReceiptArtifact: digest => digest === source(f.name).sha256 }), error('native-user-dependency-metadata-invalid'));
  assert.equal(check(f).userExtras.contentsAttested, false);
});
test('source snapshot artifact spec is metadata-only and needs no archive presence', () => {
  const f = fixture(); const s = addSnapshot(f); f.metadata.manifest.dependencies[s.packageName] = spec(s.sha256);
  const requested = [];
  const result = check(f, { hasReceiptArtifact: digest => { requested.push(digest); return digest === source(f.name).sha256; } });
  assert.equal(result.userExtras.dependencyCount, 1); assert.equal(result.userExtras.contentsAttested, false);
  assert.deepEqual(requested, [source(f.name).sha256]);
});
test('snapshot spec can qualify independently of a same-name receipt archive', () => {
  const f = fixture(); const r = addReceipt(f, 'synthetic-source'); const s = addSnapshot(f);
  s.sha256 = r.artifactSha256; f.metadata.manifest.dependencies[s.packageName] = spec(s.sha256);
  // Source records remain distinct kinds; do not invent cross-kind version equality.
  const result = check(f, { hasReceiptArtifact: digest => digest === source(f.name).sha256 });
  assert.equal(result.userExtras.dependencyCount, 1); assert.equal(result.userExtras.receiptCount, 1);
  assert.equal(result.userExtras.contentsAttested, false);
});
for (const [label, mutate] of [
  ['root schema', f => { f.metadata.snapshots.schemaVersion = 2; }],
  ['root extra key', f => { f.metadata.snapshots.unused = true; }],
  ['packages array', f => { f.metadata.snapshots.packages = []; }],
  ['entry extra key', (f, s) => { s.unused = true; }],
  ['entry package mismatch', (f, s) => { s.packageName = 'other'; }],
  ['range version', (f, s) => { s.version = '^2.0.0'; }],
  ['build metadata version', (f, s) => { s.version = '2.0.0+metadata'; }],
  ['blank spec', (f, s) => { s.spec = '   '; }],
  ['control spec', (f, s) => { s.spec = 'fixture\nvalue'; }],
  ['empty resolved', (f, s) => { s.resolved = ''; }],
  ['control resolved', (f, s) => { s.resolved = 'fixture\x7fvalue'; }],
  ['invalid commit', (f, s) => { s.commit = 'main'; }],
  ['invalid sha256', (f, s) => { s.sha256 = 'wrong'; }],
  ['missing integrity', (f, s) => { delete s.integrity; }],
  ['invalid integrity', (f, s) => { s.integrity = 'sha512-YQ=='; }],
]) {
  test(`ALL snapshot metadata validates: detached ${label} rejects`, () => {
    const f = fixture(); const s = addSnapshot(f); mutate(f, s);
    assert.throws(() => check(f), error('native-package-snapshot-invalid'));
  });
}
test('snapshot resolved is source-defined nonempty text, not an invented transport restriction', () => {
  const f = fixture(); const s = addSnapshot(f); s.resolved = ' '; delete s.commit;
  assert.equal(check(f).userExtras.contentsAttested, false);
});

test('legacy current evidence infers release only for normalized matching active receipt', () => {
  const f = fixture(); delete f.metadata.store.owners; addReceipt(f, 'legacy-user');
  f.metadata.store.receipts[f.name].unused = true; f.metadata.store.receipts[f.name].states.unused = true;
  f.metadata.store.receipts[f.name].source = reverse(f.metadata.store.receipts[f.name].source);
  const result = check(f);
  assert.equal(result.ownershipSource, 'legacy-inferred'); assert.equal(result.requiredPluginOwner, 'release');
  assert.equal(result.store.owners['legacy-user'], 'user');
});
test('invalid previous canonical plan hash defaults user but cannot pass current baseline', () => {
  const f = fixture(); delete f.metadata.store.owners; f.metadata.state.planSha256 = '0'.repeat(64);
  assert.equal(inferLegacyOwnership(f.metadata.manifest, f.metadata.state, f.metadata.store.receipts)[f.name], 'user');
  assert.throws(() => check(f), error('native-provisioning-state-invalid'));
});
test('legacy optional-failed evidence does not infer release ownership', () => {
  const f = fixture(); const item = f.metadata.state.plugins[0];
  item.required = false; item.status = 'optional-failed'; item.message = 'synthetic failure'; item.phase = 'download'; delete item.receipt;
  f.metadata.state.planSha256 = hash(JSON.stringify({ schemaVersion: 1, mode: 'exact',
    plugins: [{ required: false, source: source(f.name) }] }));
  assert.equal(inferLegacyOwnership(f.metadata.manifest, f.metadata.state, f.metadata.store.receipts)[f.name], 'user');
  f.metadata.state.verified = 'true';
  assert.throws(() => inferLegacyOwnership(f.metadata.manifest, f.metadata.state, f.metadata.store.receipts), error('native-provisioning-state-invalid'));
});
test('legacy inference without state grants only user; wrong receipt/spec cannot grant release', () => {
  const f = fixture(); assert.equal(inferLegacyOwnership(undefined, undefined, f.metadata.store.receipts)[f.name], 'user');
  f.metadata.store.receipts[f.name].releaseId++;
  assert.equal(inferLegacyOwnership(f.metadata.manifest, f.metadata.state, f.metadata.store.receipts)[f.name], 'user');
  f.metadata.store.receipts[f.name] = receipt(f.name); f.metadata.manifest.dependencies[f.name] = '1.2.3';
  assert.equal(inferLegacyOwnership(f.metadata.manifest, f.metadata.state, f.metadata.store.receipts)[f.name], 'user');
});

function remove(path) {
  const stat = lstatSync(path, { throwIfNoEntry: false }); if (!stat) return;
  if (stat.isSymbolicLink()) unlinkSync(path);
  else if (stat.isDirectory()) { for (const name of readdirSync(path)) remove(join(path, name)); rmdirSync(path); }
  else unlinkSync(path);
}
function diskFixture(t, f = fixture()) {
  const root = mkdtempSync(join(tmpdir(), 'native-profile-metadata-synthetic-')); t.after(() => remove(root));
  const profile = join(root, 'profile'); mkdirSync(profile);
  const files = { 'package.json': f.metadata.manifest, 'desktop-plugin-receipts.json': f.metadata.store,
    'desktop-plugin-provisioning-state.json': f.metadata.state };
  if (f.metadata.snapshots !== undefined) files['desktop-plugin-package-locks.json'] = f.metadata.snapshots;
  for (const [name, value] of Object.entries(files)) writeFileSync(join(profile, name), JSON.stringify(value));
  mkdirSync(join(profile, '.desktop-plugin-artifacts'));
  writeFileSync(join(profile, '.desktop-plugin-artifacts', `${source(f.name).sha256}.tgz`), 'inert fixture bytes; NOT digest-attested here');
  return { ...f, root, profile, files };
}

test('read binds raw hashes and optional absence, reads no entrypoints/env/settings or artifact bytes', t => {
  const f = diskFixture(t); const opened = []; const original = fs.openSync;
  t.mock.method(fs, 'openSync', (path, ...args) => { opened.push(basename(String(path))); return original(path, ...args); });
  syncBuiltinESMExports(); t.after(() => { t.mock.restoreAll(); syncBuiltinESMExports(); });
  const result = readNativeProfileMetadata(f.profile, f.plan);
  const hashes = Object.fromEntries(Object.keys(f.files).map(name => [name, hash(readFileSync(join(f.profile, name)))]));
  hashes['desktop-plugin-package-locks.json'] = null;
  assert.equal(result.snapshotSha256, hash(JSON.stringify(hashes)));
  assert.equal(result.planSha256, f.metadata.state.planSha256);
  assert.ok(opened.every(name => Object.hasOwn(f.files, name)));
  assert.equal(result.userExtras.contentsAttested, false);
});
test('raw whitespace and optional empty snapshot presence change snapshot identity only', t => {
  const f = diskFixture(t); const before = readNativeProfileMetadata(f.profile, f.plan);
  writeFileSync(join(f.profile, 'package.json'), JSON.stringify(f.metadata.manifest, null, 2));
  const whitespace = readNativeProfileMetadata(f.profile, f.plan);
  assert.notEqual(whitespace.snapshotSha256, before.snapshotSha256); assert.equal(whitespace.planSha256, before.planSha256);
  writeFileSync(join(f.profile, 'desktop-plugin-package-locks.json'), JSON.stringify({ schemaVersion: 1, packages: {} }));
  const present = readNativeProfileMetadata(f.profile, f.plan);
  assert.notEqual(present.snapshotSha256, whitespace.snapshotSha256); assert.deepEqual(present.userExtras, whitespace.userExtras);
});
test('disk snapshot-only user dependency succeeds with missing archive and no installed-root read', t => {
  const f = fixture(); const s = addSnapshot(f); f.metadata.manifest.dependencies[s.packageName] = spec(s.sha256);
  f.metadata.manifest.dsh.profile.bundles.push(s.packageName);
  const disk = diskFixture(t, f); const result = readNativeProfileMetadata(disk.profile, f.plan);
  assert.equal(result.userExtras.dependencyCount, 1); assert.equal(result.userExtras.enabledBundleCount, 1);
  assert.equal(result.userExtras.contentsAttested, false);
});
for (const [name, code] of [['package.json', 'native-profile-composition-mismatch'],
  ['desktop-plugin-receipts.json', 'native-receipt-store-invalid'], ['desktop-plugin-provisioning-state.json', 'native-provisioning-state-invalid'],
  ['desktop-plugin-package-locks.json', 'native-package-snapshot-invalid']]) {
  test(`4 MiB bound and raw-parser diagnostics for ${name}`, t => {
    const f = diskFixture(t); const path = join(f.profile, name);
    writeFileSync(path, ' '.repeat(4 * 1024 * 1024 + 1));
    assert.throws(() => readNativeProfileMetadata(f.profile, f.plan), error(code));
    writeFileSync(path, 'synthetic-private-sentinel-never-in-errors');
    assert.throws(() => readNativeProfileMetadata(f.profile, f.plan), error(code));
  });
}
test('deep malformed capability yields an owned receipt error, not serializer details', t => {
  const f = diskFixture(t);
  const deep = '{"x":' + '['.repeat(10000) + '0' + ']'.repeat(10000) + '}';
  const bytes = JSON.stringify(f.metadata.store).replace(JSON.stringify(receiptCap()), deep);
  writeFileSync(join(f.profile, 'desktop-plugin-receipts.json'), bytes);
  assert.throws(() => readNativeProfileMetadata(f.profile, f.plan), error('native-receipt-invalid'));
});
test('exactly 4 MiB metadata is supported without reading beyond the bound', t => {
  const f = diskFixture(t); const value = { ...f.metadata.manifest, padding: '' };
  value.padding = 'x'.repeat(4 * 1024 * 1024 - Buffer.byteLength(JSON.stringify(value)));
  writeFileSync(join(f.profile, 'package.json'), JSON.stringify(value));
  assert.match(readNativeProfileMetadata(f.profile, f.plan).snapshotSha256, /^[a-f0-9]{64}$/u);
});
test('metadata changed before second raw read fails inconsistent snapshot', t => {
  const f = diskFixture(t); const path = join(f.profile, 'package.json'); const original = fs.openSync; let reads = 0;
  t.mock.method(fs, 'openSync', (target, flags, ...args) => {
    if (String(target) === path && flags === 'r' && ++reads === 2) writeFileSync(path, JSON.stringify(f.metadata.manifest) + ' ');
    return original(target, flags, ...args);
  });
  syncBuiltinESMExports(); t.after(() => { t.mock.restoreAll(); syncBuiltinESMExports(); });
  assert.throws(() => readNativeProfileMetadata(f.profile, f.plan), error('native-inconsistent-snapshot'));
});
for (const operation of ['delete-required', 'add-optional']) {
  test(`second raw snapshot rejects ${operation} presence change`, t => {
    const f = diskFixture(t); const path = join(f.profile, 'package.json'); const original = fs.openSync; let reads = 0;
    t.mock.method(fs, 'openSync', (target, flags, ...args) => {
      if (String(target) === path && flags === 'r' && ++reads === 2) {
        if (operation === 'delete-required') unlinkSync(path);
        else writeFileSync(join(f.profile, 'desktop-plugin-package-locks.json'), JSON.stringify({ schemaVersion: 1, packages: {} }));
      }
      return original(target, flags, ...args);
    });
    syncBuiltinESMExports(); t.after(() => { t.mock.restoreAll(); syncBuiltinESMExports(); });
    assert.throws(() => readNativeProfileMetadata(f.profile, f.plan), error('native-inconsistent-snapshot'));
  });
}
for (const name of ['desktop-plugin-receipts.json', 'desktop-plugin-package-locks.json']) {
  test(`metadata ${name} rejects junction, dangling junction and special directory`, t => {
    const f = diskFixture(t); const target = join(f.root, 'outside'); mkdirSync(target); const path = join(f.profile, name);
    remove(path); symlinkSync(target, path, 'junction');
    assert.throws(() => readNativeProfileMetadata(f.profile, f.plan), error('native-reparse-path'));
    unlinkSync(path); symlinkSync(join(f.root, 'absent'), path, 'junction');
    assert.throws(() => readNativeProfileMetadata(f.profile, f.plan), error('native-reparse-path'));
    unlinkSync(path); mkdirSync(path);
    assert.throws(() => readNativeProfileMetadata(f.profile, f.plan), error('native-physical-type-mismatch'));
  });
}
test('profile ancestor junction is rejected before metadata reads', t => {
  const f = diskFixture(t); const linked = join(f.root, 'linked'); symlinkSync(f.profile, linked, 'junction');
  assert.throws(() => readNativeProfileMetadata(linked, f.plan), error('native-reparse-path'));
});
test('user receipt artifact must be present and regular; extra bytes are not attested', t => {
  const f = fixture(); const r = addReceipt(f); f.metadata.manifest.dependencies[r.packageName] = spec(r.artifactSha256);
  const disk = diskFixture(t, f); const path = join(disk.profile, '.desktop-plugin-artifacts', `${r.artifactSha256}.tgz`);
  assert.throws(() => readNativeProfileMetadata(disk.profile, f.plan), error('native-user-dependency-metadata-invalid'));
  writeFileSync(path, 'not the receipt digest, deliberately inert');
  assert.equal(readNativeProfileMetadata(disk.profile, f.plan).userExtras.contentsAttested, false);
  unlinkSync(path); symlinkSync(disk.root, path, 'junction');
  assert.throws(() => readNativeProfileMetadata(disk.profile, f.plan), error('native-reparse-path'));
});
