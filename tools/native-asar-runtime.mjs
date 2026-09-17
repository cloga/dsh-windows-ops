// Synchronous, fail-closed ASAR carrier preflight. No runtime imports here.
import { spawnSync } from 'node:child_process';
import { closeSync, lstatSync, openSync, readSync, readdirSync } from 'node:fs';
import { createRequire } from 'node:module';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { isDeepStrictEqual } from 'node:util';
import { hashFile, hashValid, inside, limits, object, physical, physicalInventory, relativeName,
  requireValue, sha256, validateDescriptor } from './native-runtime-integrity.mjs';

const reader = createRequire(import.meta.url)('./vendor/asar-reader/reader.cjs');
const policy = 'node_modules/@deepseek-ai/dsh-desktop-host/register-module-resolution-policy.mjs';
const hostEntry = 'node_modules/@deepseek-ai/dsh-desktop-host/lib/index.js';
export const asarDescriptorPath = 'resources/app.asar/dsh/desktop-runtime.json';

export function nativeLayout(lock) {
  const path = lock?.components?.desktop?.installedRuntimeDescriptor?.relativePath;
  requireValue(typeof path === 'string', 'native-runtime-layout-unsupported');
  const normalized = path.replaceAll('\\', '/');
  requireValue(['resources/dsh/desktop-runtime.json', asarDescriptorPath].includes(normalized), 'native-runtime-layout-unsupported');
  const asar = normalized === asarDescriptorPath;
  const version = lock.components.desktop.releaseChannel?.upstreamVersion;
  requireValue(typeof version === 'string' && (asar ? /^0\.1\.6(?:-|$)/u : /^0\.1\.5(?:-|$)/u).test(version),
    'native-runtime-layout-unsupported');
  return asar ? 'asar-runtime' : 'physical-links';
}

// Validate the fixed size envelope BEFORE calling upstream's allocating reader.
// This is not an ASAR parser: all archive structure is read by maintained upstream APIs.
export function boundedHeader(archive) {
  const fd = openSync(archive, 'r'); const bytes = Buffer.alloc(8);
  try { requireValue(readSync(fd, bytes, 0, 8, 0) === 8, 'native-asar-header-invalid'); }
  finally { closeSync(fd); }
  const length = bytes.readUInt32LE(4);
  requireValue(bytes.readUInt32LE(0) === 4 && length >= 8 && length % 4 === 0 && length <= limits.header &&
    length <= lstatSync(archive).size - 8, 'native-asar-header-limit');
  reader.uncache(archive);
  const raw = reader.getRawHeader(archive);
  requireValue(raw.headerSize === length && object(raw.header) && object(raw.header.files) &&
    raw.headerString === JSON.stringify(raw.header), 'native-asar-header-invalid');
  return raw;
}

export function headerRuntimeInventory(raw, archiveBytes) {
  const files = []; const aliases = new Set(); let count = 0; let total = 0;
  const visit = (node, path, inheritedUnpacked, depth) => {
    requireValue(object(node) && !Object.hasOwn(node, 'link') && depth <= limits.depth && ++count <= limits.files,
      'native-asar-entry-invalid');
    if (path) { relativeName(path); requireValue(!aliases.has(path.toLowerCase()), 'native-path-alias'); aliases.add(path.toLowerCase()); }
    requireValue(node.unpacked === undefined || typeof node.unpacked === 'boolean', 'native-asar-entry-invalid');
    const unpacked = inheritedUnpacked || node.unpacked === true;
    if (Object.hasOwn(node, 'files')) {
      requireValue(object(node.files) && !Object.hasOwn(node, 'size') && !Object.hasOwn(node, 'offset'), 'native-asar-entry-invalid');
      for (const [name, value] of Object.entries(node.files)) {
        requireValue(!name.includes('/'), 'native-asar-entry-invalid');
        visit(value, path ? `${path}/${name}` : name, unpacked, depth + 1);
      }
    } else {
      requireValue(Number.isSafeInteger(node.size) && node.size >= 0 && node.size <= limits.file, 'native-asar-entry-invalid');
      total += node.size; requireValue(total <= limits.total, 'native-inventory-limit');
      if (!unpacked) {
        requireValue(typeof node.offset === 'string' && /^(?:0|[1-9]\d*)$/u.test(node.offset), 'native-asar-entry-invalid');
        const offset = Number(node.offset);
        requireValue(Number.isSafeInteger(offset) && offset + node.size <= archiveBytes - raw.headerSize - 8, 'native-asar-entry-invalid');
      } else {
        // Electron/upstream file reads use file flags, not just directory flags.
        requireValue(node.unpacked === true, 'native-asar-unpack-semantics-mismatch');
      }
      if (path.startsWith('dsh/')) files.push({ path: path.slice(4), bytes: node.size, unpacked });
      else requireValue(!unpacked, 'native-asar-sidecar-outside-runtime');
    }
  };
  visit(raw.header, '', false, 0);
  requireValue(object(raw.header.files.dsh?.files), 'native-asar-runtime-missing');
  return files.sort((a, b) => a.path < b.path ? -1 : a.path > b.path ? 1 : 0);
}

export function preflightAsar(lock, installRoot) {
  requireValue(nativeLayout(lock) === 'asar-runtime', 'native-runtime-layout-unsupported');
  physical(installRoot, 'directory');
  const desktop = lock.components.desktop;
  const exeName = relativeName(desktop.installedExecutable.relativePath.replaceAll('\\', '/'));
  requireValue(!exeName.includes('/') && /\.exe$/iu.test(exeName) && hashValid(desktop.installedExecutable.sha256), 'native-carrier-lock-invalid');
  const executable = physical(join(installRoot, exeName), 'file');
  requireValue(hashFile(executable) === desktop.installedExecutable.sha256, 'native-carrier-hash-mismatch');
  const archive = physical(join(installRoot, 'resources', 'app.asar'), 'file');
  requireValue(lstatSync(archive).size <= limits.total, 'native-inventory-limit');
  const archiveSha256 = hashFile(archive);
  const raw = boundedHeader(archive);
  const headerFiles = headerRuntimeInventory(raw, lstatSync(archive).size);
  const descriptorEntry = headerFiles.find(f => f.path === 'desktop-runtime.json');
  requireValue(descriptorEntry && descriptorEntry.bytes <= limits.descriptor && !descriptorEntry.unpacked, 'native-asar-descriptor-invalid');
  let descriptorBytes;
  try { descriptorBytes = reader.extractFile(archive, 'dsh/desktop-runtime.json', false); }
  finally { reader.uncache(archive); }
  const descriptor = validateDescriptor(descriptorBytes, desktop.installedRuntimeDescriptor.sha256, desktop.releaseChannel.upstreamVersion);
  const expectedFiles = descriptor.files.map(({ path, bytes }) => ({ path, bytes }));
  requireValue(isDeepStrictEqual(headerFiles.filter(f => f.path !== 'desktop-runtime.json').map(({ path, bytes }) => ({ path, bytes })), expectedFiles), 'native-asar-header-inventory-mismatch');
  requireValue(descriptor.files.some(f => f.path === policy) && descriptor.files.some(f => f.path === hostEntry), 'native-runtime-entry-missing');
  const sidecar = `${archive}.unpacked`;
  if (lstatSync(sidecar, { throwIfNoEntry: false }) !== undefined) {
    physical(sidecar, 'directory');
    requireValue(readdirSync(sidecar).every(name => name === 'dsh'), 'native-asar-sidecar-outside-runtime');
  }
  const actual = physicalInventory(join(sidecar, 'dsh'));
  const unpacked = new Set(headerFiles.filter(f => f.unpacked).map(f => f.path));
  const expected = descriptor.files.filter(f => unpacked.has(f.path)).map(({ path, bytes, sha256 }) => ({ path, bytes, sha256 }));
  requireValue(isDeepStrictEqual(actual, expected), 'native-asar-sidecar-mismatch');
  reader.uncache(archive);
  requireValue(hashFile(archive) === archiveSha256, 'native-inconsistent-snapshot');
  return { executable, archive, archiveSha256, descriptor, descriptorSha256: sha256(descriptorBytes),
    runtimeRoot: join(archive, 'dsh'), executableSha256: desktop.installedExecutable.sha256,
    moduleResolutionPolicyUrl: pathToFileURL(join(archive, 'dsh', policy)).href,
    hostEntry: join(archive, 'dsh', hostEntry), unpackedCount: actual.length };
}

export function probeEnvironment(diagnosticRoot, ambient = process.env) {
  physical(diagnosticRoot, 'directory');
  for (const [key, value] of Object.entries(ambient)) {
    if (/^OneDrive/iu.test(key) && value) requireValue(!inside(resolve(value), diagnosticRoot), 'native-diagnostic-root-synchronized');
  }
  requireValue(!/(?:^|[\\/])OneDrive(?:[\\/ ]|$)/iu.test(diagnosticRoot), 'native-diagnostic-root-synchronized');
  const env = { ELECTRON_RUN_AS_NODE: '1', TEMP: diagnosticRoot, TMP: diagnosticRoot,
    USERPROFILE: diagnosticRoot, HOME: diagnosticRoot };
  for (const key of ['SystemRoot', 'WINDIR']) {
    const value = Object.entries(ambient).find(([name]) => name.toLowerCase() === key.toLowerCase())?.[1];
    if (value) { physical(value, 'directory'); env[key] = value; }
  }
  return env;
}

export function runAsarProbe(snapshot, provisioning, home, diagnosticRoot = tmpdir()) {
  const payload = { schemaVersion: 1, executable: snapshot.executable, runtimeRoot: snapshot.runtimeRoot,
    descriptorSha256: snapshot.descriptorSha256, archiveSha256: snapshot.archiveSha256,
    version: snapshot.descriptor.release.version, home, profile: provisioning.profileRoot,
    pluginRoot: provisioning.packageRoot, pluginName: provisioning.packageName,
    pluginVersion: provisioning.packageVersion, profileManifestSha256: provisioning.profileManifestSha256,
    pluginManifestSha256: provisioning.pluginManifestSha256, planSha256: provisioning.planSha256,
    profileMetadataSha256: provisioning.profileMetadataSha256 };
  const input = JSON.stringify(payload);
  requireValue(Buffer.byteLength(input) <= limits.output, 'native-probe-input-limit');
  const script = fileURLToPath(new URL('./native-electron-probe.mjs', import.meta.url));
  const result = spawnSync(snapshot.executable, ['--max-old-space-size=512', '--disable-warning=DEP0180', '--experimental-import-meta-resolve', script], {
    shell: false, windowsHide: true, cwd: physical(diagnosticRoot, 'directory'), env: probeEnvironment(diagnosticRoot),
    input, encoding: 'utf8', timeout: limits.timeout, maxBuffer: limits.output, killSignal: 'SIGKILL' });
  // Accept only fixed owned failure codes, never arbitrary parser/stderr text.
  if (!result.error && result.status === 1 && !result.signal && result.stderr === '' &&
    typeof result.stdout === 'string' && Buffer.byteLength(result.stdout) <= limits.output) {
    let failure; try { failure = JSON.parse(result.stdout); } catch { /* generic failure below */ }
    const codes = new Set(['native-probe-carrier-invalid', 'native-probe-profile-invalid', 'native-runtime-descriptor-mismatch',
      'native-runtime-descriptor-invalid', 'native-runtime-tree-mismatch', 'native-runtime-api-invalid', 'native-runtime-entry-missing',
      'native-runtime-import-outside-inventory', 'native-bundle-root-mismatch', 'native-generation-invalid',
      'native-generation-root-mismatch', 'native-shared-package-mismatch', 'native-shared-peer-unresolved',
      'native-shared-peer-resolution-mismatch', 'native-resolver-unavailable', 'native-resolver-disposal-mismatch',
      'native-inconsistent-snapshot', 'native-evidence-missing', 'native-evidence-unreadable',
      'native-receipt-store-invalid', 'native-receipt-owner-invalid', 'native-release-owned-extra',
      'native-user-dependency-metadata-invalid', 'native-package-snapshot-invalid', 'native-receipt-invalid',
      'native-provisioning-state-invalid', 'native-profile-composition-mismatch', 'native-state-receipt-mismatch']);
    if (object(failure) && Object.keys(failure).sort().join(',') === 'reason,schemaVersion,valid' &&
      failure.schemaVersion === 1 && failure.valid === false && codes.has(failure.reason)) throw new Error(failure.reason);
  }
  requireValue(!result.error && result.status === 0 && !result.signal, result.error?.code === 'ETIMEDOUT' ? 'native-probe-timeout' : 'native-probe-failed');
  requireValue(typeof result.stdout === 'string' && Buffer.byteLength(result.stdout) <= limits.output && !result.stderr, 'native-probe-output-invalid');
  let output; try { output = JSON.parse(result.stdout); } catch { throw new Error('native-probe-output-invalid'); }
  requireValue(object(output) && Object.keys(output).sort().join(',') ===
    'archiveSha256,descriptorSha256,fileCount,mode,peerCount,resolverDisposed,schemaVersion,valid' &&
    output.schemaVersion === 1 && output.valid === true && output.mode === 'metadata-cjs-esm' && output.resolverDisposed === true &&
    output.descriptorSha256 === snapshot.descriptorSha256 && output.archiveSha256 === snapshot.archiveSha256 &&
    output.fileCount === snapshot.descriptor.files.length && Number.isSafeInteger(output.peerCount) && output.peerCount >= 2,
  'native-probe-output-invalid');
  return output;
}
