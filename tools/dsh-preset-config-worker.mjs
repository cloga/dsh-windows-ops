import { readFileSync, lstatSync, realpathSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { dirname, isAbsolute, relative, resolve, sep } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { registerHooks, syncBuiltinESMExports } from 'node:module';
import net from 'node:net';
import tls from 'node:tls';
import http from 'node:http';
import https from 'node:https';
import dgram from 'node:dgram';
import dns from 'node:dns';

const request = JSON.parse(readFileSync(0, 'utf8'));
const emit = process.stdout.write.bind(process.stdout);
const exit = process.exit.bind(process);
const action = 'Review the preset and exact target artifacts before retrying; do not overwrite user instructions.';
const diagnostics = [];
const rows = [];
const packagePattern = /^(?:@[a-z0-9][a-z0-9._-]*\/)?[a-z0-9][a-z0-9._-]*$/;
const versionPattern = /^\d+\.\d+\.\d+(?:-[a-zA-Z0-9.-]+)?(?:\+[a-zA-Z0-9.-]+)?$/;
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const fail = (code, context = {}, key = '') => {
  if (diagnostics.length >= 256) throw new Error('limit');
  diagnostics.push({ preset: '', row: '', plugin: '', version: '', ...context, key, code, action });
};
const physical = path => {
  const full = resolve(path);
  if (realpathSync(full).toLowerCase() !== full.toLowerCase()) throw new Error('path');
  let cursor = full;
  while (true) {
    if (lstatSync(cursor).isSymbolicLink()) throw new Error('path');
    if (cursor.toLowerCase() === resolve(request.root).toLowerCase()) break;
    const parent = dirname(cursor);
    if (parent === cursor) break;
    cursor = parent;
  }
  return full;
};

// Permission mode denies writes, subprocesses, workers and native addons. Network
// entrypoints are additionally disabled because Node 24 permissions do not cover net.
const denied = () => { throw new Error('preflight-side-effect-denied'); };
net.Socket.prototype.connect = denied;
net.Server.prototype.listen = denied;
net.connect = net.createConnection = tls.connect = denied;
http.request = http.get = https.request = https.get = denied;
dgram.createSocket = denied;
for (const key of ['bind', 'send', 'connect']) dgram.Socket.prototype[key] = denied;
for (const key of Object.keys(dns)) {
  if (/^(lookup|resolve|reverse)/.test(key) && typeof dns[key] === 'function') dns[key] = denied;
}
for (const key of Object.keys(dns.promises)) {
  if (/^(lookup|resolve|reverse)/.test(key) && typeof dns.promises[key] === 'function') dns.promises[key] = denied;
}
for (const resolver of [dns.Resolver, dns.promises.Resolver]) {
  for (const key of Object.getOwnPropertyNames(resolver.prototype)) {
    if (/^(resolve|reverse)/.test(key)) resolver.prototype[key] = denied;
  }
}
globalThis.fetch = denied;
globalThis.WebSocket = denied;
globalThis.EventSource = denied;
syncBuiltinESMExports();
process.stdout.write = process.stderr.write = () => true;
for (const key of ['log', 'info', 'warn', 'error', 'debug', 'dir', 'trace']) console[key] = () => {};

try {
  const root = physical(request.root);
  const snapshots = new Map(request.files.map(item => [item.path, item.sha256]));
  const checkedPath = path => {
    const full = physical(path);
    const local = relative(root, full);
    if (!local || isAbsolute(local) || local.startsWith(`..${sep}`)) throw new Error('target');
    const expected = snapshots.get(local.split(sep).join('/'));
    if (!expected || hash(readFileSync(full)) !== expected) throw new Error('target');
    return full;
  };
  const base = pathToFileURL(checkedPath(resolve(root, request.entrypoint))).href;
  registerHooks({
    resolve(specifier, context, nextResolve) {
      const answer = nextResolve(specifier, context);
      if (answer.url.startsWith('node:')) {
        if (['node:inspector', 'node:inspector/promises'].includes(answer.url)) throw new Error('side-effect');
        return answer;
      }
      if (!answer.url.startsWith('file:')) throw new Error('target');
      checkedPath(fileURLToPath(answer.url));
      return answer;
    },
    load(url, context, nextLoad) {
      if (url.startsWith('file:')) checkedPath(fileURLToPath(url));
      return nextLoad(url, context);
    },
  });
  const targetImport = async name => {
    const url = import.meta.resolve(name, base);
    if (!url.startsWith('file:')) throw new Error('target');
    const entry = checkedPath(fileURLToPath(url));
    let dir = dirname(entry);
    let manifest;
    while (dir !== root && dir.startsWith(root + sep)) {
      const candidate = resolve(dir, 'package.json');
      if (snapshots.has(relative(root, candidate).split(sep).join('/'))) {
        manifest = JSON.parse(readFileSync(checkedPath(candidate), 'utf8'));
        break;
      }
      dir = dirname(dir);
    }
    if (!manifest || manifest.name !== name || !versionPattern.test(manifest.version)) throw new Error('identity');
    return { exports: await import(url), version: manifest.version };
  };
  const yamlModule = await targetImport('js-yaml');
  const yaml = yamlModule.exports.default ?? yamlModule.exports;
  const include = await targetImport('@deepseek-ai/cordis-plugin-include');
  const dialect = include.exports.entryListSchema;
  if (typeof yaml.load !== 'function' || !dialect) throw new Error('yaml-contract');

  const dynamic = (value, seen = new Set(), depth = 0) => {
    if (depth > 64) throw new Error('depth');
    if (!value || typeof value !== 'object') return false;
    if (seen.has(value)) throw new Error('cycle');
    if (Object.hasOwn(value, '__jsExpr')) return true;
    seen.add(value);
    const found = Object.values(value).some(item => dynamic(item, seen, depth + 1));
    seen.delete(value);
    return found;
  };
  // Only schema-declared keys may enter diagnostics. Dictionary keys may themselves
  // be secrets, so unproven path segments are replaced rather than regex-sanitized.
  const schemaPath = (schema, path) => {
    let result = '$';
    let current = schema;
    for (const entry of Array.isArray(path) ? path.slice(0, 32) : []) {
      const key = entry && typeof entry === 'object' ? entry.key : entry;
      if (typeof key === 'string' && /^[a-zA-Z_][a-zA-Z0-9_-]{0,63}$/.test(key) &&
          current?.dict && Object.hasOwn(current.dict, key)) {
        result += '.' + key;
        current = current.dict[key];
      } else {
        result += '.*';
        current = undefined;
      }
    }
    return result;
  };
  let rowCount = 0;
  const walk = async (list, preset, parent = '', depth = 0, ids = new Set()) => {
    if (!Array.isArray(list) || depth > 32) { fail('entry-list-invalid', { preset, row: parent }); return; }
    for (const [index, row] of list.entries()) {
      if (++rowCount > 4096) throw new Error('limit');
      const context = { preset, row: parent + String(index + 1), plugin: '', version: '' };
      if (!row || typeof row !== 'object' || Array.isArray(row) ||
          typeof row.name !== 'string' || !row.name) { fail('entry-invalid', context); continue; }
      if (row.id !== undefined && (typeof row.id !== 'string' || ids.has(row.id))) {
        fail('entry-id-conflict', context); continue;
      }
      ids.add(row.id);
      if (row.group !== undefined && row.group !== null && typeof row.group !== 'boolean') {
        fail('dynamic-group-unsupported', context); continue;
      }
      if (row.group === true) {
        if (row.name !== 'group') { fail('group-plugin-unsupported', context); continue; }
        await walk(row.config, preset, context.row + '.', depth + 1, ids);
        continue;
      }
      if (!packagePattern.test(row.name)) { fail('plugin-specifier-unsupported', context); continue; }
      context.plugin = row.name;
      // Even currently disabled rows may be re-enabled or resume in another context.
      if (dynamic(row.config)) { fail('dynamic-config-unsupported', context); continue; }
      let loaded;
      try { loaded = await targetImport(row.name); }
      catch { fail('plugin-unresolvable-or-import-unsupported', context); continue; }
      context.version = loaded.version;
      let plugin = loaded.exports.default ?? loaded.exports;
      if (plugin?.__esModule) plugin = plugin.default ?? plugin;
      if ((typeof plugin !== 'function' && typeof plugin?.apply !== 'function') ||
          plugin?.[Symbol.for('cordis.group')]) {
        fail('plugin-contract-unsupported', context); continue;
      }
      if (loaded.exports.Config !== undefined && loaded.exports.Config !== plugin.Config) {
        fail('schema-export-conflict', context); continue;
      }
      const schema = plugin.Config;
      if (!schema) {
        rows.push({ ...context, status: 'schema-less-passthrough' });
        continue;
      }
      if (schema['~standard']?.version !== 1 || typeof schema['~standard']?.validate !== 'function') {
        fail('schema-contract-unsupported', context); continue;
      }
      try {
        const result = schema['~standard'].validate(structuredClone(row.config));
        if (!result || typeof result !== 'object' || 'then' in result ||
            (!Object.hasOwn(result, 'value') && !Object.hasOwn(result, 'issues'))) {
          fail('schema-result-unsupported', context); continue;
        }
        if (result.issues) {
          if (!Array.isArray(result.issues) || !result.issues.length) {
            fail('schema-result-unsupported', context); continue;
          }
          for (const issue of result.issues) fail('config-invalid', context, schemaPath(schema, issue.path));
        } else rows.push({ ...context, status: 'schema-valid' });
      } catch {
        fail('schema-validation-failed', context);
      }
    }
  };
  for (const manifest of request.manifests) {
    let content;
    // Paths are scoped by the parent; printable diagnostics remain relative and bounded.
    const preset = /^\.agent-presets\/[^/\\\x00-\x1f]{1,128}\/agent\.cordis\.yml$/.test(manifest.relative)
      ? manifest.relative : '.agent-presets/<redacted>/agent.cordis.yml';
    try {
      // Ancestor checks were done outside permission mode; only the granted leaf is read here.
      if (lstatSync(manifest.path).isSymbolicLink() ||
          realpathSync(manifest.path).toLowerCase() !== resolve(manifest.path).toLowerCase()) throw new Error('path');
      content = readFileSync(manifest.path);
      if (hash(content) !== manifest.sha256) throw new Error('changed');
    } catch { fail('preset-input-changed', { preset }); continue; }
    let list;
    try { list = yaml.load(content.toString('utf8'), { schema: dialect }); }
    catch { fail('manifest-invalid', { preset }); continue; }
    await walk(list, preset);
  }
  // Do not return success after a concurrent edit or target replacement during validation.
  for (const manifest of request.manifests) {
    if (hash(readFileSync(manifest.path)) !== manifest.sha256) fail('preset-input-changed');
  }
  for (const file of request.files) checkedPath(resolve(root, file.path));
} catch {
  fail('target-or-validator-unsupported');
}
emit(JSON.stringify({
  valid: diagnostics.length === 0,
  status: diagnostics.length ? 'user-preset-config-blocked' : 'user-preset-config-verified',
  diagnostics, rows,
}));
exit(0);
