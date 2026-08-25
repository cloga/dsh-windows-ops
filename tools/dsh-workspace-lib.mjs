// Shared workspace-domain helpers for DSH session/workspace tooling.
// Mirrors @deepseek-ai/dsh-workspace semantics (lib/index.js of the runtime):
//   - new workspace is PREPENDED to global.workspaceIds (createCanonical)
//   - attach prepends the session to record.sessionIds (attachSession)
//   - every mutated record stamps updatedAt = new Date().toISOString()
//   - a pendingMutation in global state means the domain is mid-operation: ABORT
//   - startup validateStoredState rejects a session accounted by TWO workspaces
// File-level edits are safe ONLY while the DSH app is closed; the live process
// re-reads workspace.json at startup and may overwrite the file on its next
// workspace write.
import fs from 'node:fs';
import path from 'node:path';
import { randomUUID } from 'node:crypto';
import { spawnSync } from 'node:child_process';

// Best-effort detection of a live DSH desktop instance (Tauri shell
// 'deepseek-harness-desktop.exe'; legacy Electron 'DeepSeek Harness.exe' also
// detected for history). Returns a warning string or null.
export function runningHint() {
  try {
    const out = spawnSync('tasklist', ['/FO', 'CSV', '/NH'], { encoding: 'utf8', timeout: 10000 });
    const lines = (out.stdout ?? '').split('\n').map((l) => l.toLowerCase());
    const live = ['deepseek-harness-desktop.exe', 'deepseek harness.exe'].filter((n) => lines.some((l) => l.includes(n)));
    if (live.length > 0) return `WARN: DSH shell process(es) detected (${live.join(', ')}). Prefer closing the app first: file/header moves are safe, but workspace.json edits take effect only on NEXT STARTUP and a live process may overwrite the file on its next workspace write.`;
  } catch { /* detection unavailable — fine */ }
  return null;
}

export function canonKey(p) {
  return process.platform === 'win32' ? p.toLowerCase() : p;
}

// fs.realpath is the same canonicalization the registry uses (realpathNormalize).
export function canonicalDir(p) {
  return fs.realpathSync(p); // throws ENOENT when missing
}

export function loadWorkspace(file) {
  if (!fs.existsSync(file)) return null; // domain not created yet (fresh install)
  let obj;
  try {
    obj = JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch (e) {
    throw new Error(`workspace.json parse failed: ${e.message}`);
  }
  if (!obj || obj.unit?.name !== 'workspace') throw new Error(`not a workspace domain file: ${file}`);
  if (obj.global?.pendingMutation) {
    throw new Error('workspace.json has pendingMutation (domain mid-operation / crashed write): ABORT — do not touch; rerun with DSH closed and stable');
  }
  return obj;
}

export function saveWorkspace(file, obj) {
  fs.writeFileSync(file, JSON.stringify(obj, null, 2) + '\n', 'utf8');
}

// Structural consistency check aligned with the registry's validateStoredState.
// Returns { issues, ids, tables, byPath, accounted } — throws when fatal.
export function inspectWorkspace(obj) {
  const tables = obj?.tables?.workspaces ?? {};
  const ids = [...(obj?.global?.workspaceIds ?? [])];
  const issues = [];
  for (const id of ids) if (!tables[id]) issues.push(`registry order references missing workspace '${id}'`);
  for (const id of Object.keys(tables)) if (!ids.includes(id)) issues.push(`workspace '${id}' absent from registry order`);
  const byPath = new Map();
  const accounted = new Map();
  for (const [id, rec] of Object.entries(tables)) {
    if (!rec || typeof rec.path !== 'string') { issues.push(`workspace '${id}' has no path`); continue; }
    const key = canonKey(rec.path);
    if (byPath.has(key)) issues.push(`path '${rec.path}' claimed by both '${byPath.get(key)}' and '${id}'`);
    else byPath.set(key, id);
    for (const s of rec.sessionIds ?? []) {
      if (accounted.has(s)) issues.push(`session '${s}' accounted by both '${accounted.get(s)}' and '${id}'`);
      else accounted.set(s, id);
    }
  }
  return { issues, ids, tables, byPath, accounted };
}

export function requireConsistent(obj) {
  const v = inspectWorkspace(obj);
  if (v.issues.length > 0) {
    throw new Error(`workspace domain inconsistent:\n  - ${v.issues.join('\n  - ')}\nRun preflight-check.mjs / reconcile first.`);
  }
  return v;
}

// Every workspace record whose sessionIds account for `sid`.
export function findOwners(v, sid) {
  return Object.entries(v.tables).filter(([, rec]) => (rec.sessionIds ?? []).includes(sid)).map(([id]) => id);
}

export function detachFrom(obj, wsId, sid) {
  const rec = obj?.tables?.workspaces?.[wsId];
  if (!rec) return false;
  if (!(rec.sessionIds ?? []).includes(sid)) return false;
  rec.sessionIds = rec.sessionIds.filter((id) => id !== sid);
  rec.updatedAt = new Date().toISOString();
  return true;
}

export function attachTo(obj, wsId, sid) {
  const rec = obj.tables.workspaces[wsId];
  if (!rec) throw new Error(`workspace '${wsId}' missing`);
  if ((rec.sessionIds ?? []).includes(sid)) return false;
  rec.sessionIds = [sid, ...rec.sessionIds]; // attachSession prepends
  rec.updatedAt = new Date().toISOString();
  return true;
}

// Create a workspace for an existing canonical directory (registry prepends).
export function createWorkspace(obj, canonicalCwd) {
  const g = obj.global;
  if (!g) throw new Error('workspace domain has no global block');
  const id = randomUUID();
  const now = new Date().toISOString();
  obj.tables.workspaces[id] = {
    path: canonicalCwd,
    title: path.basename(canonicalCwd),
    sessionIds: [],
    createdAt: now,
    updatedAt: now
  };
  g.workspaceIds = [id, ...(g.workspaceIds ?? [])];
  return id;
}
