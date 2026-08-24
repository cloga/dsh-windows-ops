import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

// Official zstd frame utilities - the ONLY way to correctly read/write DSH session
// logs (multi-frame: one frame per JSONL row). Using a naive whole-file
// decompression loses all but the first frame (this bit us twice - the
// "628KB decompresses to 173 bytes" scare was OUR decoder bug, not data loss).
const zstdUrl = pathToFileURL(
  'D:/deepseek-harness/DeepSeek Harness/resources/runtime/node_modules/@deepseek-ai/dsh-session-persistence-jsonl/lib/types/zstd.js'
).href;
const zstd = await import(zstdUrl);

const args = process.argv.slice(2);
const sid = args[0];
const targetCwd = args[1];
if (!sid || !targetCwd) {
  console.error('usage: node dsh-move-session.mjs <session-id> <target-cwd>');
  process.exit(2);
}
const dshHome = process.env.DSH_HOME || path.join(os.homedir(), '.dsh');
const sessionsRoot = path.join(dshHome, 'sessions');
const backupsRoot = path.join(dshHome, 'tools', 'backups'); // OUTSIDE sessions tree

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

// Read ALL frames as JSONL lines via the official splitter/decompressor.
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

// Write header + each row as its own official frame.
async function writeAllFrames(p, lines) {
  const out = [];
  for (const line of lines) {
    if (line === '') continue;
    const frame = await zstd.compressZstdFrame(Buffer.from(line + '\n', 'utf8'));
    out.push(frame);
  }
  fs.writeFileSync(p, Buffer.concat(out));
}

// 1. uniqueness pre-check
const found = [];
for (const entry of fs.readdirSync(sessionsRoot, { withFileTypes: true })) {
  if (!entry.isDirectory()) continue;
  const f = path.join(sessionsRoot, entry.name, sid, 'session.jsonl.zstd');
  if (fs.existsSync(f)) found.push(entry.name);
}
console.log('found in project dirs:', JSON.stringify(found));
if (found.length !== 1) {
  console.error('ABORT: session must exist in EXACTLY ONE project dir (found ' + found.length + '). Run check-session-duplicates.ps1 first.');
  process.exit(1);
}
const oldProj = found[0];
const srcFile = path.join(sessionsRoot, oldProj, sid, 'session.jsonl.zstd');

// 2. parse real header (multi-frame, official)
let text;
try {
  text = await readAllFrames(srcFile);
} catch (e) {
  console.error('ABORT: cannot read session frames: ' + e.message);
  process.exit(1);
}
const lines = text.split('\n');
const header = JSON.parse(lines[0]);
console.log('header:', JSON.stringify({ id: header.id, cwd: header.cwd, agentPreset: header.agentPreset }), 'rows:', lines.filter(Boolean).length);

// 3. backup (OUTSIDE sessions tree)
const bakDir = path.join(backupsRoot, `${sid}-${new Date().toISOString().replace(/[:.]/g, '-')}`);
fs.mkdirSync(bakDir, { recursive: true });
fs.copyFileSync(srcFile, path.join(bakDir, 'session.jsonl.zstd'));
console.log('backup (outside sessions) ->', bakDir);

// 4. rewrite header.cwd = targetCwd; write under projectKey(targetCwd)
const normalizedTarget = targetCwd.replace(/\\/g, path.sep).replace(/\//g, path.sep);
const targetProj = projectKey(normalizedTarget);
const targetDir = path.join(sessionsRoot, targetProj, sid);
console.log('target projectKey:', targetProj);
const oldCwdRe = /"cwd":"(?:[^"\\]|\\.)*"/;
if (!oldCwdRe.test(lines[0])) { console.error('ABORT: no cwd field in header'); process.exit(1); }
const newCwdField = '"cwd":"' + normalizedTarget.replace(/\\/g, '\\\\').replace(/"/g, '\\"') + '"';
lines[0] = lines[0].replace(oldCwdRe, newCwdField);
console.log('header cwd ->', JSON.stringify(JSON.parse(lines[0]).cwd));

// 5. write new (official per-frame layout)
fs.mkdirSync(targetDir, { recursive: true });
await writeAllFrames(path.join(targetDir, 'session.jsonl.zstd'), lines);
console.log('written to', targetDir);

// 6. verify round-trip via official reader
let vh;
try {
  vh = await readAllFrames(path.join(targetDir, 'session.jsonl.zstd'));
} catch (e) {
  console.error('ABORT: verify parse failed: ' + e.message);
  process.exit(1);
}
const vLines = vh.split('\n').filter(Boolean);
const vHeader = JSON.parse(vLines[0]);
console.log('verify:', JSON.stringify({ cwd: vHeader.cwd, rows: vLines.length }));
if (vHeader.cwd !== normalizedTarget || vLines.length !== lines.filter(Boolean).length) {
  console.error('ABORT: verify mismatch -> keep both, check manually.');
  process.exit(1);
}

// 7. delete old (only after verify)
fs.rmSync(path.join(sessionsRoot, oldProj, sid), { recursive: true, force: true });
console.log('removed old copy from', oldProj);
console.log('DONE: moved', sid, '->', targetProj, '(cwd=' + normalizedTarget + ', rows=' + vLines.length + ')');
