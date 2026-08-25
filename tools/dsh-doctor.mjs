// dsh-doctor.mjs - health check + self-repair for the Tauri-based DSH install.
//
//   node dsh-doctor.mjs                 check only (report mode, fast)
//   node dsh-doctor.mjs --fix           check + auto-repair known issues
//   node dsh-doctor.mjs --smoke         check (+fix) then isolated boot test
//   node dsh-doctor.mjs --list-plugins  print the plugin manifest (for B snapshot)
//   node dsh-doctor.mjs --json          machine-readable output (agent/tool use)
//
// Every repair backs up the touched file/dir into
// $DSH_HOME/tools/backups/dsh-doctor/<timestamp>/ first. Run it after any
// plugin install/config change, and first thing after an incident.
// Designed for the Tauri shell (dsh-tauri-desk) + official DSH_HOME.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { pathToFileURL, fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';
import { spawnSync } from 'node:child_process';

const args = process.argv.slice(2);
const FIX = args.includes('--fix');
const SMOKE = args.includes('--smoke');
const JSON_OUT = args.includes('--json');
const LIST_PLUGINS = args.includes('--list-plugins');

const HOMEDIR = os.homedir();
const DSH_HOME = process.env.DSH_HOME || path.join(HOMEDIR, '.dsh');
const TOOLS = path.join(DSH_HOME, 'tools');
const BACKUP_ROOT = path.join(TOOLS, 'backups', 'dsh-doctor', new Date().toISOString().replace(/[:.]/g, '-'));
const SHELL_DIR = 'C:/Users/sephen/AppData/Local/Deepseek Harness Desktop';
const SHELL_EXE = path.join(SHELL_DIR, 'deepseek-harness-desktop.exe');
const SHELL_DATA = 'C:/Users/sephen/AppData/Roaming/io.github.hairyf.deepseek-harness-desktop';
const CORE_DIR = path.join(SHELL_DATA, 'dependencies', 'dsh');
const CORE_BIN = path.join(CORE_DIR, 'node_modules', '@deepseek-ai', 'dsh', 'lib', 'bin.js');
const RUNTIME_NODE = path.join(SHELL_DATA, 'runtime', 'node.exe');
const WORKER_CJS = path.join(CORE_DIR, 'node_modules', '@deepseek-ai', 'dsh-host-directory-picker-native', 'lib', 'worker.cjs');
const WORKER_READ_MARK = 'Fix (local 2026-08-19): koffi.view()';
const WORKER_COINIT_MARK = 'Fix (upstream discussion #768)';
const BRAND_FROM = 'DSH Local Build';
const BANNED = ['dsh-vision-router']; // known-crash plugins: keep out of the auto-discovery chain
const PATCHER = path.join(TOOLS, 'dsh-updater', 'patch-worker.mjs');
const SHELL_LOG = path.join(SHELL_DATA, 'logs', 'desktop.log');
const VENDOR_ZSTD = path.join(TOOLS, 'vendor', 'dsh-zstd', 'types', 'zstd.js');
const B_HOME = DSH_HOME + '-backup';
const PROFILES = ['web', 'headless'];

const report = [];
function rec(id, status, message, fixable = false, data = null) {
  report.push({ id, status, message, fixable, data });
}
function backupFile(p) {
  if (!fs.existsSync(p)) return null;
  const dst = path.join(BACKUP_ROOT, path.basename(p));
  fs.mkdirSync(BACKUP_ROOT, { recursive: true });
  fs.copyFileSync(p, dst);
  return dst;
}
function backupDir(p) {
  if (!fs.existsSync(p)) return null;
  fs.mkdirSync(BACKUP_ROOT, { recursive: true });
  fs.cpSync(p, path.join(BACKUP_ROOT, path.basename(p)), { recursive: true });
  return path.join(BACKUP_ROOT, path.basename(p));
}

// ---------------------------------------------------------------------------
// checks
// ---------------------------------------------------------------------------
function checkShell() {
  const ok = fs.existsSync(SHELL_EXE) && fs.existsSync(path.join(SHELL_DIR, 'resources', 'preset-plugins.json'));
  rec('shell', ok ? 'ok' : 'fail', ok ? 'Tauri shell present' : 'Tauri shell missing: ' + SHELL_EXE, !ok);
}
function checkCore() {
  const lacks = [RUNTIME_NODE, CORE_BIN].filter((p) => !fs.existsSync(p));
  let version = '';
  try { version = JSON.parse(fs.readFileSync(path.join(CORE_DIR, 'node_modules', '@deepseek-ai', 'dsh', 'package.json'), 'utf8')).version || ''; } catch { }
  const ok = lacks.length === 0;
  rec('core', ok ? 'ok' : 'fail', (ok ? 'core ' + version + ' present' : 'core incomplete: ' + lacks.join(', ')), !ok);
}
function checkPatches() {
  let src = '';
  try { src = fs.readFileSync(WORKER_CJS, 'utf8'); } catch { rec('patches', 'fail', 'worker.cjs missing', true); return; }
  const readOk = src.includes(WORKER_READ_MARK);
  const coinitOk = src.includes(WORKER_COINIT_MARK);
  const brandOk = !fs.readFileSync(path.join(CORE_DIR, 'node_modules', '@deepseek-ai', 'dsh-client-ui-renderer', 'lib', 'client.js'), 'utf8').includes(BRAND_FROM);
  const all = readOk && coinitOk && brandOk;
  rec('patches', all ? 'ok' : 'warn',
    'worker.readUtf16=' + readOk + ' worker.coUninit=' + coinitOk + ' brand=' + brandOk +
    (all ? '' : ' (missing patches - --fix reapplies via patch-worker)'), !all);
}
async function checkConfigYaml() {
  const targets = ['cordis.patch.yml', path.join('profiles', 'web', 'cordis.patch.yml'), path.join('profiles', 'headless', 'cordis.patch.yml'), 'settings.yaml'];
  const missing = [];
  const bad = [];
  let yaml = null;
  for (const cand of ['C:/Users/sephen/.dsh/profiles/node_modules/yaml/dist/index.js', 'C:/Users/sephen/.dsh/profiles/web/node_modules/yaml/dist/index.js']) {
    try { yaml = await import(pathToFileURL(cand).href); break; } catch { }
  }
  for (const rel of targets) {
    const p = path.join(DSH_HOME, rel);
    if (!fs.existsSync(p)) { missing.push(rel); continue; }
    if (yaml) {
      try { yaml.parse(fs.readFileSync(p, 'utf8')); } catch (e) { bad.push(rel + ': ' + e.message.slice(0, 80)); }
    }
  }
  const ok = missing.length === 0 && bad.length === 0;
  rec('config-yaml', ok ? 'ok' : 'warn',
    ok ? 'all config YAML parse' : (missing.length ? 'missing: ' + missing.join(', ') : '') + (bad.length ? ' unparseable: ' + bad.join(' | ') : ''),
    bad.length > 0);
}
function checkPluginLinks() {
  const problems = [];
  for (const prof of PROFILES) {
    const nm = path.join(DSH_HOME, 'profiles', prof, 'node_modules');
    if (!fs.existsSync(nm)) continue;
    for (const entry of fs.readdirSync(nm, { withFileTypes: true })) {
      if (entry.name === '.pnpm' || entry.name.startsWith('.') || entry.name.endsWith('.disabled')) continue;
      if (entry.name.startsWith('@')) {
        for (const sub of fs.readdirSync(path.join(nm, entry.name), { withFileTypes: true })) {
          if (sub.name === '.pnpm' || sub.name.startsWith('.') || sub.name.endsWith('.disabled')) continue;
          checkOneLink(path.join(nm, entry.name, sub.name), problems);
        }
        continue;
      }
      checkOneLink(path.join(nm, entry.name), problems);
    }
  }
  const broken = problems.filter((p) => p.kind === 'broken');
  const ok = broken.length === 0 && problems.length === 0;
  rec('plugin-links', ok ? 'ok' : (broken.length ? 'warn' : 'ok'),
    broken.length ? 'broken link(s): ' + broken.map((p) => p.target).join(', ') : (problems.length ? problems.map((p) => p.target + ' (stale-target note)').join(', ') : 'plugin node_modules links OK'),
    broken.length > 0);
  return broken;
}
function checkOneLink(p, problems) {
  while (true) { // follow to the deepest broken node
    const l = fs.lstatSync(p, { throwIfNoEntry: false });
    if (!l) break;
    if (!(l.isSymbolicLink() || l.isDirectory() === false && l.isSymbolicLink())) break;
    if (l.isSymbolicLink()) {
      const target = fs.readlinkSync(p);
      const abs = path.isAbsolute(target) ? target : path.resolve(path.dirname(p), target);
      const exists = fs.existsSync(abs);
      if (!exists) { problems.push({ kind: 'broken', target: p, real: abs, link: true }); return; }
      const rl = fs.realpathSync(p);
      const innerBroken = fs.existsSync(rl);
      if (!innerBroken) { problems.push({ kind: 'broken', target: p, real: rl, link: true, junction: true }); return; }
      return;
    }
    if (!l.isDirectory() && l.isSymbolicLink() === false) return;
    break;
  }
}
function checkDuplicateInserts() {
  const dup = []; // {id, patchFile, foundIn}
  const patchFiles = ['cordis.patch.yml', path.join('profiles', 'web', 'cordis.patch.yml')].map((r) => path.join(DSH_HOME, r));
  const pluginSelfPatch = new Map(); // id -> plugin dir
  const nm = path.join(DSH_HOME, 'profiles', 'web', 'node_modules');
  const scanDirs = [];
  for (const entry of fs.readdirSync(nm, { withFileTypes: true })) {
    if (entry.name === '.pnpm' || entry.name.startsWith('.')) continue;
    if (entry.name.startsWith('@')) {
      for (const sub of fs.readdirSync(path.join(nm, entry.name), { withFileTypes: true })) {
        if (!sub.name.startsWith('.')) scanDirs.push(path.join(nm, entry.name, sub.name));
      }
      continue;
    }
    if (!entry.name.startsWith('.')) scanDirs.push(path.join(nm, entry.name));
  }
  for (const dir of scanDirs) {
    const sp = path.join(dir, 'cordis.patch.yml');
    if (!fs.existsSync(sp)) continue;
    try {
      const t = fs.readFileSync(sp, 'utf8');
      const ids = [...t.matchAll(/^\s*-\s*id\s*:\s*([A-Za-z0-9_.@-]+)/gm)].map((m) => m[1]);
      for (const id of ids) pluginSelfPatch.set(id, path.basename(dir));
    } catch { }
  }
  for (const pf of patchFiles) {
    if (!fs.existsSync(pf)) continue;
    const t = fs.readFileSync(pf, 'utf8');
    for (const id of pluginSelfPatch.keys()) {
      // explicit insert + plugin self-patch = duplicate loader entry
      const clear = t.includes('- id: ' + id) && t.match(new RegExp('-\\s*id\\s*:\\s*' + id + '(?![\\w-])')) && !t.includes('DISABLED-BY-USER');
      if (clear) dup.push({ id, patchFile: pf, owner: pluginSelfPatch.get(id) });
    }
  }
  rec('dup-insert', dup.length === 0 ? 'ok' : 'warn',
    dup.length === 0 ? 'no duplicate loader registrations' : 'possible duplicates (explicit insert + plugin self-patch): ' + dup.map((d) => d.id).join(', '),
    dup.length > 0, dup);
  return dup;
}
function checkBanned() {
  const present = [];
  const nm = path.join(DSH_HOME, 'profiles', 'web', 'node_modules');
  for (const id of BANNED) {
    for (const cand of [path.join(nm, id), path.join(nm, '@dsh-external', id)]) {
      if (fs.existsSync(cand)) present.push(cand);
    }
  }
  rec('banned-plugins', present.length === 0 ? 'ok' : 'warn',
    present.length === 0 ? 'no banned plugins in discovery chain' : 'banned present: ' + present.join(', '),
    present.length > 0, present);
  return present;
}
function checkGit() {
  const probe = spawnSync('git', ['--version'], { encoding: 'utf8', timeout: 8000 });
  let inUserPath = false;
  try {
    const up = process.env.DSH_SKIP_HKLM || null;
    const userPath = spawnSync('powershell', ['-NoProfile', '-Command', "[Environment]::GetEnvironmentVariable('Path','User')"], { encoding: 'utf8', timeout: 10000 });
    inUserPath = (userPath.stdout || '').toLowerCase().includes('d:\\git\\cmd');
  } catch { }
  const ok = probe.status === 0;
  rec('git', ok ? 'ok' : 'warn',
    ok ? ('git ' + (probe.stdout || '').trim()) : ('git not on PATH' + (inUserPath ? ' (user PATH has D:\\Git\\cmd - new shells only; restart the shell)' : ' (add D:\\Git\\cmd to user PATH)')),
    false, null);
}
function checkVendor() {
  const ok = fs.existsSync(VENDOR_ZSTD);
  rec('vendor-zstd', ok ? 'ok' : 'fail', ok ? 'zstd vendor present' : 'zstd vendor missing: ' + VENDOR_ZSTD, !ok);
}
function checkBHome() {
  const ok = fs.existsSync(path.join(B_HOME, 'profiles'));
  let promoted = '';
  try { promoted = fs.readFileSync(path.join(B_HOME, 'PROMOTED.txt'), 'utf8').slice(0, 60); } catch { }
  rec('b-home', ok ? 'ok' : 'warn', ok ? ('B backup present' + (promoted ? ' (' + promoted + ')' : '')) : 'B home missing - run dsh-backup.ps1 -promote while healthy', !ok);
}
function checkShellProc() {
  const sh = spawnSync('powershell', ['-NoProfile', '-Command', "(Get-Process -Name 'deepseek-harness-desktop' -ErrorAction SilentlyContinue | Measure-Object).Count"], { encoding: 'utf8', timeout: 10000 });
  const n = parseInt((sh.stdout || '0').trim() || '0', 10);
  const web = spawnSync('powershell', ['-NoProfile', '-Command', "(Get-CimInstance Win32_Process | Where-Object { \$_.CommandLine -match 'dependencies..dsh' -and \$_.CommandLine -match 'bin..js' } | Measure-Object).Count"], { encoding: 'utf8', timeout: 10000 });
  const wn = parseInt((web.stdout || '0').trim() || '0', 10);
  const ok = n > 0 && wn > 0;
  rec('shell-proc', ok ? 'ok' : 'warn', ok ? ('shell running + dsh web running (' + wn + ')') : (n === 0 ? 'shell NOT running' : 'shell running but no dsh web (' + n + '/' + wn + ')'), n === 0);
}

// ---------------------------------------------------------------------------
// fixes
// ---------------------------------------------------------------------------
function fixPatches() {
  const r = spawnSync(process.execPath, [PATCHER, WORKER_CJS], { encoding: 'utf8', timeout: 120000 });
  return { done: r.status === 0, detail: (r.stdout || r.stderr || '').slice(0, 300) };
}
function fixBrokenLinks(broken) {
  const fixed = [];
  for (const b of broken) {
    try {
      const name = path.basename(b.target);
      const src = path.join(DSH_HOME, 'plugins', name);
      if (!fs.existsSync(src)) { fixed.push({ target: b.target, ok: false, reason: 'no source at ' + src }); continue; }
      // rebuild junction (Windows) / symlink
      fs.rmSync(b.target, { recursive: true, force: true });
      const r = spawnSync('cmd', ['/c', 'mklink', '/J', b.target, src], { encoding: 'utf8', timeout: 15000 });
      fixed.push({ target: b.target, ok: fs.existsSync(b.target), detail: (r.stdout || r.stderr || '').trim() });
    } catch (e) { fixed.push({ target: b.target, ok: false, reason: e.message }); }
  }
  return fixed;
}
function fixDuplicateInserts(dups) {
  // comment out the explicit insert block for each duplicated id (keep a note)
  const done = [];
  const byFile = new Map();
  for (const d of dups) { if (!byFile.has(d.patchFile)) byFile.set(d.patchFile, []); byFile.get(d.patchFile).push(d); }
  for (const [pf, items] of byFile) {
    let t = fs.readFileSync(pf, 'utf8');
    let changed = false;
    for (const it of items) {
      const re = new RegExp('([ \\t]*)-\\s*insert\\s*:\\s*\\n([ \\t]*)-\\s*id\\s*:\\s*' + it.id + '[\\s\\S]{0,400}?\\n(?=[ \\t]*[^-\\n]|\\s*\\n)');
      const m = t.match(re);
      if (!m) continue;
      backupFile(pf);
      t = t.replace(m[0], '[' + new Date().toISOString().slice(0, 10) + ' dsh-doctor] DISABLED-BY-USER duplicate registrations: ' + it.id + ' self-registers via its own cordis.patch.yml\n#     ' + m[0].replace(/\n/g, '\n#     ').trimEnd());
      changed = true;
      done.push({ patchFile: pf, id: it.id });
    }
    if (changed) fs.writeFileSync(pf, t, 'utf8');
  }
  return done;
}
function fixBanned(present) {
  const moved = [];
  for (const p of present) {
    try { backupDir(p); fs.renameSync(p, p + '.disabled'); moved.push(p + ' -> .disabled'); } catch (e) { moved.push(p + ' FAILED: ' + e.message); }
  }
  return moved;
}

// ---------------------------------------------------------------------------
// main
// ---------------------------------------------------------------------------
if (LIST_PLUGINS) {
  const manifest = { home: DSH_HOME, generatedAt: new Date().toISOString(), plugins: [] };
  for (const prof of PROFILES) {
    const nm = path.join(DSH_HOME, 'profiles', prof, 'node_modules');
    if (!fs.existsSync(nm)) continue;
    for (const entry of fs.readdirSync(nm, { withFileTypes: true })) {
      if (entry.name === '.pnpm' || entry.name.startsWith('.') || entry.name.startsWith('@') || !/^(dsh-|@dsh-external\/)/.test(entry.name)) continue;
      const dir = path.join(nm, entry.name);
      const l = fs.lstatSync(dir);
      let pkg = {};
      try { pkg = JSON.parse(fs.readFileSync(path.join(l.isSymbolicLink() ? fs.realpathSync(dir) : dir, 'package.json'), 'utf8')); } catch { }
      manifest.plugins.push({
        profile: prof, id: entry.name, version: pkg.version || '',
        type: l.isSymbolicLink() ? 'link' : 'dir',
        target: l.isSymbolicLink() ? fs.realpathSync(dir) : '',
        hasClientPatch: fs.existsSync(path.join(dir, 'cordis.patch.yml')),
        description: (pkg.description || '').slice(0, 80),
      });
    }
  }
  if (JSON_OUT) { console.log(JSON.stringify(manifest, null, 2)); }
  else {
    console.log('plugin manifest (' + manifest.plugins.length + '):');
    for (const p of manifest.plugins) console.log('  ' + p.profile + '/' + p.id + '@' + (p.version || '?') + (p.target ? ' -> ' + p.target : ''));
  }
  process.exit(0);
}

// check phase
await checkConfigYaml(); // uses top-level await; yaml probe inside
checkShell(); checkCore(); checkPatches(); checkPluginLinks(); checkDuplicateInserts(); checkBanned();
checkGit(); checkVendor(); checkBHome(); checkShellProc();

const summary = { fixMode: FIX, repairableFailures: report.filter((r) => r.fixable && r.status !== 'ok') };
if (FIX && summary.repairableFailures.length > 0) {
  fs.mkdirSync(BACKUP_ROOT, { recursive: true });
  console.log('[doctor] repairing ' + summary.repairableFailures.length + ' item(s) (backups -> ' + BACKUP_ROOT + ')');
  for (const r of summary.repairableFailures) {
    try {
      if (r.id === 'patches') { const f = fixPatches(); r.fixResult = f.done ? 'reapplied (patch-worker)' : 'FAILED: ' + f.detail; }
      else if (r.id === 'plugin-links') { r.fixResult = fixBrokenLinks(r.data || []).map((x) => x.ok ? x.target + ' rebuilt' : x.target + ' ' + (x.reason || '')).join('; '); }
      else if (r.id === 'dup-insert') { r.fixResult = fixDuplicateInserts(r.data || []).map((x) => x.id + ' disabled in ' + x.patchFile).join('; ') || 'no automated match (manual review)'; }
      else if (r.id === 'banned-plugins') { r.fixResult = fixBanned(r.data || []).join('; ') || 'none'; }
      else if (r.id === 'vendor-zstd') {
        const src = 'D:/deepseek-harness/DeepSeek Harness/resources/runtime/node_modules/@deepseek-ai/dsh-session-persistence-jsonl/lib/types';
        if (fs.existsSync(src)) {
          fs.mkdirSync(path.dirname(VENDOR_ZSTD), { recursive: true });
          fs.cpSync(src, path.dirname(VENDOR_ZSTD), { recursive: true });
          r.fixResult = fs.existsSync(VENDOR_ZSTD) ? 'vendor restored from old shell' : 'FAILED copy';
        } else r.fixResult = 'source missing (old shell gone) - vendor manually from workbuddy';
      }
    } catch (e) { r.fixResult = 'ERR ' + e.message; }
  }
  recheck();
}

function recheck() {
  // second pass after fixes for the affected items
  const pass = [];
  checkCore(); // cheap here; full rerun below
  // simplest correct rerun of the check phase
  report.length = 0;
  checkShell(); checkCore(); checkPatches(); checkPluginLinks(); checkDuplicateInserts(); checkBanned();
  checkGit(); checkVendor(); checkBHome(); checkShellProc();
}

if (SMOKE) {
  const r = spawnSync(process.execPath, [path.join(TOOLS, 'preflight-check.mjs'), '--smoke'], { encoding: 'utf8', timeout: 300000 });
  rec('smoke', (r.stdout || '').includes('SMOKE OK') ? 'ok' : 'fail', (r.stdout || r.stderr || '').replace(/\s+/g, ' ').slice(0, 160), true);
}

const fails = report.filter((r) => r.status === 'fail');
const warns = report.filter((r) => r.status === 'warn');
if (JSON_OUT) {
  console.log(JSON.stringify({ vendor: { node: process.version, dshHome: DSH_HOME }, summary: { fix: FIX, fails: fails.length, warns: warns.length }, checks: report }, null, 2));
} else {
  for (const r of report) {
    const mark = r.status === 'ok' ? 'OK  ' : r.status === 'warn' ? 'WARN' : 'FAIL';
    console.log('[' + mark + '] ' + r.id.padEnd(15) + r.message + (r.fixResult ? '  => ' + r.fixResult : ''));
  }
  console.log('');
  console.log('summary: ' + report.length + ' checks, ' + fails.length + ' fail, ' + warns.length + ' warn' + (FIX ? ' (fix mode)' : ''));
  console.log(fails.length === 0 ? (warns.length === 0 ? 'ALL HEALTHY - you are good.' : 'HEALTHY with notes (see WARN).') : 'ISSUES FOUND - fix with: node dsh-doctor.mjs --fix');
}
process.exit(fails.length === 0 ? 0 : 1);
