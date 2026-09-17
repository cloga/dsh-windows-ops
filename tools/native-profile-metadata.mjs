// Ops-owned, bounded DATA codec for Desktop profile metadata. Builtins only;
// no runtime/private-codec imports, package entrypoints, settings, env or mutation.
// Semantics inspected in source project-manager, plugin-source, plugin-provisioning
// and plugin-package-lock. Metadata acceptance never attests user package bytes.
import { closeSync, fstatSync, lstatSync, openSync, readSync } from 'node:fs';
import { join } from 'node:path';
import { physical, sha256 } from './native-runtime-integrity.mjs';

const MAX_METADATA_BYTES = 4 * 1024 * 1024;
const MAX_ASSET_BYTES = 64 * 1024 * 1024;
const NAME = /^(?:@[a-z0-9][a-z0-9._~-]*\/)?[a-z0-9][a-z0-9._~-]*$/u;
const HASH = /^[a-f0-9]{64}$/u;
const COMMIT = /^[a-f0-9]{40}$/u;
const RELEASE_NAME = /^[A-Za-z0-9][A-Za-z0-9._+-]*$/u;
const BASE = ['@deepseek-ai/dsh-base', '@deepseek-ai/dsh-web-app'];
const receiptCapability = Object.freeze({ id: 'desktopNativeVerifiedRelease', schemaVersion: 1, sourceSchemaVersion: 1, receiptSchemaVersion: 1 });
const stateCapability = Object.freeze({ id: 'desktopNativePluginProvisioning', schemaVersion: 1,
  planSchemaVersion: 1, stateSchemaVersion: 1, pluginCapability: receiptCapability });
const record = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const need = (condition, code) => { if (!condition) throw new Error(code); };
const text = (value, pattern) => typeof value === 'string' && value !== '' && (!pattern || pattern.test(value));
const integer = value => Number.isSafeInteger(value) && value > 0;
const allowed = (value, keys) => record(value) && Object.keys(value).every(key => keys.includes(key));
const same = (left, right) => {
  try { return JSON.stringify(left) === JSON.stringify(right); } catch { return false; }
};
const artifact = hash => `file:.desktop-plugin-artifacts/${hash}.tgz`;

// This is the source's valid(value) === value predicate, not a version-range
// resolver. semver's canonical .version omits build metadata; no v/space/+ forms.
function canonicalVersion(value) {
  if (typeof value !== 'string' || value.length > 256) return false;
  const match = /^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-((?:0|[1-9]\d*|\d*[A-Za-z-][0-9A-Za-z-]*)(?:\.(?:0|[1-9]\d*|\d*[A-Za-z-][0-9A-Za-z-]*))*))?$/u.exec(value);
  return match !== null && match.slice(1, 4).every(part => Number.isSafeInteger(Number(part)));
}
function integrity(value, code, required = false) {
  if (value === undefined && !required) return undefined;
  need(text(value, /^sha512-[A-Za-z0-9+/]+={0,2}$/u), code);
  const encoded = value.slice(7); const bytes = Buffer.from(encoded, 'base64');
  need(bytes.length === 64 && bytes.toString('base64') === encoded, code);
  return value;
}
function source(value, code) {
  need(allowed(value, ['schemaVersion', 'type', 'owner', 'repo', 'tag', 'asset', 'packageName', 'version',
    'assetId', 'size', 'sha256', 'integrity', 'targetCommit', 'dependencyRegistry', 'checksumManifest']) &&
    value.schemaVersion === 1 && value.type === 'githubRelease' &&
    text(value.owner, /^[A-Za-z0-9][A-Za-z0-9-]{0,38}$/u) && text(value.repo, /^[A-Za-z0-9._-]+$/u) &&
    text(value.tag, RELEASE_NAME) && value.tag.toLowerCase() !== 'latest' && text(value.asset, RELEASE_NAME) &&
    integer(value.assetId) && text(value.packageName, NAME) && canonicalVersion(value.version) &&
    integer(value.size) && value.size <= MAX_ASSET_BYTES && text(value.sha256, HASH) && text(value.targetCommit, COMMIT), code);
  const sri = integrity(value.integrity, code);
  if (value.dependencyRegistry !== undefined) {
    need(text(value.dependencyRegistry), code);
    let url; try { url = new URL(value.dependencyRegistry); } catch { need(false, code); }
    need(url.protocol === 'https:' && !url.username && !url.password && !url.search && !url.hash, code);
  }
  let checksumManifest;
  if (value.checksumManifest !== undefined) {
    const c = value.checksumManifest;
    need(allowed(c, ['format', 'asset', 'assetId', 'url', 'size', 'sha256', 'integrity']) && c.format === 'sha256sums' &&
      text(c.asset, RELEASE_NAME) && integer(c.assetId) && integer(c.size) && c.size <= MAX_ASSET_BYTES && text(c.sha256, HASH) &&
      c.url === `https://github.com/${value.owner}/${value.repo}/releases/download/${encodeURIComponent(value.tag)}/${encodeURIComponent(c.asset)}`, code);
    const checksumSri = integrity(c.integrity, code);
    checksumManifest = { format: 'sha256sums', asset: c.asset, assetId: c.assetId, url: c.url, size: c.size, sha256: c.sha256,
      ...(checksumSri === undefined ? {} : { integrity: checksumSri }) };
  }
  // Order intentionally matches the shipped source parser and Ops canonicalPlan.
  return { schemaVersion: 1, type: 'githubRelease', owner: value.owner, repo: value.repo, tag: value.tag,
    asset: value.asset, assetId: value.assetId, packageName: value.packageName, version: value.version,
    size: value.size, sha256: value.sha256, ...(sri === undefined ? {} : { integrity: sri }), targetCommit: value.targetCommit,
    ...(value.dependencyRegistry === undefined ? {} : { dependencyRegistry: value.dependencyRegistry }),
    ...(checksumManifest === undefined ? {} : { checksumManifest }) };
}
function receipt(value) {
  const code = 'native-receipt-invalid';
  // Receipt and states extras are allowed by source, then discarded. Capability
  // equality, unlike source field normalization, is JSON/key-order sensitive.
  need(record(value) && value.schemaVersion === 1 && same(value.capability, receiptCapability), code);
  const parsed = source(value.source, code);
  need(value.packageName === parsed.packageName && value.version === parsed.version && value.artifactSha256 === parsed.sha256 &&
    integer(value.releaseId) && value.assetId === parsed.assetId && record(value.states) && value.states.staged === true &&
    value.states.health === 'passed' && value.states.activated === true && value.states.rolledBack === false && value.states.verified === true, code);
  return { schemaVersion: 1, capability: receiptCapability, source: parsed, releaseId: value.releaseId, assetId: value.assetId,
    packageName: parsed.packageName, version: parsed.version, artifactSha256: parsed.sha256,
    states: { staged: true, health: 'passed', activated: true, rolledBack: false, verified: true } };
}
function plan(value) {
  const code = 'native-provisioning-state-invalid';
  need(allowed(value, ['schemaVersion', 'mode', 'plugins']) && Object.keys(value).length === 3 &&
    value.schemaVersion === 1 && value.mode === 'exact' && Array.isArray(value.plugins), code);
  const names = new Set(); let registry;
  const plugins = value.plugins.map(entry => {
    need(allowed(entry, ['required', 'source']) && Object.keys(entry).length === 2 && typeof entry.required === 'boolean', code);
    const parsed = source(entry.source, code);
    need(parsed.checksumManifest !== undefined && !names.has(parsed.packageName), code); names.add(parsed.packageName);
    const next = parsed.dependencyRegistry ?? 'https://registry.npmjs.org/'; registry ??= next; need(registry === next, code);
    return { required: entry.required, source: parsed };
  });
  return { schemaVersion: 1, mode: 'exact', plugins };
}
function state(value) {
  const code = 'native-provisioning-state-invalid';
  need(record(value) && value.schemaVersion === 1 && same(value.capability, stateCapability) && text(value.planSha256, HASH) &&
    value.composition === 'active' && Array.isArray(value.plugins) && Array.isArray(value.removed) && value.rolledBack === false && value.verified === true, code);
  const plugins = value.plugins.map(item => {
    need(allowed(item, ['name', 'version', 'required', 'status', 'source', 'receipt', 'message', 'phase']) &&
      ['name', 'version', 'required', 'status', 'source'].every(key => Object.hasOwn(item, key)) &&
      typeof item.name === 'string' && typeof item.version === 'string' && typeof item.required === 'boolean' &&
      ['active', 'optional-failed'].includes(item.status) && (item.message === undefined || typeof item.message === 'string'), code);
    const parsed = source(item.source, code); need(parsed.checksumManifest !== undefined, code);
    need(parsed.packageName === item.name && parsed.version === item.version, 'native-state-receipt-mismatch');
    const parsedReceipt = item.receipt === undefined ? undefined : receipt(item.receipt);
    need(item.phase === undefined || ['download', 'validation', 'install', 'graph', 'health'].includes(item.phase), code);
    if (parsedReceipt !== undefined) need(same(parsedReceipt.source, parsed), 'native-state-receipt-mismatch');
    need(item.status === 'active' ? parsedReceipt !== undefined && item.message === undefined && item.phase === undefined :
      item.required === false && parsedReceipt === undefined && text(item.message) && item.phase !== undefined, code);
    return { name: item.name, version: item.version, required: item.required, status: item.status, source: parsed,
      ...(parsedReceipt === undefined ? {} : { receipt: parsedReceipt }), ...(item.message === undefined ? {} : { message: item.message }),
      ...(item.phase === undefined ? {} : { phase: item.phase }) };
  });
  need(new Set(plugins.map(item => item.name)).size === plugins.length && value.removed.every(name => text(name, NAME)) &&
    new Set(value.removed).size === value.removed.length, code);
  return { schemaVersion: 1, capability: stateCapability, planSha256: value.planSha256, composition: 'active',
    plugins, removed: value.removed, rolledBack: false, verified: true };
}
function receiptMap(value) {
  need(record(value), 'native-receipt-store-invalid'); const result = Object.create(null);
  for (const [name, raw] of Object.entries(value)) {
    need(text(name, NAME), 'native-receipt-invalid'); const parsed = receipt(raw);
    need(parsed.packageName === name, 'native-receipt-invalid'); result[name] = parsed;
  }
  return result;
}
function inferOwners(manifest, previous, receipts) {
  const owners = Object.create(null);
  for (const name of Object.keys(receipts)) owners[name] = 'user';
  if (previous === undefined) return owners;
  const previousPlan = plan({ schemaVersion: 1, mode: 'exact', plugins: previous.plugins.map(({ required, source }) => ({ required, source })) });
  if (sha256(JSON.stringify(previousPlan)) !== previous.planSha256) return owners;
  need(record(manifest) && record(manifest.dependencies), 'native-profile-composition-mismatch');
  for (const item of previous.plugins) {
    if (item.status === 'active' && Object.hasOwn(receipts, item.name) && same(receipts[item.name], item.receipt) &&
      manifest.dependencies[item.name] === artifact(receipts[item.name].artifactSha256)) owners[item.name] = 'release';
  }
  return owners;
}
/** Synthetic/data callers can examine conservative legacy inference separately.
 * Inputs are raw parsed JSON; invalid state still rejects, but a wrong previous
 * canonical plan hash grants no release ownership. This is NOT a baseline check. */
export function inferLegacyOwnership(manifest, previousState, rawReceipts) {
  return inferOwners(manifest, previousState === undefined ? undefined : state(previousState), receiptMap(rawReceipts));
}
function snapshots(value) {
  const code = 'native-package-snapshot-invalid'; const result = Object.create(null);
  if (value === undefined) return result;
  need(allowed(value, ['schemaVersion', 'packages']) && value.schemaVersion === 1 && record(value.packages), code);
  for (const [name, entry] of Object.entries(value.packages)) {
    need(allowed(entry, ['packageName', 'version', 'spec', 'resolved', 'commit', 'sha256', 'integrity']) && text(name, NAME) &&
      entry.packageName === name && canonicalVersion(entry.version) && typeof entry.spec === 'string' && entry.spec.trim() !== '' &&
      !/[\u0000-\u001f\u007f]/u.test(entry.spec) && text(entry.resolved) && !/[\u0000-\u001f\u007f]/u.test(entry.resolved) &&
      text(entry.sha256, HASH) && (entry.commit === undefined || text(entry.commit, COMMIT)), code);
    const sri = integrity(entry.integrity, code, true);
    result[name] = { packageName: name, version: entry.version, spec: entry.spec, resolved: entry.resolved,
      ...(entry.commit === undefined ? {} : { commit: entry.commit }), sha256: entry.sha256, integrity: sri };
  }
  return result;
}

/** Pure DATA validation; hasReceiptArtifact must report only regular-file presence,
 * never payload attestation. Synthetic callers must not treat success as runtime proof. */
export function validateNativeProfileMetadata(metadata, currentPlan, { hasReceiptArtifact = () => false } = {}) {
  need(record(metadata), 'native-profile-composition-mismatch');
  const parsedPlan = plan(currentPlan);
  need(parsedPlan.plugins.length === 1 && parsedPlan.plugins[0].required, 'native-provisioning-state-invalid');
  const required = parsedPlan.plugins[0]; const name = required.source.packageName;
  const raw = metadata.manifest;
  need(record(raw) && raw.name === '@deepseek-ai/dsh-desktop-runtime' && raw.private === true && typeof raw.version === 'string' &&
    (raw.dependencies === undefined || record(raw.dependencies)) && record(raw.dsh) && record(raw.dsh.profile) &&
    Array.isArray(raw.dsh.profile.bundles) && raw.dsh.profile.bundles.every(bundle => typeof bundle === 'string'), 'native-profile-composition-mismatch');
  const manifest = { ...raw, dependencies: raw.dependencies ?? {} };
  const bundles = manifest.dsh.profile.bundles;
  need(BASE.every((base, index) => bundles[index] === base) && new Set(bundles).size === bundles.length &&
    bundles.slice(BASE.length).every(bundle => text(bundle, NAME)) && bundles.slice(BASE.length).includes(name), 'native-profile-composition-mismatch');
  const parsedState = state(metadata.state);
  const rawStore = metadata.store;
  need(allowed(rawStore, ['schemaVersion', 'receipts', 'owners']) && rawStore.schemaVersion === 1 && record(rawStore.receipts), 'native-receipt-store-invalid');
  const receipts = receiptMap(rawStore.receipts); let owners; let ownershipSource;
  if (Object.hasOwn(rawStore, 'owners')) {
    need(record(rawStore.owners) && Object.keys(rawStore.owners).length === Object.keys(receipts).length, 'native-receipt-owner-invalid');
    owners = Object.create(null);
    for (const [key, owner] of Object.entries(rawStore.owners)) {
      need(Object.hasOwn(receipts, key) && ['user', 'release'].includes(owner), 'native-receipt-owner-invalid'); owners[key] = owner;
    }
    ownershipSource = 'explicit';
  } else { owners = inferOwners(manifest, parsedState, receipts); ownershipSource = 'legacy-inferred'; }
  const sourceSnapshots = snapshots(metadata.snapshots); // Validate ALL entries, even unused snapshots.
  const planSha256 = sha256(JSON.stringify(parsedPlan));
  need(parsedState.planSha256 === planSha256, 'native-provisioning-state-invalid');
  need(!Object.keys(receipts).some(key => owners[key] === 'release' && key !== name), 'native-release-owned-extra');
  need(parsedState.plugins.length === 1, 'native-state-receipt-mismatch');
  const result = parsedState.plugins[0]; const requiredReceipt = receipts[name];
  need(result.name === name && result.required === true && result.status === 'active' && same(result.source, required.source) &&
    requiredReceipt !== undefined && same(requiredReceipt, result.receipt) && requiredReceipt.artifactSha256 === required.source.sha256 &&
    manifest.dependencies[name] === artifact(requiredReceipt.artifactSha256), 'native-state-receipt-mismatch');
  for (const [key, spec] of Object.entries(manifest.dependencies)) {
    need(text(key, NAME) && typeof spec === 'string', 'native-user-dependency-metadata-invalid');
    if (canonicalVersion(spec)) continue;
    const snapshot = sourceSnapshots[key];
    // Source projectManifest accepts this metadata-only branch WITHOUT opening or
    // requiring an archive. Do not confuse it with verifyDesktopPackageArtifact.
    if (snapshot && spec === artifact(snapshot.sha256)) continue;
    const verified = receipts[key];
    need(verified !== undefined && spec === artifact(verified.artifactSha256) && hasReceiptArtifact(verified.artifactSha256) === true,
      'native-user-dependency-metadata-invalid');
  }
  return { manifest, state: parsedState, store: { schemaVersion: 1, receipts, owners }, planSha256, ownershipSource,
    requiredPluginOwner: owners[name], userExtras: {
      dependencyCount: Object.keys(manifest.dependencies).filter(key => key !== name).length,
      receiptCount: Object.keys(receipts).filter(key => key !== name).length,
      enabledBundleCount: bundles.slice(BASE.length).filter(key => key !== name).length, contentsAttested: false,
    } };
}

function readBytes(path, code, optional = false) {
  if (optional && lstatSync(path, { throwIfNoEntry: false }) === undefined) return null;
  physical(path, 'file'); const fd = openSync(path, 'r');
  try {
    const stat = fstatSync(fd);
    need(stat.isFile() && stat.size <= MAX_METADATA_BYTES, code);
    // One extra byte detects growth without allowing an unbounded readFile allocation.
    const bytes = Buffer.allocUnsafe(stat.size + 1); let length = 0;
    while (length < bytes.length) {
      const count = readSync(fd, bytes, length, bytes.length - length, null); if (count === 0) break; length += count;
    }
    need(length === stat.size && fstatSync(fd).size === stat.size, 'native-inconsistent-snapshot');
    return bytes.subarray(0, length);
  } finally { closeSync(fd); }
}
function parse(bytes, code) {
  if (bytes === null) return undefined;
  try { return JSON.parse(bytes.toString('utf8')); } catch { throw new Error(code); }
}
/** Read only the four allowlisted metadata files and artifact-presence metadata.
 * snapshotSha256 binds raw hashes (not normalized JSON), including optional absence.
 * No settings/env/user entrypoints or user-extra payload bytes are read/attested. */
export function readNativeProfileMetadata(profile, currentPlan) {
  physical(profile, 'directory');
  const files = [
    ['package.json', 'native-profile-composition-mismatch', false],
    ['desktop-plugin-receipts.json', 'native-receipt-store-invalid', false],
    ['desktop-plugin-provisioning-state.json', 'native-provisioning-state-invalid', false],
    ['desktop-plugin-package-locks.json', 'native-package-snapshot-invalid', true],
  ];
  const bytes = files.map(([name, code, optional]) => readBytes(join(profile, name), code, optional));
  const parsed = bytes.map((body, index) => parse(body, files[index][1]));
  const validated = validateNativeProfileMetadata({ manifest: parsed[0], store: parsed[1], state: parsed[2], snapshots: parsed[3] }, currentPlan, {
    hasReceiptArtifact(hash) {
      const path = join(profile, '.desktop-plugin-artifacts', `${hash}.tgz`);
      if (lstatSync(path, { throwIfNoEntry: false }) === undefined) return false;
      physical(path, 'file'); return true; // Presence only, not source/archive hash proof.
    },
  });
  const hashes = Object.create(null);
  files.forEach(([name, code, optional], index) => {
    let after;
    try { after = readBytes(join(profile, name), code, optional); }
    catch (error) { if (error.code === 'ENOENT') throw new Error('native-inconsistent-snapshot'); throw error; }
    const before = bytes[index];
    need(before === null ? after === null : after !== null && before.equals(after), 'native-inconsistent-snapshot');
    hashes[name] = before === null ? null : sha256(before);
  });
  return { ...validated, snapshotSha256: sha256(JSON.stringify(hashes)) };
}
