// Explicit local carrier smoke: real existing Electron, SYNTHETIC negative archive.
// Not a runtime success test; never locates/downloads Electron or runs Desktop/Host.
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { hashFile, limits, physical } from '../tools/native-runtime-integrity.mjs';
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
  write(join(profile, 'package.json'), JSON.stringify({ dsh: { profile: { bundles: ['@deepseek-ai/dsh-base', '@deepseek-ai/dsh-web-app', 'synthetic-plugin'] } } }));
  write(join(pluginRoot, 'package.json'), JSON.stringify({ name: 'synthetic-plugin', version: '1.0.0' }));
  const input = { schemaVersion: 1, executable, runtimeRoot: join(archive, 'dsh'), descriptorSha256: identity.descriptorSha256,
    archiveSha256: identity.archiveSha256, version: identity.version, home, profile, pluginRoot,
    pluginName: 'synthetic-plugin', pluginVersion: '1.0.0', profileManifestSha256: hashFile(join(profile, 'package.json')),
    pluginManifestSha256: hashFile(join(pluginRoot, 'package.json')) };
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
  // Change a packed file without touching its header/descriptor; virtual inventory
  // must reject before any synthetic package/policy is imported.
  const bytes = readFileSync(archive); const at = bytes.indexOf(Buffer.from('// SYNTHETIC NEGATIVE FIXTURE: no real runtime APIs.'));
  assert.ok(at >= 0); bytes[at] ^= 1; writeFileSync(archive, bytes);
  assert.deepEqual(run(), { valid: false, reason: 'native-runtime-tree-mismatch', runtimeLoads: 0 });
  writeFileSync(archive, readFileSync(join(fixture, 'app.asar')));
  const backing = join(root, native); const backingBytes = readFileSync(backing); backingBytes[0] ^= 1; writeFileSync(backing, backingBytes);
  assert.deepEqual(run(), { valid: false, reason: 'native-runtime-tree-mismatch', runtimeLoads: 0 });
  // ASAR-aware inventory must not materialize packed files into diagnostic temp.
  assert.deepEqual(readdirSync(root).sort(), ['app.asar', 'app.asar.unpacked', 'home']);
  process.stdout.write(JSON.stringify({ valid: true, syntheticOnly: true, runtimeProof: false, formalReleaseAcceptance: false,
    checks: ['node-mode-only', 'missing-public-api-fails', 'packed-drift-before-import', 'unpacked-drift-before-import', 'no-packed-extraction'], executableSha256 }) + '\n');
} finally { rmSync(root, { recursive: true, force: true }); }
