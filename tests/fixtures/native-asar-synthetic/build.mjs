// Developer-only fixture recipe. Requires the existing source checkout dependencies;
// does not install anything. Outputs synthetic integrity fixtures, NEVER runtime proof.
import { createHash } from 'node:crypto';
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { physical } from '../../../tools/native-runtime-integrity.mjs';
const source = resolve(process.argv[2]);
const tempRoot = physical(resolve(process.argv[3]), 'directory');
const sourceRoot = mkdtempSync(join(tempRoot, 'synthetic-asar-source-'));
const require = createRequire(import.meta.url);
const upstream = require(join(source, 'node_modules/.pnpm/@electron+asar@3.4.1/node_modules/@electron/asar'));
const output = dirname(fileURLToPath(import.meta.url));
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const version = '0.1.6-synthetic-local.1';
const files = {};
const sharedPackages = [];
for (const name of ['@deepseek-ai/dsh', '@deepseek-ai/dsh-desktop-host', '@deepseek-ai/cordis',
  '@deepseek-ai/dsh-app-boot', '@deepseek-ai/dsh-base', '@deepseek-ai/dsh-web-app',
  '@deepseek-ai/dsh-authorization', '@deepseek-ai/schemastery']) {
  const path = `node_modules/${name}`;
  files[`${path}/package.json`] = JSON.stringify({ name, version, type: 'module', exports: { '.': './lib/index.js' } });
  files[`${path}/lib/index.js`] = '// SYNTHETIC NEGATIVE FIXTURE: no real runtime APIs.\nexport const synthetic = true;\n';
  sharedPackages.push({ name, path, version });
}
files['node_modules/@deepseek-ai/dsh-desktop-host/register-module-resolution-policy.mjs'] = '// SYNTHETIC NEGATIVE FIXTURE: never a production policy proof.\n';
files['node_modules/fixture-native/fixture.node'] = 'synthetic native bytes, not executable';
const descriptor = { schemaVersion: 1, platform: 'win32', arch: 'x64',
  release: { schemaVersion: 1, version, hostProtocolVersion: 3, nodeVersion: '24.13.0', pnpmVersion: '11.7.0' },
  sharedPackages: sharedPackages.sort((a, b) => a.name.localeCompare(b.name)),
  files: Object.entries(files).sort(([a], [b]) => a < b ? -1 : a > b ? 1 : 0)
    .map(([path, bytes]) => ({ path, bytes: Buffer.byteLength(bytes), sha256: hash(bytes), executable: false })) };
files['desktop-runtime.json'] = JSON.stringify(descriptor);
try {
  for (const [name, bytes] of Object.entries(files)) {
    const path = join(sourceRoot, 'dsh', name); mkdirSync(dirname(path), { recursive: true }); writeFileSync(path, bytes);
  }
  await upstream.createPackageWithOptions(sourceRoot, join(output, 'app.asar'), { unpack: '**/*.node' });
  writeFileSync(join(output, 'identity.json'), JSON.stringify({ syntheticOnly: true, runtimeProof: false,
    version, descriptorSha256: hash(files['desktop-runtime.json']), archiveSha256: hash(readFileSync(join(output, 'app.asar'))),
    generator: '@electron/asar@3.4.1 createPackageWithOptions', unpack: '**/*.node' }, null, 2) + '\n');
} finally { rmSync(sourceRoot, { recursive: true, force: true }); }
