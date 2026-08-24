// DSH workspace-registry repair tool — the "session moved but sidebar group did
// not follow" fixer. Two modes:
//
//   node dsh-workspace-fix.mjs <session-id> <target-cwd> [--dry-run]
//     Point fix: detach <session-id> from every workspace that accounts for it
//     and attach it to the workspace owning <target-cwd> (creating that
//     workspace like the registry does when missing). Also useful right after
//     an old-style/manual session move.
//
//   node dsh-workspace-fix.mjs --auto [--create-missing] [--dry-run]
//     Full reconciliation: for every workspace record, sessions whose live
//     canonical cwd no longer matches the record path are "filtered candidates"
//     (the registry's reportFilteredCandidates). Each candidate is moved to the
//     workspace owning its actual cwd when one exists; with --create-missing a
//     workspace is created for cwds that have none. Sessions with unresolvable
//     cwd are only reported.
//
// The sidebar groups by this registry (~/.dsh/storages/workspace.json), NOT by
// header.cwd — that is why a move without this step leaves the session nowhere
// visible (it falls to Ungrouped). Run with the DSH app closed; edits take
// effect on next startup. To fix WITHOUT a restart while DSH is running, use
// the dynamic Cordis plugin template: tools/workspace-fix-plugin.template.js.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import {
  canonKey, canonicalDir, loadWorkspace, saveWorkspace, requireConsistent,
  findOwners, detachFrom, attachTo, createWorkspace, runningHint
} from './dsh-workspace-lib.mjs';

const zstdUrl = pathToFileURL(
  (process.env.DSH_ZSTD || 'D:/deepseek-harness/DeepSeek Harness/resources/runtime/node_modules/@deepseek-ai/dsh-session-persistence-jsonl/lib/types/zstd.js')
).href;
const zstd = await import(zstdUrl);

const args = process.argv.slice(2);
const dryRun = args.includes('--dry-run');
const autoMode = args.includes('--auto');
const createMissing = args.includes('--create-missing');
const positional = args.filter((a) => !a.startsWith('--'));
const dshHome = process.env.DSH_HOME || path.join(os.homedir(), '.dsh');
const sessionsRoot = path.join(dshHome, 'sessions');
const workspaceFile = path.join(dshHome, 'storages', 'workspace.json');

async function readHeaderCwd(sessionFile) {
  const buf = fs.readFileSync(sessionFile);
  const { frames } = zstd.scanZstdFrames(buf, { maxFrames: 1000000 });
  if (frames.length === 0) return undefined;
  const plain = await zstd.decompressZstdFrame(buf.subarray(frames[0].start, frames[0].end));
  const line = Buffer.from(plain).toString('utf8').split('\n')[0];
  const h = JSON.parse(line);
  return { id: h.id, cwd: h.cwd };
}

function sessionLocs() {
  // Map session id -> { dir, headerCwd }
  const map = new Map();
  for (const entry of fs.readdirSync(sessionsRoot, { withFileTypes: true })) {
    if (!entry.isDirectory()) continue;
    for (const inner of fs.readdirSync(path.join(sessionsRoot, entry.name), { withFileTypes: true })) {
      if (!inner.isDirectory()) continue;
      const f = path.join(sessionsRoot, entry.name, inner.name, 'session.jsonl.zstd');
      if (fs.existsSync(f)) map.set(inner.name, { dir: entry.name, file: f });
    }
  }
  return map;
}

const hint = runningHint();
if (hint) console.log(hint);

// ---------- point mode ----------
if (!autoMode) {
  const sid = positional[0];
  const targetCwd = positional[1];
  if (!sid || !targetCwd) {
    console.error('usage: node dsh-workspace-fix.mjs <session-id> <target-cwd> [--dry-run]   |   node dsh-workspace-fix.mjs --auto [--create-missing] [--dry-run]');
    process.exit(2);
  }
  console.log('session:', sid, '| requested target cwd:', JSON.stringify(targetCwd));
  let ws = loadWorkspace(workspaceFile);
  if (ws === null) {
    console.log('no workspace domain exists yet — nothing to repair.');
    process.exit(0);
  }
  const v = requireConsistent(ws);
  const owners = findOwners(v, sid);
  console.log('current owners:', JSON.stringify(owners), owners.length === 0 ? '(stray — not accounted)' : '');
  let canonical;
  try {
    canonical = canonicalDir(targetCwd);
  } catch (e) {
    console.error('ABORT: target directory not resolvable: ' + targetCwd + ' (' + e.message + ')');
    process.exit(1);
  }
  let targetId = v.byPath.get(canonKey(canonical));
  const willCreate = targetId === undefined;
  console.log('target workspace:', targetId ?? 'NONE (will create)', '| canonical:', JSON.stringify(canonical));
  const plan = [];
  for (const o of owners) if (o !== targetId) plan.push('detach ' + sid + ' <- ' + o);
  if (willCreate) plan.push('create workspace @ ' + canonical + ' (prepend)');
  if (targetId === undefined || !owners.includes(targetId)) plan.push('attach ' + sid + ' -> ' + (targetId ?? 'new-workspace'));
  if (plan.length === 0) {
    console.log('registry already consistent: no-op. DONE.');
    process.exit(0);
  }
  console.log('plan:', plan.join(' | '));
  if (dryRun) { console.log('DRY-RUN — nothing written.'); process.exit(0); }
  for (const o of owners) detachFrom(ws, o, sid);
  if (willCreate) targetId = createWorkspace(ws, canonical);
  attachTo(ws, targetId, sid);
  saveWorkspace(workspaceFile);
  // readback
  const v2 = requireConsistent(loadWorkspace(workspaceFile));
  const owners2 = findOwners(v2, sid);
  if (owners2.length !== 1 || owners2[0] !== targetId) {
    console.error('WARN: readback mismatch (owners=' + JSON.stringify(owners2) + ') — inspect ' + workspaceFile + ' after startup.');
    process.exit(1);
  }
  console.log('DONE: ' + sid + ' now accounted by workspace ' + targetId + ' (' + v2.tables[targetId].title + '). Takes effect on next startup.');
  process.exit(0);
}

// ---------- auto (reconcile) mode ----------
(async () => {
  let ws = loadWorkspace(workspaceFile);
  if (ws === null) { console.log('no workspace domain exists yet — nothing to reconcile.'); process.exit(0); }
  const v = requireConsistent(ws);
  const locs = sessionLocs();
  // Build canonical cwd per session id (live index of the file system).
  const cwdBySession = new Map();   // id -> canonical cwd
  const invalid = new Map();        // id -> reason
  for (const [id, loc] of locs) {
    let h;
    try {
      h = await readHeaderCwd(loc.file);
    } catch (e) {
      invalid.set(id, 'header unreadable: ' + e.message);
      continue;
    }
    if (!h || !h.cwd) { invalid.set(id, 'header has no cwd'); continue; }
    try {
      cwdBySession.set(id, canonicalDir(h.cwd));
    } catch {
      invalid.set(id, `cwd '${h.cwd}' does not resolve`);
    }
  }
  // Candidates: record.sessionIds entries whose live cwd differs from record path.
  const candidates = [];
  let kept = 0;
  for (const [wsId, rec] of Object.entries(v.tables)) {
    for (const s of rec.sessionIds ?? []) {
      const live = cwdBySession.get(s);
      if (live !== undefined && canonKey(live) === canonKey(rec.path)) { kept++; continue; }
      if (live !== undefined) {
        candidates.push({ sid: s, from: wsId, actualCwd: live, reason: `cwd '${live}' != workspace '${rec.path}'` });
      } else {
        const reason = invalid.get(s) ?? 'session log not found on disk';
        candidates.push({ sid: s, from: wsId, actualCwd: undefined, reason });
      }
    }
  }
  console.log('reconcile: ' + candidates.length + ' filtered candidate(s) of ' + (candidates.length + kept) + ' accounted session(s).');
  for (const c of candidates) {
    if (c.actualCwd === undefined) {
      console.log('  skip  ' + c.sid + ' — ' + c.reason);
      continue;
    }
    const target = v.byPath.get(canonKey(c.actualCwd));
    if (target === undefined) {
      console.log('  skip  ' + c.sid + ' — ' + c.reason + '; no workspace owns it' + (createMissing ? '' : ' (use --create-missing to create one)'));
      continue;
    }
    console.log('  move  ' + c.sid + ' from ' + c.from + ' -> ' + target + ' (' + c.reason + ')');
  }
  if (candidates.length === 0) {
    console.log('registry already consistent with live session locations. DONE.');
    process.exit(0);
  }
  if (dryRun) { console.log('DRY-RUN — nothing written.'); process.exit(0); }
  const applied = { moved: 0, created: 0, skipped: 0 };
  for (const c of candidates) {
    if (c.actualCwd === undefined) { applied.skipped++; continue; }
    let target = v.byPath.get(canonKey(c.actualCwd));
    if (target === undefined) {
      if (!createMissing) { applied.skipped++; continue; }
      target = createWorkspace(ws, c.actualCwd);
      v.byPath.set(canonKey(c.actualCwd), target);
      applied.created++;
    }
    detachFrom(ws, c.from, c.sid);
    attachTo(ws, target, c.sid);
    applied.moved++;
  }
  saveWorkspace(workspaceFile);
  console.log('DONE: moved=' + applied.moved + ', created=' + applied.created + ', skipped=' + applied.skipped + '. Takes effect on next startup.');
})();
