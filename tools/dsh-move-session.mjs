// dsh-move-session.mjs - atomically move a DSH session to another project (cwd / workspace group).
// Discipline (2026-08-24 duplicate-session incident):
//   1. pre-check: the session id must exist in EXACTLY ONE project dir
//   2. backup: copy the artifact to a backup dir first
//   3. write new: decompress, rewrite header.cwd, recompress, write to target project dir
//   4. verify: read back and confirm header/content
//   5. delete old: only after verify succeeds
// Usage:
//   node dsh-move-session.mjs <session-id> <target-cwd> [--sessions-root <dir>]
//   example: node dsh-move-session.mjs session-xxx "D:\转咪"
// Env: DSH_HOME (default ~/.dsh); backups under <sessions-root>/.move-backups/
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import zlib from 'node:zlib';

const args = process.argv.slice(2);
const sid = args[0];
const targetCwd = args[1];
if (!sid || !targetCwd) {
  console.error('usage: node dsh-move-session.mjs <session-id> <target-cwd>');
  process.exit(2);
}
const sessionsRoot = path.join(process.env.DSH_HOME || path.join(os.homedir(), '.dsh'), 'sessions');
// Match the official projectKey: separators -> '-', unsafe code units -> ~XXXX, wrapped in --...--
function projectKey(cwd) {
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

async function decompress(p) {
  const buf = fs.readFileSync(p);
  const out = [];
  await new Promise((res, rej) => {
    const dec = new zlib.ZstdDecompress();
    dec.on('data', (c) => out.push(c));
    dec.on('end', res);
    dec.on('error', rej);
    dec.write(buf);
    dec.end();
  });
  return Buffer.concat(out);
}

// 1. locate: exactly one project dir must hold this session
const found = [];
for (const entry of fs.readdirSync(sessionsRoot, { withFileTypes: true })) {
  if (!entry.isDirectory()) continue;
  const dir = path.join(sessionsRoot, entry.name, sid);
  if (fs.existsSync(path.join(dir, 'session.jsonl.zstd'))) found.push(entry.name);
}
console.log('found in project dirs:', JSON.stringify(found));
if (found.length !== 1) {
  console.error('ABORT: session must exist in EXACTLY ONE project dir (found ' + found.length + '). Run check-session-duplicates.ps1 first.');
  process.exit(1);
}
const oldProj = found[0];
const srcFile = path.join(sessionsRoot, oldProj, sid, 'session.jsonl.zstd');

// 2. backup
const bakDir = path.join(sessionsRoot, '.move-backups', sid + '-' + new Date().toISOString().replace(/[:.]/g, '-'));
fs.mkdirSync(bakDir, { recursive: true });
fs.copyFileSync(srcFile, path.join(bakDir, 'session.jsonl.zstd'));
console.log('backup ->', bakDir);

// 3. rewrite header.cwd + write to target
const text = (await decompress(srcFile)).toString('utf8');
const lines = text.split('\n');
const oldCwdRe = /"cwd":"(?:[^"\\]|\\.)*"/;
const oldCwd = (lines[0].match(oldCwdRe) || [null])[0];
if (!oldCwd) { console.error('ABORT: no cwd field in header'); process.exit(1); }
const newCwd = '"cwd":"' + targetCwd.replace(/\\/g, '\\\\').replace(/"/g, '\\"') + '"';
lines[0] = lines[0].replace(oldCwdRe, newCwd);
console.log('header cwd:', oldCwd, '->', newCwd);
const newText = lines.join('\n');
const newBuf = zlib.zstdCompressSync(Buffer.from(newText, 'utf8'));
const targetProj = projectKey(targetCwd);
const targetDir = path.join(sessionsRoot, targetProj, sid);
fs.mkdirSync(targetDir, { recursive: true });
fs.writeFileSync(path.join(targetDir, 'session.jsonl.zstd'), newBuf);

// 4. verify round-trip
const vb = fs.readFileSync(path.join(targetDir, 'session.jsonl.zstd'));
const vtext = (await decompress(path.join(targetDir, 'session.jsonl.zstd'))).toString('utf8');
const vHeader = (vtext.split('\n')[0].match(oldCwdRe) || [null])[0];
console.log('verify header cwd:', vHeader);
const ok = vHeader === newCwd;
if (!ok) { console.error('ABORT: verify failed - leaving both copies; check manually.'); process.exit(1); }

// 5. delete old (target verified)
fs.rmSync(path.join(sessionsRoot, oldProj, sid), { recursive: true, force: true });
console.log('removed old copy from', oldProj);
console.log('DONE: moved', sid, 'to', targetProj, '(cwd=' + targetCwd + ')');
