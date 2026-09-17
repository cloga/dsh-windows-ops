// Explicit local carrier smoke: real existing Electron, SYNTHETIC negative archive.
// Not a runtime success test; never locates/downloads Electron or runs Desktop/Host.
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, unlinkSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { hashFile, limits, physical, sha256 } from '../tools/native-runtime-integrity.mjs';
import { readNativeProfileMetadata } from '../tools/native-profile-metadata.mjs';
import { probeEnvironment } from '../tools/native-asar-runtime.mjs';
assert.equal(process.argv.length, 4, 'usage: node tests/native-asar-carrier-negative.mjs <exact-existing-electron.exe> <private-temp-root>');
const executable = physical(resolve(process.argv[2]), 'file');
const executableSha256 = hashFile(executable);
const tempRoot = physical(resolve(process.argv[3]), 'directory');
probeEnvironment(tempRoot); // reject synchronized/reparse diagnostic roots before creation
const root = mkdtempSync(join(tempRoot, 'carrier-negative-'));
const fixture = fileURLToPath(new URL('./fixtures/native-asar-synthetic/', import.meta.url));
const identity = JSON.parse(readFileSync(join(fixture, 'identity.json'), 'utf8'));
const archive = join(root, 'app.asar');
const native = 'app.asar.unpacked/dsh/node_modules/fixture-native/fixture.node';
const home = join(root, 'home'); const profile = join(home, 'profiles', 'desktop');
const pluginRoot = join(profile, 'node_modules', 'synthetic-plugin');
const write = (path, bytes) => { mkdirSync(dirname(path), { recursive: true }); writeFileSync(path, bytes); };
try {
  write(archive, readFileSync(join(fixture, 'app.asar')));
  write(join(root, native), readFileSync(join(fixture, native)));
  // Inert ownership metadata, not published receipts or a working runtime.
  const artifactBytes = 'synthetic metadata artifact, not a package';
  const source = { schemaVersion: 1, type: 'githubRelease', owner: 'fixture', repo: 'synthetic-plugin', tag: 'v1.0.0',
    asset: 'plugin.tgz', assetId: 1, packageName: 'synthetic-plugin', version: '1.0.0', size: Buffer.byteLength(artifactBytes),
    sha256: sha256(artifactBytes), targetCommit: 'a'.repeat(40), checksumManifest: { format: 'sha256sums', asset: 'SHA256SUMS',
      assetId: 2, url: 'https://github.com/fixture/synthetic-plugin/releases/download/v1.0.0/SHA256SUMS', size: 1, sha256: 'b'.repeat(64) } };
  const capability = { id: 'desktopNativeVerifiedRelease', schemaVersion: 1, sourceSchemaVersion: 1, receiptSchemaVersion: 1 };
  const plan = { schemaVersion: 1, mode: 'exact', plugins: [{ required: true, source }] };
  const receipt = { schemaVersion: 1, capability, source, releaseId: 1, assetId: source.assetId, packageName: source.packageName,
    version: source.version, artifactSha256: source.sha256, states: { staged: true, health: 'passed', activated: true, rolledBack: false, verified: true } };
  write(join(root, 'desktop-provisioning/plan.json'), JSON.stringify(plan));
  write(join(profile, 'desktop-plugin-receipts.json'), JSON.stringify({ schemaVersion: 1,
    receipts: { 'synthetic-plugin': receipt }, owners: { 'synthetic-plugin': 'user' } }));
  write(join(profile, 'desktop-plugin-provisioning-state.json'), JSON.stringify({ schemaVersion: 1,
    capability: { id: 'desktopNativePluginProvisioning', schemaVersion: 1, planSchemaVersion: 1, stateSchemaVersion: 1, pluginCapability: capability },
    planSha256: sha256(JSON.stringify(plan)), composition: 'active', plugins: [{ name: source.packageName, version: source.version,
      required: true, status: 'active', source, receipt }], removed: [], rolledBack: false, verified: true }));
  write(join(profile, '.desktop-plugin-artifacts', `${source.sha256}.tgz`), artifactBytes);
  write(join(profile, 'package.json'), JSON.stringify({ name: '@deepseek-ai/dsh-desktop-runtime', private: true, version: identity.version,
    dependencies: { 'synthetic-plugin': `file:.desktop-plugin-artifacts/${source.sha256}.tgz` },
    dsh: { profile: { bundles: ['@deepseek-ai/dsh-base', '@deepseek-ai/dsh-web-app', 'synthetic-plugin'] } } }));
  write(join(pluginRoot, 'package.json'), JSON.stringify({ name: 'synthetic-plugin', version: '1.0.0' }));
  const metadata = readNativeProfileMetadata(profile, plan);
  const input = { schemaVersion: 1, executable, runtimeRoot: join(archive, 'dsh'), descriptorSha256: identity.descriptorSha256,
    archiveSha256: identity.archiveSha256, version: identity.version, home, profile, pluginRoot,
    pluginName: 'synthetic-plugin', pluginVersion: '1.0.0', profileManifestSha256: hashFile(join(profile, 'package.json')),
    pluginManifestSha256: hashFile(join(pluginRoot, 'package.json')), planSha256: metadata.planSha256,
    profileMetadataSha256: metadata.snapshotSha256 };
  // Test-only load counter outside the production probe. It observes, never
  // resolves or permits a target; no fixture source/public API is substituted.
  const bootstrap = `
    import { registerHooks } from 'node:module';
    import { pathToFileURL } from 'node:url';
    import { probe } from ${JSON.stringify(new URL('../tools/native-electron-probe.mjs', import.meta.url).href)};
    const chunks = []; let length = 0;
    for await (const chunk of process.stdin) { length += chunk.length; if (length > 16384) throw new Error('bounded input'); chunks.push(chunk); }
    const input = JSON.parse(Buffer.concat(chunks).toString('utf8'));
    let runtimeLoads = 0;
    const prefix = pathToFileURL(input.runtimeRoot).href + '/';
    const counter = registerHooks({load(url, context, nextLoad) { if (url.startsWith(prefix)) runtimeLoads++; return nextLoad(url, context); }});
    try { await probe(input); process.stdout.write(JSON.stringify({valid:true,runtimeLoads})); }
    catch (error) { process.stdout.write(JSON.stringify({valid:false,reason:/^native-[a-z-]+$/.test(error.message)?error.message:'unexpected',runtimeLoads})); process.exitCode=1; }
    finally { counter.deregister(); }
  `;
  const run = () => {
    assert.equal(hashFile(executable), executableSha256);
    const result = spawnSync(executable, ['--max-old-space-size=512', '--disable-warning=DEP0180', '--experimental-import-meta-resolve',
      '--input-type=module', '--eval', bootstrap], {
      shell: false, windowsHide: true, cwd: root, env: probeEnvironment(root), input: JSON.stringify(input), encoding: 'utf8',
      timeout: limits.timeout, maxBuffer: limits.output, killSignal: 'SIGKILL' });
    assert.ok(!result.error, 'bounded Node-mode carrier launch must complete');
    assert.equal(result.status, 1, 'synthetic runtime must NEVER pass');
    assert.equal(result.stderr, '', 'no raw loader/stderr output');
    assert.equal(hashFile(executable), executableSha256);
    return JSON.parse(result.stdout);
  };
  // Sound complete bytes reach the explicit missing public-API check, not Host boot.
  const missingApi = run();
  assert.equal(missingApi.valid, false); assert.equal(missingApi.reason, 'native-runtime-api-invalid');
  assert.ok(missingApi.runtimeLoads > 0);
  const storePath = join(profile, 'desktop-plugin-receipts.json'); const storeBytes = readFileSync(storePath);
  const changedStore = JSON.parse(storeBytes); changedStore.owners['synthetic-plugin'] = 'release';
  writeFileSync(storePath, JSON.stringify(changedStore));
  assert.deepEqual(run(), { valid: false, reason: 'native-inconsistent-snapshot', runtimeLoads: 0 });
  writeFileSync(storePath, storeBytes);
  const snapshotsPath = join(profile, 'desktop-plugin-package-locks.json');
  writeFileSync(snapshotsPath, JSON.stringify({ schemaVersion: 1, packages: {} }));
  assert.deepEqual(run(), { valid: false, reason: 'native-inconsistent-snapshot', runtimeLoads: 0 });
  unlinkSync(snapshotsPath);
  // Change a packed file without touching its header/descriptor; virtual inventory
  // must reject before any synthetic package/policy is imported.
  const bytes = readFileSync(archive); const at = bytes.indexOf(Buffer.from('// SYNTHETIC NEGATIVE FIXTURE: no real runtime APIs.'));
  assert.ok(at >= 0); bytes[at] ^= 1; writeFileSync(archive, bytes);
  assert.deepEqual(run(), { valid: false, reason: 'native-runtime-tree-mismatch', runtimeLoads: 0 });
  writeFileSync(archive, readFileSync(join(fixture, 'app.asar')));
  const backing = join(root, native); const backingBytes = readFileSync(backing); backingBytes[0] ^= 1; writeFileSync(backing, backingBytes);
  assert.deepEqual(run(), { valid: false, reason: 'native-runtime-tree-mismatch', runtimeLoads: 0 });
  // ASAR-aware inventory must not materialize packed files into diagnostic temp.
  assert.deepEqual(readdirSync(root).sort(), ['app.asar', 'app.asar.unpacked', 'desktop-provisioning', 'home']);
  process.stdout.write(JSON.stringify({ valid: true, syntheticOnly: true, runtimeProof: false, formalReleaseAcceptance: false,
    checks: ['node-mode-only', 'missing-public-api-fails', 'ownership-drift-before-import', 'snapshot-presence-drift-before-import', 'packed-drift-before-import', 'unpacked-drift-before-import', 'no-packed-extraction'], executableSha256 }) + '\n');
} finally { rmSync(root, { recursive: true, force: true }); }
