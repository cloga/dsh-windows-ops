// preflight-check.mjs - DSH startup preflight: verify the session store is healthy
// BEFORE the app starts, so corrupt/duplicate session data never turns into a
// "app won't boot" surprise.
//
// Checks (all read-only; --fix moves bad copies into DSH_HOME/tools/quarantine/):
//   1. no duplicate parsed header ids across project dirs
//   2. no explicit backup / quarantine / tooling dirs INSIDE sessions/ (the DSH
//      scanner treats every project child as an active session)
//   3. every session.jsonl.zstd: its first frame is exactly one JSON header line,
//      all frames decode, AND header.cwd matches the project dir's decoded cwd
//   4. (optional --smoke) start the web backend with an isolated DSH_HOME copy,
//      wait for healthy, then stop it - a full boot test in the sandbox.
//
// Usage:
//   node preflight-check.mjs [--fix] [--smoke]
// Env: DSH_HOME (default ~/.dsh)
import fs from 'node:fs';
import crypto from 'node:crypto';
import os from 'node:os';
import path from 'node:path';
import { execFile, spawn } from 'node:child_process';
import { promisify } from 'node:util';
import { fileURLToPath, pathToFileURL } from 'node:url';

const execP = promisify(execFile);
const dshHome = process.env.DSH_HOME || path.join(os.homedir(), '.dsh');
const sessionsRoot = path.join(dshHome, 'sessions');
const quarantineRoot = path.join(dshHome, 'tools', 'quarantine');
const args = process.argv.slice(2);
const doFix = args.includes('--fix');
const doSmoke = args.includes('--smoke');

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const zstdPath = process.env.DSH_ZSTD
  || path.join(scriptDir, 'vendor', 'dsh-zstd', 'types', 'zstd.js');
const zstd = await import(pathToFileURL(zstdPath).href);

function log(s) { console.log(s); }
function warn(s) { console.warn('[WARN] ' + s); }
function err(s) { console.error('[ERROR] ' + s); }

function sha256(bytes) {
  return crypto.createHash('sha256').update(bytes).digest('hex');
}

function runtimeTreeState(root) {
  const entries = [];
  let totalBytes = 0;
  let reparseEntryCount = 0;
  function visit(directory) {
    for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
      const absolute = path.join(directory, entry.name);
      const stat = fs.lstatSync(absolute);
      if (stat.isSymbolicLink()) {
        reparseEntryCount++;
        continue;
      }
      if (stat.isDirectory()) {
        visit(absolute);
        continue;
      }
      if (!stat.isFile()) {
        reparseEntryCount++;
        continue;
      }
      const bytes = fs.readFileSync(absolute);
      totalBytes += bytes.length;
      entries.push({
        relativePath: path.relative(root, absolute).split(path.sep).join('/'),
        sha256: sha256(bytes),
      });
    }
  }
  visit(root);
  const pathComparer = new Intl.Collator('en-US', { sensitivity: 'variant' });
  entries.sort((left, right) => pathComparer.compare(
    left.relativePath,
    right.relativePath
  ));
  return {
    fileCount: entries.length,
    totalBytes,
    treeSha256: sha256(Buffer.from(
      entries.map((entry) => `${entry.relativePath}\t${entry.sha256}`).join('\n'),
      'utf8'
    )),
    reparseEntryCount,
  };
}

// Keep these checks aligned with the vendored official format contract in
// vendor/dsh-zstd/types/format.js without loading its unavailable DSH runtime.
const SESSION_FORMAT_VERSION = 0;
function isHeaderLine(value) {
  return typeof value === 'object' && value !== null
    && value.type === 'session'
    && value.version === SESSION_FORMAT_VERSION
    && typeof value.id === 'string'
    && value.id.length > 0
    && typeof value.createdAt === 'number'
    && Number.isSafeInteger(value.createdAt)
    && value.createdAt >= 0
    && !Object.is(value.createdAt, -0)
    && typeof value.delegationDepth === 'number'
    && Number.isSafeInteger(value.delegationDepth)
    && value.delegationDepth >= 0
    && !Object.is(value.delegationDepth, -0)
    && (value.cwd === undefined || (typeof value.cwd === 'string' && value.cwd.length > 0))
    && (value.seedLength === undefined
      || (typeof value.seedLength === 'number'
        && Number.isSafeInteger(value.seedLength)
        && value.seedLength >= 0
        && !Object.is(value.seedLength, -0)))
    && (value.origin === undefined || value.origin === 'subagent')
    && (value.agentPreset === undefined || typeof value.agentPreset === 'string')
    && !Object.hasOwn(value, 'sandboxMode')
    && !Object.hasOwn(value, 'approvalPolicy');
}

function encodeSegment(raw) {
  if (raw === '.') return '~002E';
  if (raw === '..') return '~002E~002E';
  let out = '';
  for (let i = 0; i < raw.length; i++) {
    const code = raw.charCodeAt(i);
    const ch = String.fromCharCode(code);
    out += ch !== '~' && /^[A-Za-z0-9._-]$/.test(ch)
      ? ch
      : '~' + code.toString(16).toUpperCase().padStart(4, '0');
  }
  return out;
}

async function inspectSessionLog(p) {
  const buf = fs.readFileSync(p);
  const { frames, tornStart } = zstd.scanZstdFrames(buf);
  if (frames.length === 0 || tornStart !== undefined) {
    throw new Error('incomplete Zstandard framing');
  }

  const first = Buffer.from(await zstd.decompressZstdFrame(
    buf.subarray(frames[0].start, frames[0].end)
  ));
  if (first.length < 2 || first[first.length - 1] !== 0x0a) {
    throw new Error('first Zstandard frame is not exactly one nonempty newline-terminated JSON header');
  }
  const headerBytes = first.subarray(0, first.length - 1);
  if (headerBytes.length === 0 || headerBytes.includes(0x0a) || headerBytes.includes(0x0d)) {
    throw new Error('first Zstandard frame is not exactly one nonempty newline-terminated JSON header');
  }

  let header;
  try {
    header = JSON.parse(headerBytes.toString('utf8'));
  } catch {
    throw new Error('first Zstandard frame does not contain a valid JSON header');
  }
  if (!isHeaderLine(header)) {
    throw new Error('first Zstandard frame does not contain a valid session header');
  }

  // Validate every remaining frame while deliberately discarding plaintext.
  for (let i = 1; i < frames.length; i++) {
    await zstd.decompressZstdFrame(buf.subarray(frames[i].start, frames[i].end));
  }
  return header;
}

// Encode a target cwd's project key for comparison.
function projectKeyOf(cwd) {
  let readable = '';
  let sepRun = false;
  for (let i = 0; i < cwd.length; i++) {
    const code = cwd.charCodeAt(i);
    const ch = String.fromCharCode(code);
    if (ch === '/' || ch === '\\' || ch === ':') {
      if (!sepRun) readable += '-';
      sepRun = true;
    } else if (ch !== '~' && /^[A-Za-z0-9._-]$/.test(ch)) {
      readable += ch;
      sepRun = false;
    } else {
      readable += '~' + code.toString(16).toUpperCase().padStart(4, '0');
      sepRun = false;
    }
  }
  const slug = readable.replace(/^-+/, '') || 'root';
  return `--${slug.slice(0, 251)}--`;
}

function quarantine(pathToMove, reason) {
  if (!doFix) { warn('would quarantine: ' + pathToMove + ' (' + reason + '); rerun with --fix'); return; }
  const dest = path.join(quarantineRoot, `${new Date().toISOString().replace(/[:.]/g, '-')}-${path.basename(path.dirname(pathToMove))}`);
  fs.mkdirSync(dest, { recursive: true });
  fs.renameSync(pathToMove, path.join(dest, path.basename(pathToMove)));
  log('quarantined: ' + pathToMove + ' -> ' + dest);
}

let problems = 0;

log('=== DSH preflight: ' + dshHome + ' ===');

// 1 & 2: walk sessions tree
if (!fs.existsSync(sessionsRoot)) { err('sessions root missing: ' + sessionsRoot); process.exit(2); }

// Collect every directory Desktop treats as a session. Only explicit
// administrative directory names are strays; session ids are otherwise opaque.
const candidates = [];
const strays = [];
const straySessionDirNames = new Set([
  '.backup', '.backups', 'backup', 'backups',
  '.move-backups', 'move-backups',
  '.quarantine', 'quarantine',
  '.tool', '.tools', '.tooling', 'tool', 'tools', 'tooling',
]);
let sessionCount = 0;
for (const entry of fs.readdirSync(sessionsRoot, { withFileTypes: true })) {
  if (!entry.isDirectory()) continue;
  const proj = entry.name;
  // 2: stray dirs that are NOT project-key shaped
  if ((!proj.startsWith('--') || !proj.endsWith('--')) && proj !== '_no-cwd') {
    strays.push(path.join(sessionsRoot, proj));
    continue;
  }
  for (const sub of fs.readdirSync(path.join(sessionsRoot, proj), { withFileTypes: true })) {
    if (!sub.isDirectory()) continue;
    const n = sub.name;
    if (straySessionDirNames.has(n.toLowerCase())) {
      strays.push(path.join(sessionsRoot, proj, n));
      continue;
    }
    sessionCount++;
    candidates.push({
      dirName: n,
      proj,
      sessionDir: path.join(sessionsRoot, proj, n),
      quarantineReasons: new Set(),
    });
  }
}

// Parse and validate candidates before duplicate detection: the header id is the
// canonical identity, while the directory name is only its encoded storage key.
const byHeaderId = new Map();
const invalidCandidates = new Set();
function diagnose(candidate, message, reason) {
  invalidCandidates.add(candidate);
  candidate.quarantineReasons.add(reason);
  err(message + ': ' + candidate.dirName + ' in ' + candidate.proj);
  if (!doFix) problems++;
}

for (const candidate of candidates) {
  const p = path.join(candidate.sessionDir, 'session.jsonl.zstd');
  if (!fs.existsSync(p)) {
    diagnose(candidate, 'MISSING session.jsonl.zstd', 'missing session log');
    continue;
  }

  let header;
  try {
    header = await inspectSessionLog(p);
  } catch (e) {
    diagnose(candidate, 'UNREADABLE session (' + e.message + ')', 'unreadable');
    continue;
  }
  candidate.header = header;
  const copies = byHeaderId.get(header.id);
  if (copies) copies.push(candidate);
  else byHeaderId.set(header.id, [candidate]);

  if (encodeSegment(header.id) !== candidate.dirName) {
    diagnose(candidate, 'SESSION DIRECTORY vs HEADER mismatch', 'directory/header mismatch');
  }
  const expectedProject = header.cwd === undefined ? '_no-cwd' : projectKeyOf(header.cwd);
  if (expectedProject !== candidate.proj) {
    diagnose(candidate, 'POSITION vs HEADER mismatch', 'position/header mismatch');
  }
}

// 1: duplicates by canonical parsed header id
let dupCount = 0;
for (const copies of byHeaderId.values()) {
  if (copies.length > 1) {
    dupCount++;
    err('DUPLICATE parsed session id across ' + copies.length + ' directories');
    if (doFix) {
      const keep = copies.find(candidate => candidate.quarantineReasons.size === 0);
      for (const candidate of copies) {
        if (candidate !== keep && candidate.quarantineReasons.size === 0) {
          candidate.quarantineReasons.add('duplicate parsed header id');
          invalidCandidates.add(candidate);
        }
      }
    } else problems++;
  }
}
log(dupCount ? ('duplicates: ' + dupCount) : '1. no duplicate parsed session ids (' + sessionCount + ' sessions)');

// 2: explicit administrative dirs (esp. .move-backups / quarantine)
for (const s of strays) {
  warn('stray dir inside sessions/ (DSH scanner will treat as session!): ' + s);
  if (doFix) quarantine(s, 'stray dir');
  else problems++;
}
log(strays.length ? ('stray dirs: ' + strays.length) : '2. no stray dirs');

// 3: quarantine each affected session directory once, preserving every file.
if (doFix) {
  for (const candidate of invalidCandidates) {
    quarantine(candidate.sessionDir, [...candidate.quarantineReasons].join('; '));
  }
}
const corruptCount = invalidCandidates.size;
log(corruptCount ? ('corrupt/mismatch: ' + corruptCount) : '3. all session headers and paths match');

// 4: optional smoke boot - MUST use an isolated DSH_HOME (never boot a second
//    web against the live home: im-gateway holds an instance lock and data dirs
//    forbid concurrent access; the smoke boot must never reuse the live home).
if (doSmoke) {
  log('=== SMOKE BOOT (isolated DSH_HOME) ===');
  const smokeHome = path.join(os.tmpdir(), 'dsh-smoke-' + Date.now());
  fs.mkdirSync(smokeHome, { recursive: true });
  // Junction sessions/memories/storages: real data read-only by the smoke boot
  // is fine (a health-checked boot does not rewrite history); but to be safe,
  // copy the sessions tree (small-ish) and link nothing writable.
  const smokeSessions = path.join(smokeHome, 'sessions');
  fs.cpSync(sessionsRoot, smokeSessions, { recursive: true, force: true });
  log('smoke home: ' + smokeHome + ' (sessions copied)');
  const lock = JSON.parse(fs.readFileSync(
    path.join(scriptDir, '..', 'deployments', 'windows-copilot.lock.json'),
    'utf8'
  ));
  const selectors = lock.components?.desktop?.runtimeSelectors ?? [];
  const selector = selectors.length === 1 && selectors[0]?.id === 'desktop-official'
    ? selectors[0]
    : null;
  const runtimeRoot = selector && process.env.APPDATA
    ? selector.root.replace(/^%APPDATA%/i, process.env.APPDATA)
    : '';
  const bin = selector ? path.resolve(runtimeRoot, selector.package.entrypoint) : '';
  const override = process.env.DSH_CLI_PATH
    ? path.resolve(process.env.DSH_CLI_PATH)
    : null;
  const node = process.env.DSH_SMOKE_NODE || process.execPath;
  let runtimeValid = false;
  if (bin.length > 0 && fs.existsSync(bin)
    && (!override || override.toLowerCase() === bin.toLowerCase())) {
    try {
      const bytes = fs.readFileSync(bin);
      const manifest = JSON.parse(fs.readFileSync(
        path.resolve(runtimeRoot, selector.package.manifest),
        'utf8'
      ));
      const rootManifestBytes = fs.readFileSync(
        path.resolve(runtimeRoot, selector.rootPackage.manifest)
      );
      const rootManifest = JSON.parse(rootManifestBytes.toString('utf8'));
      const wrapper = runtimeTreeState(runtimeRoot);
      runtimeValid = bytes.length === selector.package.entrypointSize
        && sha256(bytes) === selector.package.entrypointSha256
        && manifest.name === selector.package.name
        && manifest.version === selector.package.version
        && rootManifest.name === selector.rootPackage.name
        && rootManifest.version === selector.rootPackage.version
        && sha256(rootManifestBytes) === selector.rootPackage.manifestSha256
        && wrapper.fileCount === selector.rootPackage.fileCount
        && wrapper.totalBytes === selector.rootPackage.totalBytes
        && wrapper.treeSha256 === selector.rootPackage.treeSha256
        && wrapper.reparseEntryCount === selector.rootPackage.reparseDirectoryCount;
    } catch {
      runtimeValid = false;
    }
  }
  if (override && override.toLowerCase() !== bin.toLowerCase()) {
    err('SMOKE FAILED: DSH_CLI_PATH does not match the locked Desktop-managed runtime.');
    problems++;
    fs.rmSync(smokeHome, { recursive: true, force: true });
    process.exitCode = 1;
  } else if (!runtimeValid) {
    err('SMOKE FAILED: locked Desktop-managed runtime attestation failed.');
    problems++;
    fs.rmSync(smokeHome, { recursive: true, force: true });
    process.exitCode = 1;
  } else {
  log('using node: ' + node);
  log('starting backend on isolated home...');
  let child;
  try {
    child = spawn(node, ['--expose-internals', bin, 'web', '--host', '127.0.0.1', '--port', '0', '--no-open'], {
      env: { ...process.env, DSH_HOME: smokeHome },
      stdio: ['ignore', 'pipe', 'pipe'],
      windowsHide: true,
    });
    let out = '';
    const urlRe = /dsh web:\s+(http:\/\/127\.0\.0\.1:\d+)/;
    const ok = await new Promise((resolve) => {
      const t = setTimeout(() => resolve(false), 60000);
      child.stdout.on('data', (d) => { out += d.toString(); const m = out.match(urlRe); if (m) { clearTimeout(t); resolve(m[1]); } });
      child.stderr.resume();
      child.on('exit', () => { clearTimeout(t); resolve(false); });
    });
    if (ok) {
      log('SMOKE OK: ' + ok);
    } else {
      err('SMOKE FAILED: isolated backend did not become ready within 60s.');
      problems++;
    }
  } catch (e) {
    err('smoke boot error: ' + e.message);
    problems++;
  } finally {
    if (child && child.exitCode === null) {
      child.kill();
      await Promise.race([
        new Promise(resolve => child.once('exit', resolve)),
        new Promise(resolve => setTimeout(resolve, 5000)),
      ]);
      if (child.exitCode === null) {
        child.kill('SIGKILL');
        await new Promise(resolve => child.once('exit', resolve));
      }
      log('smoke instance stopped');
    }
    fs.rmSync(smokeHome, { recursive: true, force: true });
  }
  }
}

log(problems === 0 ? '=== PREFLIGHT CLEAN ===' : '=== PREFLIGHT PROBLEMS: ' + problems + ' (run with --fix to quarantine; --smoke to boot-test) ===');
process.exit(problems === 0 ? 0 : 1);
