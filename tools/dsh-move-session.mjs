// DSH session mover v2 — the standard, atomic session migration tool.
//
// Usage:
//   node dsh-move-session.mjs <session-id> <target-cwd> [--dry-run]
//
// What it does (file + workspace registry, in this order):
//   1. uniqueness pre-check (a duplicate id anywhere ABORTS — DSH refuses to
//      boot on duplicate ids)
//   2. parse the real header via official multi-frame zstd utilities
//   3. backup the source OUTSIDE the sessions tree (tools/backups/)
//   4. rewrite header.cwd = canonical(target-cwd); write under
//      projectKey(canonical(target-cwd)) with official per-frame layout
//   5. verify round-trip (cwd + row count) BEFORE deleting the old copy
//   6. delete the old copy
//   7. sync the Host Workspace registry (~/.dsh/storages/workspace.json):
//      detach the session from every workspace that accounts for it, attach it
//      to the workspace owning the target directory (creating that workspace
//      like the registry does: prepended to the display order) — the sidebar
//      groups sessions by this registry, NOT by header.cwd
//
// --dry-run prints the whole plan and writes nothing.
//
// NOTE: run with the DSH app CLOSED. File/header moves are safe while it runs,
// but workspace.json takes effect on next startup and a live process may
// overwrite the file on its next workspace write.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import {
  canonKey, canonicalDir, loadWorkspace, saveWorkspace, requireConsistent,
  findOwners, detachFrom, attachTo, createWorkspace, runningHint
} from './dsh-workspace-lib.mjs';

// Official zstd frame utilities - the ONLY way to correctly read/write DSH session
// logs (multi-frame: one frame per JSONL row). A naive whole-file decompression
// loses all but the first frame (this bit us twice - the "628KB decompresses to
// 173 bytes" scare was OUR decoder bug, not data loss).
const zstdUrl = pathToFileURL(
  (process.env.DSH_ZSTD || 'D:/deepseek-harness/DeepSeek Harness/resources/runtime/node_modules/@deepseek-ai/dsh-session-persistence-jsonl/lib/types/zstd.js')
).href;
const zstd = await import(zstdUrl);

const args = process.argv.slice(2);
const dryRun = args.includes('--dry-run');
const positional = args.filter((a) => !a.startsWith('--'));
const sid = positional[0];
const targetCwd = positional[1];
if (!sid || !targetCwd) {
  console.error('usage: node dsh-move-session.mjs <session-id> <target-cwd> [--dry-run]');
  process.exit(2);
}
const dshHome = process.env.DSH_HOME || path.join(os.homedir(), '.dsh');
const sessionsRoot = path.join(dshHome, 'sessions');
const backupsRoot = path.join(dshHome, 'tools', 'backups'); // OUTSIDE sessions tree
const workspaceFile = path.join(dshHome, 'storages', 'workspace.json');

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

// ---------- plan phase (read-only) ----------
const hint = runningHint();
if (hint) console.log(hint);

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

// 3. canonical target (registry compares realpath — directory must exist)
let normalizedTarget;
try {
  normalizedTarget = canonicalDir(targetCwd);
} catch (e) {
  console.error('ABORT: target directory does not exist or is not resolvable: ' + targetCwd + ' (' + e.message + ')');
  process.exit(1);
}
if (!fs.statSync(normalizedTarget).isDirectory()) {
  console.error('ABORT: target is not a directory: ' + normalizedTarget);
  process.exit(1);
}
const targetProj = projectKey(normalizedTarget);
console.log('target canonical cwd:', JSON.stringify(normalizedTarget), '-> projectKey:', targetProj);

// 4. workspace plan (read-only) — what the registry sync will do
const wsObj = loadWorkspace(workspaceFile);
const wsPlan = { owners: [], targetId: undefined, targetExists: false, willCreate: false };
if (wsObj !== null) {
  const v = requireConsistent(wsObj);
  wsPlan.owners = findOwners(v, sid);
  wsPlan.targetId = v.byPath.get(canonKey(normalizedTarget));
  wsPlan.targetExists = wsPlan.targetId !== undefined;
  wsPlan.willCreate = !wsPlan.targetExists;
  const lostText = wsPlan.owners.length === 0 ? ' (session not accounted by any workspace)' : '';
  console.log('workspace registry:', wsPlan.owners.length + ' owner(s)' + lostText +
    (wsPlan.targetExists ? ', target workspace=' + wsPlan.targetId : ', target workspace: NONE (will create)') +
    ', consistent=' + (v.issues.length === 0));
}

// idempotence: already in place
const headerCwdMatches = header.cwd === normalizedTarget;
if (oldProj === targetProj && headerCwdMatches) {
  console.log('session already at its target location (projectKey + header.cwd).');
  if (dryRun) {
    console.log('DRY-RUN: nothing to move; workspace sync would be: holders ' + JSON.stringify(wsPlan.owners) + ' -> target ' + (wsPlan.targetId ?? 'create'));
    process.exit(0);
  }
  const needDetach = wsPlan.owners.filter((id) => id !== wsPlan.targetId);
  if (needDetach.length === 0 && wsPlan.targetId !== undefined) {
    console.log('workspace accounting already consistent: no-op. DONE.');
    process.exit(0);
  }
  // header matches but registry needs repair — fall through to sync below with no file move
  const moved = false;
  console.log('registry sync only (file already in place)…');
  // (continues to the sync section)
  const ws = loadWorkspace(workspaceFile);
  if (ws === null) { console.error('ABORT: no workspace domain file while registry sync is required.'); process.exit(1); }
  for (const ownerId of needDetach) detachFrom(ws, ownerId, sid);
  let targetId = wsPlan.targetId;
  if (targetId === undefined) targetId = createWorkspace(ws, normalizedTarget);
  attachTo(ws, targetId, sid);
  console.log('sync -> owner(s)=' + JSON.stringify(needDetach) + ', target=' + targetId + (wsPlan.willCreate ? ' (created)' : ''));
  if (!dryRun) saveWorkspace(workspaceFile, ws);
  console.log('DONE (sync only):', sid, 'accounted by workspace', targetId);
  process.exit(0);
}

// ---------- dry run ----------
if (dryRun) {
  console.log('DRY-RUN plan:');
  console.log('  - backup   ' + srcFile + ' -> ' + path.join(backupsRoot, sid + '-<ts>', 'session.jsonl.zstd'));
  console.log('  - move     ' + oldProj + '/' + sid + ' -> ' + targetProj + '/' + sid);
  console.log('  - header   cwd ' + JSON.stringify(header.cwd) + ' -> ' + JSON.stringify(normalizedTarget));
  console.log('  - registry detach ' + JSON.stringify(wsPlan.owners) + (wsPlan.targetExists ? ', attach -> ' + wsPlan.targetId : ', create workspace @ ' + normalizedTarget + ' then attach'));
  console.log('  - verify   round-trip + registry readback before old copy is deleted');
  process.exit(0);
}

// 5. backup (OUTSIDE sessions tree)
const bakDir = path.join(backupsRoot, `${sid}-${new Date().toISOString().replace(/[:.]/g, '-')}`);
fs.mkdirSync(bakDir, { recursive: true });
fs.copyFileSync(srcFile, path.join(bakDir, 'session.jsonl.zstd'));
console.log('backup (outside sessions) ->', bakDir);

// 6. rewrite header.cwd; write under projectKey(canonical target)
const targetDir = path.join(sessionsRoot, targetProj, sid);
const oldCwdRe = /"cwd":"(?:[^"\\]|\\.)*"/;
if (!oldCwdRe.test(lines[0])) { console.error('ABORT: no cwd field in header'); process.exit(1); }
const newCwdField = '"cwd":"' + normalizedTarget.replace(/\\/g, '\\\\').replace(/"/g, '\\"') + '"';
lines[0] = lines[0].replace(oldCwdRe, newCwdField);
console.log('header cwd ->', JSON.stringify(JSON.parse(lines[0]).cwd));

fs.mkdirSync(targetDir, { recursive: true });
await writeAllFrames(path.join(targetDir, 'session.jsonl.zstd'), lines);
console.log('written to', targetDir);

// 7. verify round-trip via official reader
let vh;
try {
  vh = await readAllFrames(path.join(targetDir, 'session.jsonl.zstd'));
} catch (e) {
  console.error('ABORT: verify parse failed: ' + e.message + ' — target kept, source NOT deleted; inspect manually.');
  process.exit(1);
}
const vLines = vh.split('\n').filter(Boolean);
const vHeader = JSON.parse(vLines[0]);
console.log('verify:', JSON.stringify({ cwd: vHeader.cwd, rows: vLines.length }));
if (vHeader.cwd !== normalizedTarget || vLines.length !== lines.filter(Boolean).length) {
  console.error('ABORT: verify mismatch -> keep both, check manually.');
  process.exit(1);
}

// 8. delete old (only after verify)
if (oldProj !== targetProj) {
  fs.rmSync(path.join(sessionsRoot, oldProj, sid), { recursive: true, force: true });
  console.log('removed old copy from', oldProj);
} else {
  console.log('same project dir — old copy already replaced in place');
}

// 9. workspace registry sync (file-level, official semantics)
let ws;
try {
  ws = loadWorkspace(workspaceFile);
  if (ws === null) throw new Error('workspace domain file does not exist');
  const v = requireConsistent(ws);
  const owners = findOwners(v, sid);
  if (owners.length > 1) throw new Error(`session accounted by ${owners.length} workspaces — resolve first; refusing to guess`);
  for (const ownerId of owners) detachFrom(ws, ownerId, sid);
  let targetId = v.byPath.get(canonKey(normalizedTarget));
  if (targetId === undefined) targetId = createWorkspace(ws, normalizedTarget);
  attachTo(ws, targetId, sid);
  saveWorkspace(workspaceFile, ws);
  console.log('workspace registry synced: detach ' + JSON.stringify(owners) + ', owner=' + targetId + (owners.length === 0 ? ' (was stray)' : ''));
} catch (e) {
  console.error('WARN: workspace registry sync FAILED: ' + e.message + ' — session files are already moved (backup exists at ' + bakDir + '). Repair with: node dsh-workspace-fix.mjs ' + sid + ' ' + normalizedTarget);
  process.exit(1);
}

// 10. registry readback verification
try {
  const v2 = requireConsistent(loadWorkspace(workspaceFile));
  const owners2 = findOwners(v2, sid);
  if (owners2.length !== 1) throw new Error(`readback: expected exactly 1 owner, got ${owners2.length}`);
  const owner = owners2[0];
  if (v2.tables[owner].path.toLowerCase() !== normalizedTarget.toLowerCase()) throw new Error(`readback: owner path '${v2.tables[owner].path}' != target '${normalizedTarget}'`);
  console.log('registry readback OK: owner=' + owner + ', path=' + v2.tables[owner].path);
} catch (e) {
  console.error('WARN: registry readback failed: ' + e.message + ' — rerun dsh-workspace-fix.mjs before next startup.');
  process.exit(1);
}

console.log('DONE: moved', sid, '->', targetProj, '(cwd=' + normalizedTarget + ', rows=' + vLines.length + ')');
