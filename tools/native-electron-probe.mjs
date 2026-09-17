// Isolated diagnostic only. Never imports the Host entry or boots a composition.
import { lstatSync, readFileSync, readdirSync, realpathSync } from 'node:fs';
import { createRequire, isBuiltin, registerHooks } from 'node:module';
import { dirname, join, relative, resolve, sep } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { isDeepStrictEqual } from 'node:util';
import { hashFile, inside, limits, object, packageValid, physical, relativeName, requireValue,
  safeReason, sha256, validateDescriptor } from './native-runtime-integrity.mjs';

function inventory(root) {
  const files = []; const aliases = new Set();
  const visit = (directory, depth) => {
    requireValue(depth <= limits.depth, 'native-inventory-limit');
    for (const entry of readdirSync(directory, { withFileTypes: true })) {
      const path = join(directory, entry.name); const name = relativeName(relative(root, path).split(sep).join('/'));
      requireValue(!aliases.has(name.toLowerCase()) && aliases.size < limits.files, 'native-path-alias'); aliases.add(name.toLowerCase());
      const stat = lstatSync(path);
      requireValue(!stat.isSymbolicLink(), 'native-runtime-reparse-entry');
      if (stat.isDirectory()) visit(path, depth + 1);
      else {
        requireValue(stat.isFile() && stat.size <= limits.file, 'native-runtime-special-entry');
        // Electron openSync may copy packed files out; readFileSync is ASAR-aware
        // and reads virtual bytes without extraction. Sequential, bounded per file.
        if (name !== 'desktop-runtime.json') files.push({ path: name, bytes: stat.size, sha256: sha256(readFileSync(path)) });
      }
    }
  };
  visit(root, 0);
  return files.sort((a, b) => a.path < b.path ? -1 : a.path > b.path ? 1 : 0);
}

export async function probe(input) {
  requireValue(object(input) && input.schemaVersion === 1 && process.platform === 'win32' && process.arch === 'x64' &&
    typeof process.versions.electron === 'string' && typeof registerHooks === 'function' &&
    process.env.ELECTRON_RUN_AS_NODE === '1' &&
    !process.env.ELECTRON_NO_ASAR && resolve(process.execPath).toLowerCase() === resolve(input.executable).toLowerCase(), 'native-probe-carrier-invalid');
  physical(input.home, 'directory'); physical(input.profile, 'directory'); physical(input.pluginRoot, 'directory');
  requireValue(join(input.home, 'profiles', 'desktop') === input.profile && packageValid(input.pluginName) &&
    input.pluginRoot === join(input.profile, 'node_modules', input.pluginName), 'native-probe-profile-invalid');
  const descriptorPath = join(input.runtimeRoot, 'desktop-runtime.json');
  requireValue(lstatSync(descriptorPath).size <= limits.descriptor, 'native-inventory-limit');
  const descriptor = validateDescriptor(readFileSync(descriptorPath), input.descriptorSha256, input.version);
  const files = inventory(input.runtimeRoot);
  requireValue(isDeepStrictEqual(files, descriptor.files.map(({ path, bytes, sha256 }) => ({ path, bytes, sha256 }))), 'native-runtime-tree-mismatch');
  const attested = new Set(files.map(f => resolve(input.runtimeRoot, f.path).toLowerCase()));
  const metadata = (path) => {
    requireValue(attested.has(resolve(path).toLowerCase()), 'native-runtime-entry-missing');
    return JSON.parse(readFileSync(path, 'utf8'));
  };
  for (const shared of descriptor.sharedPackages) {
    const m = metadata(join(input.runtimeRoot, shared.path, 'package.json'));
    requireValue(m.name === shared.name && m.version === shared.version, 'native-shared-package-mismatch');
  }
  // Recheck the physical metadata supplied by the outer provisioning acceptance.
  const profileManifest = join(input.profile, 'package.json'); const pluginManifest = join(input.pluginRoot, 'package.json');
  requireValue(hashFile(profileManifest) === input.profileManifestSha256 && hashFile(pluginManifest) === input.pluginManifestSha256, 'native-inconsistent-snapshot');
  const profileData = JSON.parse(readFileSync(profileManifest, 'utf8'));
  const pluginData = JSON.parse(readFileSync(pluginManifest, 'utf8'));
  requireValue(pluginData.name === input.pluginName && pluginData.version === input.pluginVersion &&
    isDeepStrictEqual(profileData.dsh?.profile?.bundles, ['@deepseek-ai/dsh-base', '@deepseek-ai/dsh-web-app', input.pluginName]), 'native-probe-profile-invalid');
  const hostManifest = join(input.runtimeRoot, 'node_modules/@deepseek-ai/dsh-desktop-host/package.json');
  const installAnchor = join(input.runtimeRoot, 'node_modules/@deepseek-ai/dsh/package.json');
  metadata(hostManifest); metadata(installAnchor);
  const policy = join(input.runtimeRoot, 'node_modules/@deepseek-ai/dsh-desktop-host/register-module-resolution-policy.mjs');
  requireValue(attested.has(policy.toLowerCase()), 'native-runtime-entry-missing');

  // Only now may runtime code load. This guard does NOT resolve/map packages or
  // replace the production policy: it forbids execution of unattested transitive
  // modules while leaving resolve-only queries to the shipped production hooks.
  const loadGuard = registerHooks({ load(url, context, nextLoad) {
    if (!isBuiltin(url)) {
      requireValue(url.startsWith('file:'), 'native-runtime-import-outside-inventory');
      let path = resolve(fileURLToPath(url));
      const sidecar = `${dirname(input.runtimeRoot)}.unpacked${sep}dsh${sep}`;
      if (path.startsWith(sidecar)) path = join(input.runtimeRoot, path.slice(sidecar.length));
      requireValue(attested.has(path.toLowerCase()), 'native-runtime-import-outside-inventory');
    }
    return nextLoad(url, context);
  } });
  const oldArgv = process.argv; const oldHome = process.env.DSH_HOME;
  let ctx; let peerCount = 0;
  const importRoot = async (name) => {
    const root = join(input.runtimeRoot, 'node_modules', name);
    const manifest = metadata(join(root, 'package.json'));
    requireValue(manifest.name === name, 'native-runtime-api-invalid');
    const url = import.meta.resolve(name, pathToFileURL(installAnchor).href);
    requireValue(url.startsWith('file:') && inside(root, fileURLToPath(url)) && attested.has(resolve(fileURLToPath(url)).toLowerCase()), 'native-runtime-api-invalid');
    return import(url);
  };
  try {
    // Same order as production: exact attested policy first, then public app-boot
    // generation + PluginPackages. Explicit validated home is not an ambient override.
    process.env.DSH_HOME = input.home;
    process.argv = [process.execPath, join(input.runtimeRoot, 'node_modules/@deepseek-ai/dsh-desktop-host/lib/index.js'), input.runtimeRoot, input.profile];
    try { await import(pathToFileURL(policy).href); } finally { process.argv = oldArgv; }
    const { Context } = await importRoot('@deepseek-ai/cordis');
    const { createProfileResolutionGeneration, resolveBundleDir, PluginPackages } = await importRoot('@deepseek-ai/dsh-app-boot');
    requireValue(typeof Context === 'function' && typeof createProfileResolutionGeneration === 'function' &&
      typeof resolveBundleDir === 'function' && typeof PluginPackages === 'function', 'native-runtime-api-invalid');
    const layers = profileData.dsh.profile.bundles.map(packageName => {
      const packageDir = resolveBundleDir('windows-ops-check', packageName, installAnchor, input.profile);
      const expected = packageName === input.pluginName ? input.pluginRoot : join(input.runtimeRoot, 'node_modules', packageName);
      requireValue(realpathSync(packageDir) === realpathSync(expected), 'native-bundle-root-mismatch');
      if (packageName !== input.pluginName) metadata(join(packageDir, 'package.json'));
      return { packageName, packageDir, patchPath: join(packageDir, 'cordis.yml'), patches: [] };
    });
    const profile = { name: 'desktop', dir: input.profile, layers, patchPath: join(input.profile, 'cordis.patch.yml'), patches: [], patchReload: false };
    const generation = await createProfileResolutionGeneration({ installAnchor, profile, home: input.home });
    requireValue(generation.profilesDir === join(input.home, 'profiles') && generation.profileDir === input.profile &&
      Array.isArray(generation.entries), 'native-generation-invalid');
    for (const entry of generation.entries) {
      requireValue(packageValid(entry.name), 'native-generation-invalid');
      if (entry.scope === 'installation') {
        requireValue(inside(input.runtimeRoot, entry.packageDir), 'native-generation-root-mismatch');
        const manifest = metadata(join(entry.packageDir, 'package.json'));
        requireValue(manifest.name === entry.name && manifest.version === entry.version, 'native-generation-root-mismatch');
      } else {
        requireValue(entry.scope === 'profile' && inside(input.profile, entry.packageDir), 'native-generation-root-mismatch');
        physical(entry.packageDir, 'directory');
      }
    }
    const peers = new Set(['@deepseek-ai/dsh-authorization', '@deepseek-ai/schemastery']);
    for (const name of Object.keys(pluginData.peerDependencies ?? {})) {
      if (descriptor.sharedPackages.some(p => p.name === name) || pluginData.peerDependenciesMeta?.[name]?.optional !== true) peers.add(name);
    }
    const resolutionSnapshot = () => [...peers].flatMap(peer => [hostManifest, pluginManifest].flatMap(anchor => ['cjs', 'esm'].map(mode => {
      try { return { peer, anchor, mode, value: mode === 'cjs' ? createRequire(anchor).resolve(peer) : import.meta.resolve(peer, pathToFileURL(anchor).href) }; }
      catch (error) { return { peer, anchor, mode, error: typeof error.code === 'string' ? error.code : 'unresolved' }; }
    })));
    const beforeResolution = resolutionSnapshot();
    ctx = new Context();
    try {
      await ctx.plugin(PluginPackages, { generation, behavior: 'enforce' });
      const service = ctx.get('pluginPackages'); requireValue(service && typeof service.packageOf === 'function', 'native-resolver-unavailable');
      for (const peer of peers) {
        const shared = descriptor.sharedPackages.find(p => p.name === peer);
        requireValue(shared && generation.entries.some(e => e.name === peer && e.scope === 'installation' && e.version === shared.version &&
          realpathSync(e.packageDir) === realpathSync(join(input.runtimeRoot, shared.path))), 'native-shared-peer-unresolved');
        const expectedRoot = realpathSync(join(input.runtimeRoot, shared.path));
        for (const anchor of [hostManifest, pluginManifest]) {
          const info = service.packageOf(peer, pathToFileURL(anchor).href);
          requireValue(info && info.name === peer && info.version === shared.version && realpathSync(info.dir) === expectedRoot &&
            realpathSync(info.manifestPath) === realpathSync(join(expectedRoot, 'package.json')), 'native-shared-peer-resolution-mismatch');
        }
        for (const mode of ['cjs', 'esm']) {
          const resolvePeer = anchor => mode === 'cjs' ? createRequire(anchor).resolve(peer) : fileURLToPath(import.meta.resolve(peer, pathToFileURL(anchor).href));
          const host = realpathSync(resolvePeer(hostManifest)); const plugin = realpathSync(resolvePeer(pluginManifest));
          requireValue(host === plugin && inside(expectedRoot, host) && attested.has(host.toLowerCase()), 'native-shared-peer-resolution-mismatch');
        }
        peerCount++;
      }
    } finally {
      await ctx.fiber.dispose(); ctx = undefined;
      requireValue(isDeepStrictEqual(resolutionSnapshot(), beforeResolution), 'native-resolver-disposal-mismatch');
    }
  } finally {
    try { if (ctx) await ctx.fiber.dispose(); }
    finally {
      process.argv = oldArgv;
      if (oldHome === undefined) delete process.env.DSH_HOME; else process.env.DSH_HOME = oldHome;
      loadGuard.deregister();
    }
  }
  requireValue(hashFile(profileManifest) === input.profileManifestSha256 && hashFile(pluginManifest) === input.pluginManifestSha256 &&
    sha256(readFileSync(descriptorPath)) === input.descriptorSha256, 'native-inconsistent-snapshot');
  return { schemaVersion: 1, valid: true, mode: 'metadata-cjs-esm', resolverDisposed: true,
    fileCount: files.length, peerCount, descriptorSha256: input.descriptorSha256, archiveSha256: input.archiveSha256 };
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  try {
    const chunks = []; let size = 0;
    for await (const chunk of process.stdin) {
      size += chunk.length; requireValue(size <= limits.output, 'native-probe-input-limit'); chunks.push(chunk);
    }
    const input = JSON.parse(Buffer.concat(chunks).toString('utf8'));
    process.stdout.write(JSON.stringify(await probe(input)));
  } catch (error) {
    // Never return parser text, native-loader errors, stderr, stack or manifests.
    process.stdout.write(JSON.stringify({ schemaVersion: 1, valid: false, reason: safeReason(error) }));
    process.exitCode = 1;
  }
}
