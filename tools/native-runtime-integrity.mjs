// Ops-owned validation shared by the physical preflight and Node-mode probe.
// No installed-runtime imports, config loaders, or filesystem mutations.
import { createHash } from 'node:crypto';
import { closeSync, lstatSync, openSync, readSync, readdirSync, realpathSync } from 'node:fs';
import { dirname, isAbsolute, join, relative, resolve, sep } from 'node:path';

export const limits = Object.freeze({ header: 16 * 1024 * 1024, descriptor: 32 * 1024 * 1024,
  file: 512 * 1024 * 1024, files: 200000, total: 16 * 1024 ** 3, depth: 128, output: 16384, timeout: 30000 });
export const requireValue = (condition, code) => { if (!condition) throw new Error(code); };
export const sha256 = (bytes) => createHash('sha256').update(bytes).digest('hex');
export const object = (value) => value !== null && typeof value === 'object' && !Array.isArray(value);
export const hashValid = (value) => typeof value === 'string' && /^[a-f0-9]{64}$/u.test(value);
export const packageValid = (value) => typeof value === 'string' && /^(?:@[a-z0-9][a-z0-9._~-]*\/)?[a-z0-9][a-z0-9._~-]*$/u.test(value);
export function relativeName(name) {
  requireValue(typeof name === 'string' && name.length <= 32760 && name !== '' && !isAbsolute(name) &&
    !/[\\:\x00-\x1f<>"|?*]/u.test(name) && name.split('/').every(part => part && part !== '.' && part !== '..' &&
      !/[. ]$/u.test(part) && !/^(?:con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\.|$)/iu.test(part)), 'native-invalid-relative-path');
  return name;
}
export function inside(root, path) {
  const child = relative(root, path);
  return child === '' || (!isAbsolute(child) && child !== '..' && !child.startsWith(`..${sep}`));
}
export function physical(path, type) {
  requireValue(typeof path === 'string' && isAbsolute(path) && !path.startsWith('\\\\') &&
    !path.startsWith('//') && !path.slice(2).includes(':'), 'native-invalid-physical-path');
  let current = resolve(path);
  for (;;) {
    const stat = lstatSync(current);
    requireValue(!stat.isSymbolicLink() && realpathSync(current).toLowerCase() === current.toLowerCase(), 'native-reparse-path');
    const parent = dirname(current);
    if (parent === current) break;
    current = parent;
  }
  const stat = lstatSync(path);
  requireValue(type === 'file' ? stat.isFile() : stat.isDirectory(), 'native-physical-type-mismatch');
  return path;
}
export function hashFile(path) {
  const fd = openSync(path, 'r');
  try {
    const hash = createHash('sha256');
    const buffer = Buffer.allocUnsafe(1024 * 1024);
    for (let count; (count = readSync(fd, buffer, 0, buffer.length, null)) > 0;) hash.update(buffer.subarray(0, count));
    return hash.digest('hex');
  } finally { closeSync(fd); }
}
export function physicalInventory(root) {
  if (lstatSync(root, { throwIfNoEntry: false }) === undefined) return [];
  physical(root, 'directory');
  const files = []; const aliases = new Set(); let total = 0;
  const visit = (directory, depth) => {
    requireValue(depth <= limits.depth, 'native-inventory-limit');
    for (const entry of readdirSync(directory, { withFileTypes: true })) {
      const path = join(directory, entry.name);
      const name = relativeName(relative(root, path).split(sep).join('/'));
      requireValue(!aliases.has(name.toLowerCase()), 'native-path-alias'); aliases.add(name.toLowerCase());
      requireValue(aliases.size <= limits.files && !entry.isSymbolicLink(), 'native-reparse-or-inventory-limit');
      if (entry.isDirectory()) { physical(path, 'directory'); visit(path, depth + 1); }
      else {
        physical(path, 'file');
        const bytes = lstatSync(path).size; total += bytes;
        requireValue(bytes <= limits.file && total <= limits.total, 'native-inventory-limit');
        files.push({ path: name, bytes, sha256: hashFile(path) });
      }
    }
  };
  visit(root, 0);
  return files.sort((a, b) => a.path < b.path ? -1 : a.path > b.path ? 1 : 0);
}
export function validateDescriptor(bytes, expectedHash, version) {
  requireValue(bytes.length <= limits.descriptor && hashValid(expectedHash) && sha256(bytes) === expectedHash, 'native-runtime-descriptor-mismatch');
  const d = JSON.parse(bytes.toString('utf8'));
  const semver = /^v?(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-((?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*)(?:\.(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*))*))?(?:\+([0-9a-zA-Z-]+(?:\.[0-9a-zA-Z-]+)*))?$/u;
  const keys = (value, expected) => object(value) && Object.keys(value).sort().join(',') === expected;
  requireValue(keys(d, 'arch,files,platform,release,schemaVersion,sharedPackages') && d.schemaVersion === 1 && d.platform === 'win32' && d.arch === 'x64' &&
    keys(d.release, 'hostProtocolVersion,nodeVersion,pnpmVersion,schemaVersion,version') && d.release.schemaVersion === 1 && d.release.version === version && semver.test(version) &&
    d.release.hostProtocolVersion === 3 && semver.test(d.release.nodeVersion) && semver.test(d.release.pnpmVersion) &&
    Array.isArray(d.files) && d.files.length > 0 && d.files.length <= limits.files && Array.isArray(d.sharedPackages), 'native-runtime-descriptor-invalid');
  const names = new Set(); let total = 0; let previous = '';
  for (const file of d.files) {
    requireValue(keys(file, 'bytes,executable,path,sha256'), 'native-runtime-descriptor-invalid'); relativeName(file.path);
    requireValue(file.path !== 'desktop-runtime.json' && previous < file.path && !names.has(file.path.toLowerCase()) &&
      Number.isSafeInteger(file.bytes) && file.bytes >= 0 && file.bytes <= limits.file && hashValid(file.sha256) &&
      typeof file.executable === 'boolean', 'native-runtime-descriptor-invalid');
    names.add(file.path.toLowerCase()); previous = file.path; total += file.bytes;
  }
  requireValue(total <= limits.total, 'native-inventory-limit');
  // A file cannot also be a directory, including Windows case aliases.
  for (const file of d.files) {
    const parts = file.path.toLowerCase().split('/'); parts.pop();
    while (parts.length) { requireValue(!names.has(parts.join('/')), 'native-path-alias'); parts.pop(); }
  }
  const shared = new Set();
  for (const item of d.sharedPackages) {
    requireValue(keys(item, 'name,path,version') && packageValid(item.name) && item.path === `node_modules/${item.name}` &&
      typeof item.version === 'string' && semver.test(item.version) && !shared.has(item.name) &&
      names.has(`${item.path}/package.json`.toLowerCase()), 'native-shared-package-mismatch');
    shared.add(item.name);
  }
  for (const name of ['@deepseek-ai/dsh', '@deepseek-ai/dsh-desktop-host']) {
    requireValue(d.sharedPackages.some(p => p.name === name && p.version === version), 'native-shared-package-mismatch');
  }
  return d;
}
export function safeReason(error) {
  return /^native-[a-z-]+$/u.test(error?.message) ? error.message :
    error?.code === 'ENOENT' ? 'native-evidence-missing' : 'native-evidence-unreadable';
}
