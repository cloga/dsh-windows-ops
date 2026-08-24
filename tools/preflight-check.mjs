// preflight-check.mjs - DSH startup preflight: verify the session store is healthy
// BEFORE the app starts, so corrupt/duplicate session data never turns into a
// "app won't boot" surprise.
//
// Checks (all read-only; --fix moves bad copies into DSH_HOME/tools/quarantine/):
//   1. no duplicate session ids across project dirs
//   2. no stray .move-backups / quarantine dirs INSIDE sessions/ (the DSH scanner
//      treats every subdir as an active session - a backup there looks corrupt)
//   3. every session.jsonl.zstd: multi-frame decodes OK AND header.cwd matches the
//      project dir's decoded cwd (position vs header mismatch => corrupt)
//   4. (optional --smoke) start the web backend with an isolated DSH_HOME copy,
//      wait for healthy, then stop it - a full boot test in the sandbox.
//
// Usage:
//   node preflight-check.mjs [--fix] [--smoke]
// Env: DSH_HOME (default ~/.dsh)
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFile, spawn } from 'node:child_process';
import { promisify } from 'node:util';
import { pathToFileURL } from 'node:url';

const execP = promisify(execFile);
const dshHome = process.env.DSH_HOME || path.join(os.homedir(), '.dsh');
const sessionsRoot = path.join(dshHome, 'sessions');
const quarantineRoot = path.join(dshHome, 'tools', 'quarantine');
const args = process.argv.slice(2);
const doFix = args.includes('--fix');
const doSmoke = args.includes('--smoke');

const zstdUrl = pathToFileURL(
  'D:/deepseek-harness/DeepSeek Harness/resources/runtime/node_modules/@deepseek-ai/dsh-session-persistence-jsonl/lib/types/zstd.js'
).href;
const zstd = await import(zstdUrl);

function log(s) { console.log(s); }
function warn(s) { console.warn('[WARN] ' + s); }
function err(s) { console.error('[ERROR] ' + s); }

async function readAllFrames(p) {
  const buf = fs.readFileSync(p);
  const { frames } = zstd.scanZstdFrames(buf, { maxFrames: 1000000 });
  const parts = [];
  for (const fr of frames) {
    const plain = await zstd.decompressZstdFrame(buf.subarray(fr.start, fr.end));
    parts.push(Buffer.isBuffer(plain) ? plain : Buffer.from(plain));
  }
  return Buffer.concat(parts).toString('utf8');
}

// Decode a project dir key back to its cwd (inverse of projectKey).
// projectKey maps '\\' ':' -> '-', non-safe -> ~XXXX. Decode: '-' -> separator
// is ambiguous (a '-' could come from a solid separator OR an escaped one), so
// we decode '-' => '\\' only when it separates a drive/segment; the simplest
// robust approach for comparison: normalize BOTH sides (lowercase, separators).
function decodeProjectKey(key) {
  if (!key.startsWith('--') || !key.endsWith('--')) return key;
  const inner = key.slice(2, -2);
  let out = '';
  for (let i = 0; i < inner.length; i++) {
    const ch = inner[i];
    if (ch === '-') {
      // a run of '-' came from separators (drive colon + backslash); first '-'
      // after nothing or a digit => drive colon, else path sep. Approximation:
      out += '\\';
      continue;
    }
    if (ch === '~') {
      const hex = inner.slice(i + 1, i + 5);
      out += String.fromCharCode(parseInt(hex, 16));
      i += 4;
      continue;
    }
    out += ch;
  }
  return out;
}
// Normalize a Windows path for position-vs-header comparison.
function normPath(p) {
  return String(p).replace(/\\/g, '/').toLowerCase().replace(/\/+$/, '');
}

// Decode a target cwd's projectKey (for comparison)
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

// Collect session dirs and stray dirs
const byId = {};
const strays = [];
let sessionCount = 0;
for (const entry of fs.readdirSync(sessionsRoot, { withFileTypes: true })) {
  if (!entry.isDirectory()) continue;
  const proj = entry.name;
  // 2: stray dirs that are NOT project-key shaped
  if (!proj.startsWith('--') || !proj.endsWith('--')) {
    strays.push(path.join(sessionsRoot, proj));
    continue;
  }
  for (const sub of fs.readdirSync(path.join(sessionsRoot, proj), { withFileTypes: true })) {
    if (!sub.isDirectory()) continue;
    // Legal session dir shapes:  session-<id>  |  <uuid> (subagent)  |  im<encoded> (im-gateway chat)
    const n = sub.name;
    const isSession = /^session-[0-9a-f-]+$/i.test(n)
      || /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(n)
      || /^im~/.test(n);
    if (!isSession) { strays.push(path.join(sessionsRoot, proj, sub.name)); continue; }
    sessionCount++;
    if (byId[n]) byId[n].push(proj);
    else byId[n] = [proj];
  }
}

// 1: duplicates
let dupCount = 0;
for (const [id, projs] of Object.entries(byId)) {
  if (projs.length > 1) {
    dupCount++;
    err('DUPLICATE session ' + id + ' in [' + projs.join(', ') + ']');
    if (doFix) {
      // keep first, quarantine others
      for (let i = 1; i < projs.length; i++) {
        quarantine(path.join(sessionsRoot, projs[i], id, 'session.jsonl.zstd'), 'duplicate copy');
      }
    } else problems++;
  }
}
log(dupCount ? ('duplicates: ' + dupCount) : '1. no duplicate session ids (' + sessionCount + ' sessions)');

// 2: strays (esp. .move-backups / quarantine inside sessions)
for (const s of strays) {
  warn('stray dir inside sessions/ (DSH scanner will treat as session!): ' + s);
  if (doFix) quarantine(s, 'stray dir');
  else problems++;
}
log(strays.length ? ('stray dirs: ' + strays.length) : '2. no stray dirs');

// 3: per-session header/parity check
let corruptCount = 0;
for (const [id, projs] of Object.entries(byId)) {
  // check each copy's header vs its project dir
  for (const proj of projs) {
    const p = path.join(sessionsRoot, proj, id, 'session.jsonl.zstd');
    if (!fs.existsSync(p)) continue;
    try {
      const text = await readAllFrames(p);
      const rows = text.split('\n').filter(Boolean);
      const h = JSON.parse(rows[0]);
      // Forward-encode comparison (no decode ambiguity): projectKeyOf(header.cwd)
      // must EQUAL the directory key the session sits in.
      const expectedDir = projectKeyOf(h.cwd || '');
      if (expectedDir !== proj) {
        corruptCount++;
        err('POSITION vs HEADER mismatch: ' + id + ' in ' + proj + ' (header cwd=' + h.cwd + ', expected dir=' + expectedDir + ')');
        if (doFix) quarantine(path.join(sessionsRoot, proj, id), 'position/header mismatch');
        else problems++;
      }
    } catch (e) {
      corruptCount++;
      err('UNREADABLE session ' + id + ' in ' + proj + ': ' + e.message);
      if (doFix) quarantine(path.join(sessionsRoot, proj, id), 'unreadable');
      else problems++;
    }
  }
}
log(corruptCount ? ('corrupt/mismatch: ' + corruptCount) : '3. all sessions decode; position matches header');

// 4: optional smoke boot - MUST use an isolated DSH_HOME (never boot a second
//    web against the live home: im-gateway holds an instance lock and data dirs
//    forbid concurrent access - A/B discipline).
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
  const bin = 'D:/deepseek-harness/DeepSeek Harness/resources/runtime/lib/bin.js';
  // Node >= 22 required: the session store uses zstd (node:zlib), and D:\node.exe
  // is v20 - use the workbuddy node 22.22.2 (same as WorkBuddy's Electron v24 in spirit).
  const node = process.env.DSH_SMOKE_NODE || 'C:/Users/sephen/.workbuddy/binaries/node/versions/22.22.2/node.exe';
  log('using node: ' + node);
  log('starting backend on isolated home...');
  try {
    const child = spawn(node, ['--expose-internals', bin, 'web', '--host', '127.0.0.1', '--port', '0', '--no-open'], {
      env: { ...process.env, DSH_HOME: smokeHome },
      stdio: ['ignore', 'pipe', 'pipe'],
      windowsHide: true,
    });
    let out = '';
    let errOut = '';
    const urlRe = /dsh web:\s+(http:\/\/127\.0\.0\.1:\d+)/;
    const ok = await new Promise((resolve) => {
      const t = setTimeout(() => resolve(false), 60000);
      child.stdout.on('data', (d) => { out += d.toString(); const m = out.match(urlRe); if (m) { clearTimeout(t); resolve(m[1]); } });
      child.stderr.on('data', (d) => { errOut += d.toString(); });
      child.on('exit', () => { clearTimeout(t); resolve(false); });
    });
    if (ok) {
      log('SMOKE OK: ' + ok);
      child.kill();
      log('smoke instance stopped');
    } else {
      err('SMOKE FAILED (no ' + urlRe.source + ' within 60s). stdout tail:');
      console.log(out.slice(-2000));
      console.log('--- stderr tail: ---');
      console.log(errOut.slice(-2000));
      problems++;
    }
  } catch (e) {
    err('smoke boot error: ' + e.message);
    problems++;
  }
  // cleanup smoke home
  try { fs.rmSync(smokeHome, { recursive: true, force: true }); } catch {}
}

log(problems === 0 ? '=== PREFLIGHT CLEAN ===' : '=== PREFLIGHT PROBLEMS: ' + problems + ' (run with --fix to quarantine; --smoke to boot-test) ===');
process.exit(problems === 0 ? 0 : 1);
