// Self-test for dsh-move-session.mjs v2 (file move + workspace registry sync).
// Runs FULLY ISOLATED: a scratch DSH_HOME is built with a synthetic session
// (official zstd frames) and a synthetic workspace domain, the real tool is
// invoked as a child process, then every invariant is asserted.
//
// Usage:  node dsh-move-session.selftest.mjs
// (uses $env:DSH_SMOKE_NODE / DSH_SMOKE_NODE for node>=22, falls back to 'node')
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { spawnSync } from 'node:child_process';

const NODE = process.env.DSH_SMOKE_NODE || 'node';
const zstdUrl = pathToFileURL(
  (process.env.DSH_ZSTD || 'D:/deepseek-harness/DeepSeek Harness/resources/runtime/node_modules/@deepseek-ai/dsh-session-persistence-jsonl/lib/types/zstd.js')
).href;
const zstd = await import(zstdUrl);

const tool = path.join(process.env.DSH_TOOLS_DIR || path.join(os.homedir(), '.dsh', 'tools'), 'dsh-move-session.mjs');
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'dsh-move-test-'));
const rootHome = path.join(tmp, 'home');
const srcCwd = path.join(tmp, 'TestMoveSrc');
const dstCwd = path.join(tmp, 'TestMoveDest');
fs.mkdirSync(path.join(rootHome, 'sessions', '--D-TestMoveSrc--'), { recursive: true });
fs.mkdirSync(rootHome, { recursive: true });
fs.mkdirSync(srcCwd);
fs.mkdirSync(dstCwd);

const SID = 'session-00000000-0000-4000-8000-000000000001';

async function frame(line) {
  return zstd.compressZstdFrame(Buffer.from(line + '\n', 'utf8'));
}
const headerLine = JSON.stringify({
  type: 'session', version: 2, id: SID, cwd: srcCwd,
  createdAt: Date.now(), delegationDepth: 0, agentPreset: 'cordis'
});
const srcSession = path.join(rootHome, 'sessions', '--D-TestMoveSrc--', SID, 'session.jsonl.zstd');
fs.mkdirSync(path.dirname(srcSession), { recursive: true });
fs.writeFileSync(srcSession, Buffer.concat([
  await frame(headerLine),
  await frame(JSON.stringify({ type: 'permission/preset', seq: 1, time: Date.now(), data: { preset: 'default' } })),
  await frame(JSON.stringify({ type: 'user/message', seq: 2, time: Date.now(), data: { content: [{ type: 'text', text: 'hi' }] } }))
]));

const OLD_WS = '11111111-1111-4111-8111-111111111111';
const workspaceFile = path.join(rootHome, 'storages', 'workspace.json');
fs.mkdirSync(path.dirname(workspaceFile), { recursive: true });
const now = new Date().toISOString();
fs.writeFileSync(workspaceFile, JSON.stringify({
  unit: { name: 'workspace', version: 2 },
  global: {
    initialized: true,
    workspaceIds: [OLD_WS],
    archivedSessionIds: []
  },
  tables: {
    workspaces: {
      [OLD_WS]: {
        path: srcCwd, title: 'TestMoveSrc', sessionIds: [SID], createdAt: now, updatedAt: now
      }
    }
  }
}, null, 2) + '\n');

function runTool(args) {
  return spawnSync(NODE, [tool, ...args], {
    env: { ...process.env, DSH_HOME: rootHome },
    encoding: 'utf8', timeout: 120000
  });
}

let failures = 0;
function check(name, cond, detail) {
  if (cond) console.log('  PASS  ' + name);
  else { failures++; console.log('  FAIL  ' + name + (detail ? ' — ' + detail : '')); }
}

console.log('== synthetic setup complete (DSH_HOME=' + rootHome + ') ==');

console.log('\n[run 1] move ' + SID + ' -> ' + dstCwd);
const r1 = runTool([SID, dstCwd]);
if (r1.status !== 0) { console.log(r1.stdout + '\n' + r1.stderr); failures++; }
check('tool exit 0', r1.status === 0, 'status=' + r1.status + ' stderr=' + (r1.stderr || '').slice(0, 200));
check('reports DONE', /DONE: moved/.test(r1.stdout || ''));
check('old project dir removed', !fs.existsSync(path.join(rootHome, 'sessions', '--D-TestMoveSrc--', SID)));
const projMatch = /projectKey: (--[A-Za-z0-9._-]+--)/.exec((r1.stdout || '') + (r1.stderr || ''));
const newProj = projMatch ? projMatch[1] : '--D-TestMoveDest--';
const newFile = path.join(rootHome, 'sessions', newProj, SID, 'session.jsonl.zstd');
check('new session file exists', fs.existsSync(newFile));
// header cwd
const zbuf = fs.readFileSync(newFile);
const { frames } = zstd.scanZstdFrames(zbuf, { maxFrames: 1000000 });
const firstLine = Buffer.from(await zstd.decompressZstdFrame(zbuf.subarray(frames[0].start, frames[0].end))).toString('utf8').split('\n')[0];
check('header.cwd rewritten', JSON.parse(firstLine).cwd === dstCwd, JSON.parse(firstLine).cwd);
check('row count preserved', frames.length === 3, 'frames=' + frames.length);
// workspace registry
const ws = JSON.parse(fs.readFileSync(workspaceFile, 'utf8'));
const oldRec = ws.tables.workspaces[OLD_WS];
check('old workspace detached', !(oldRec.sessionIds ?? []).includes(SID));
const wsKeys = Object.keys(ws.tables.workspaces);
const newId = wsKeys.find((k) => ws.tables.workspaces[k].path === dstCwd);
check('new workspace created', newId !== undefined);
check('new workspace owns session', newId !== undefined && (ws.tables.workspaces[newId].sessionIds ?? []).includes(SID));
check('new workspace prepended', newId !== undefined && ws.global.workspaceIds[0] === newId);
check('session accounted exactly once', wsKeys.every((k) => (ws.tables.workspaces[k].sessionIds ?? []).filter((s) => s === SID).length === (k === newId ? 1 : 0)));
// backup
const bakFiles = fs.existsSync(path.join(rootHome, 'tools', 'backups'))
  ? fs.readdirSync(path.join(rootHome, 'tools', 'backups')).filter((n) => n.startsWith(SID))
  : [];
check('backup exists outside sessions', bakFiles.length === 1 && fs.existsSync(path.join(rootHome, 'tools', 'backups', bakFiles[0], 'session.jsonl.zstd')));

console.log('\n[run 2] idempotence (run again)');
const r2 = runTool([SID, dstCwd]);
check('second run is no-op', r2.status === 0 && /no-op|already|consistent/.test(r2.stdout || ''), (r2.stdout || '').split('\n').slice(-3).join(' | '));

console.log('\n[run 3] dry-run does not write');
const pre = fs.readFileSync(workspaceFile, 'utf8');
const r3 = runTool([SID, dstCwd, '--dry-run']);
check('dry-run exit 0', r3.status === 0);
check('dry-run writes nothing', fs.readFileSync(workspaceFile, 'utf8') === pre);

console.log('\n[run 4] delete protection (fake duplicate)');
fs.mkdirSync(path.join(rootHome, 'sessions', '--D-DeepSeek--', SID), { recursive: true });
fs.copyFileSync(newFile, path.join(rootHome, 'sessions', '--D-DeepSeek--', SID, 'session.jsonl.zstd'));
const r4 = runTool([SID, dstCwd]);
check('duplicate aborts', r4.status !== 0 && /EXACTLY ONE/.test((r4.stdout || '') + (r4.stderr || '')), 'status=' + r4.status + ' out=' + ((r4.stdout || '') + (r4.stderr || '')).slice(-300));

fs.rmSync(tmp, { recursive: true, force: true });
fs.rmSync(dstCwd, { recursive: true, force: true });
console.log('\n== ' + (failures === 0 ? 'ALL PASS' : failures + ' FAILURE(S)') + ' ==');
process.exit(failures === 0 ? 0 : 1);
