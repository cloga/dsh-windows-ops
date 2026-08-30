// dsh-compat-check.mjs — DSH 桌面版插件入口兼容性检查器 v2（零依赖，node >= 18）
// 用法: node dsh-compat-check.mjs [profile] [--probe] [--probe=<pkg>] [--json]
//   缺省 profile=web；--probe 对插件做真实 import 加载测试（会执行插件顶层代码，慎用）；
//   --probe=<pkg> 只测指定插件；--json 输出可归档的结构化入口兼容报告。
// 原理: 插件能解析的包 = 插件目录 node_modules + <profile> 层 node_modules 白名单；
//       对比插件代码的 import/require 清单，找出加载即崩的缺失项。
// 边界: “通过”仅表示 import-compatible，不证明 Cordis 已激活、工具可用、功能正确或安全。
'use strict';

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFile } from 'node:child_process';

const HOME = process.env.DSH_HOME || path.join(os.homedir(), '.dsh');
const ARGS = process.argv.slice(2);
const profile = ARGS.find(a => !a.startsWith('--')) || 'web';
const NM = path.join(HOME, 'profiles', profile, 'node_modules');
const wantProbe = ARGS.includes('--probe') || ARGS.some(a => a.startsWith('--probe='));
const probeOnly = ARGS.find(a => a.startsWith('--probe='));
const wantJson = ARGS.includes('--json');

const NATIVE_RISK = /^(sharp|koffi|node-pty|better-sqlite3|onnxruntime-node|canvas|bufferutil|utf-8-validate|fsevents|esbuild)$/;

// ---------- helpers ----------
function exists(p) { try { fs.accessSync(p); return true; } catch { return false; } }
function dirs(p) {
  try {
    return fs.readdirSync(p, { withFileTypes: true }).filter(d => {
      if (d.isDirectory()) return true;
      if (d.isSymbolicLink()) { try { return fs.statSync(path.join(p, d.name)).isDirectory(); } catch { return false; } }
      return false;
    }).map(d => d.name);
  } catch { return []; }
}
function realDir(p) { try { return fs.realpathSync(p); } catch { return p; } }
function readJson(p) { try { return JSON.parse(fs.readFileSync(p, 'utf8')); } catch { return null; } }

function walkJs(root, out, depth) {
  if (depth > 5) return;
  let entries = [];
  try { entries = fs.readdirSync(root, { withFileTypes: true }); } catch { return; }
  for (const e of entries) {
    if (['node_modules', 'tests', 'test', 'src', 'docs', 'scripts', '.git', 'assets'].includes(e.name)) continue;
    const full = path.join(root, e.name);
    if (e.isDirectory()) walkJs(full, out, depth + 1);
    else if (e.name.endsWith('.js')) out.push(full);
  }
}

function normalizePkg(spec) {
  const parts = spec.split('/');
  return spec.startsWith('@') ? parts.slice(0, 2).join('/') : parts[0];
}

// 返回 [{pkg, file, kind}]，kind = 'static' | 'dynamic'
function extractImports(files) {
  const out = [];
  const seen = new Set();
  const rules = [
    { kind: 'static', re: /(?:import|export) +(?:[^'";]*? +from +)?['"]([^'"]+)['"]/g },
    { kind: 'static', re: /require\( *['"]([^'"]+)['"] *\)/g },
    { kind: 'dynamic', re: /import\( *['"]([^'"]+)['"] *\)/g },
  ];
  for (const file of files) {
    let src = '';
    try { src = fs.readFileSync(file, 'utf8'); } catch { continue; }
    for (const rule of rules) {
      rule.re.lastIndex = 0;
      let m;
      while ((m = rule.re.exec(src))) {
        const spec = m[1];
        if (!spec || spec.startsWith('.') || spec.startsWith('node:') || spec.startsWith('file:')) continue;
        const pkg = normalizePkg(spec);
        const key = pkg + '|' + rule.kind;
        if (!seen.has(key)) { seen.add(key); out.push({ pkg, file, kind: rule.kind }); }
      }
    }
  }
  return out;
}

// ---------- 极简 semver ----------
function cmpVer(a, b) {
  const pa = a.split('.').map(Number), pb = b.split('.').map(Number);
  for (let i = 0; i < 3; i++) {
    const x = pa[i] || 0, y = pb[i] || 0;
    if (x !== y) return x < y ? -1 : 1;
  }
  return 0;
}
function inCaret(v, r) {
  const a = r.split('.');
  const lo = a[0] + '.' + (a[1] || 0) + '.' + (a[2] || 0);
  const hi = Number(a[0]) > 0 ? String(Number(a[0]) + 1) + '.0.0'
    : a[1] !== undefined && Number(a[1]) > 0 ? '0.' + String(Number(a[1]) + 1) + '.0'
    : '0.0.' + String((Number(a[2]) || 0) + 1);
  return cmpVer(v, lo) >= 0 && cmpVer(v, hi) < 0;
}
function inTilde(v, r) {
  const a = r.split('.');
  const lo = a[0] + '.' + (a[1] || 0) + '.' + (a[2] || 0);
  const hi = a.length >= 3 ? a[0] + '.' + a[1] + '.' + String(Number(a[2]) + 1)
    : a.length === 2 ? a[0] + '.' + String(Number(a[1]) + 1) + '.0'
    : String(Number(a[0]) + 1) + '.0.0';
  return cmpVer(v, lo) >= 0 && cmpVer(v, hi) < 0;
}
function nodeSatisfies(range, verRaw) {
  if (!range) return true;
  const v = verRaw.replace(/^v/, '').split('-')[0].split('+')[0];
  const p = v.split('.');
  const verStr = Number(p[0]) + '.' + (Number(p[1]) || 0) + '.' + (Number(p[2]) || 0);
  return range.split('||').map(s => s.trim()).some(or => {
    return or.split(/ +/).filter(Boolean).every(cond => {
      if (cond === '*' || cond === 'x' || cond === 'latest') return true;
      if (cond.startsWith('^')) return inCaret(verStr, cond.slice(1));
      if (cond.startsWith('~')) return inTilde(verStr, cond.slice(1));
      const m = cond.match(/^(>=|<=|>|<|=)?([0-9]+(?:[.][0-9]+){0,2})$/);
      if (!m) return true; // 未知语法保守放行
      const op = m[1] || '=';
      if (op === '=') return cmpVer(verStr, m[2]) === 0;
      if (op === '>=') return cmpVer(verStr, m[2]) >= 0;
      if (op === '<=') return cmpVer(verStr, m[2]) <= 0;
      if (op === '>') return cmpVer(verStr, m[2]) > 0;
      if (op === '<') return cmpVer(verStr, m[2]) < 0;
      return true;
    });
  });
}

// ---------- 1. 白名单 ----------
const whitelist = new Set();
for (const name of dirs(NM)) {
  if (name.startsWith('@')) {
    for (const sub of dirs(path.join(NM, name))) whitelist.add(name + '/' + sub);
  } else if (name !== '.bin' && name !== '.pnpm') {
    whitelist.add(name);
  }
}
const isOfficial = pkg => pkg.startsWith('@deepseek-ai/');

// ---------- 2. 补丁启用的插件 ----------
function extractEnabledFromPatch(file) {
  if (!exists(file)) return [];
  const lines = fs.readFileSync(file, 'utf8').split('\n');
  const out = [];
  for (let i = 0; i < lines.length; i++) {
    const t = lines[i].trim();
    const idM = t.match(/^- id: *([^ ]+)/);
    if (!idM) continue;
    let name = null;
    for (let j = i + 1; j < lines.length; j++) {
      const s = lines[j].trim();
      if (!s || s.startsWith('#')) continue;
      const m = s.match(/^name: *['"]?([^'"]+?)['"]? *$/);
      if (m) { name = m[1].trim(); break; }
      if (/^- |^config:/.test(s)) break;
    }
    if (name) out.push({ id: idM[1], name, file: path.basename(file), line: i + 1 });
  }
  return out;
}
const enabled = [];
for (const p of [path.join(HOME, 'cordis.patch.yml'), path.join(HOME, 'profiles', profile, 'cordis.patch.yml')]) {
  enabled.push(...extractEnabledFromPatch(p));
}

// ---------- 3. 识别外来插件 ----------
const plugins = [];
for (const name of dirs(NM)) {
  if (name === '.pnpm' || name === '.bin' || name.endsWith('.bak')) continue;
  if (name.startsWith('@')) {
    for (const sub of dirs(path.join(NM, name))) {
      const pkg = name + '/' + sub;
      if (isOfficial(pkg)) continue;
      const dir = path.join(NM, name, sub);
      const pj = readJson(path.join(dir, 'package.json'));
      if (pj && (pj.dsh || exists(path.join(dir, 'cordis.patch.yml')))) plugins.push({ pkg, dir, pj });
    }
  } else {
    const dir = path.join(NM, name);
    const pj = readJson(path.join(dir, 'package.json'));
    if (pj && (pj.dsh || exists(path.join(dir, 'cordis.patch.yml')))) plugins.push({ pkg: name, dir, pj });
  }
}

// ---------- host 入口判定 ----------
function hostFiles(pj, dir) {
  const cands = [];
  if (pj && pj.main) cands.push(path.join(dir, pj.main));
  cands.push(path.join(dir, 'lib', 'index.js'), path.join(dir, 'index.js'));
  const out = [];
  for (const c of cands) { if (exists(c) && !out.includes(c)) out.push(c); }
  return out;
}

// ---------- 4. 逐插件检查 ----------
const out = [];
const reports = [];
const probes = [];
const fatalList = [], warnList = [], okList = [];
function resolveChain(pkg, pluginDir) {
  let isLink = false;
  try { isLink = fs.lstatSync(pluginDir).isSymbolicLink(); } catch {}
  if (!isLink && whitelist.has(pkg)) return true;
  if (exists(path.join(pluginDir, 'node_modules', pkg))) return true;
  let cur = realDir(pluginDir);
  for (let i = 0; i < 6; i++) {
    if (exists(path.join(cur, 'node_modules', pkg))) return true;
    const parent = path.dirname(cur);
    if (parent === cur) break;
    cur = parent;
  }
  return false;
}

for (const pl of plugins) {
  const { pkg, dir, pj } = pl;
  const files = [];
  walkJs(dir, files, 0);
  const host = hostFiles(pj, dir);
  const imports = extractImports(files);
  const isEnabled = enabled.some(e => e.name === pkg);
  const state = isEnabled ? '（补丁已启用）' : '（补丁未启用）';

  const fatal = [], warn = [], info = [];
  for (const it of imports) {
    const missing = resolveChain(it.pkg, dir) ? null : it.pkg;
    if (!missing) continue;
    const inHost = host.includes(it.file);
    const label = path.basename(it.file);
    if (inHost && it.kind === 'static') fatal.push(it.pkg + '（' + label + ' 顶层静态 import）');
    else if (inHost) warn.push(it.pkg + '（' + label + ' 动态 import）');
    else info.push(it.pkg + '（' + label + '，可能为 client 侧）');
  }

  const declaredMissing = [];
  for (const d of Object.keys(pj.dependencies || {})) {
    if (!resolveChain(d, dir)) declaredMissing.push(d);
  }
  const native = [];
  for (const it of imports) if (NATIVE_RISK.test(it.pkg)) native.push(it.pkg);
  const nodeFiles = files.filter(f => f.endsWith('.node'));
  const enginesOk = pj.engines && pj.engines.node ? nodeSatisfies(pj.engines.node, process.version) : true;
  const injectMissing = Array.isArray(pj.dsh && pj.dsh.client && pj.dsh.client.inject)
    ? pj.dsh.client.inject.filter(c => !whitelist.has(c) && !isOfficial(c)) : [];

  const verdict = [];
  if (fatal.length) verdict.push('致命: ' + fatal.length + ' 个顶层静态 import 解析不到 → 启用即崩(ERR_MODULE_NOT_FOUND)');
  if (warn.length) verdict.push('警告: ' + warn.length + ' 个动态 import 解析不到 → 运行到对应功能才崩');
  if (declaredMissing.length) verdict.push('警告: 声明依赖未安装: ' + declaredMissing.join(', '));
  if (native.length) verdict.push('风险: 原生模块 ' + native.join(', ') + '（DLL/二进制冲突风险）');
  if (nodeFiles.length) verdict.push('风险: 自带 .node 文件: ' + nodeFiles.map(f => path.basename(f)).join(', '));
  if (!enginesOk) verdict.push('警告: engines.node=' + pj.engines.node + ' 不满足当前 ' + process.version);
  if (injectMissing.length) verdict.push('警告: client.inject 缺失: ' + injectMissing.join(', ') + '（Web 端功能可能缺失）');
  if (!verdict.length) verdict.push('通过');

  const status = fatal.length ? 'load-fatal' : (warn.length || native.length || nodeFiles.length || !enginesOk || injectMissing.length || declaredMissing.length) ? 'import-warning' : 'import-compatible';
  const level = status === 'load-fatal' ? '[加载致命]' : status === 'import-warning' ? '[入口警告]' : '[入口兼容]';
  reports.push({
    package: pkg,
    version: pj.version || null,
    enabled: isEnabled,
    status,
    fatal,
    warnings: warn,
    informational: info,
    declaredMissing,
    nativeModules: [...new Set(native)],
    nativeFiles: nodeFiles.map(f => path.basename(f)),
    engines: pj.engines && pj.engines.node ? { required: pj.engines.node, current: process.version, compatible: enginesOk } : null,
    missingClientInject: injectMissing,
  });
  out.push(level + ' ' + pkg + ' v' + (pj.version || '?') + state);
  for (const v of verdict) out.push('  - ' + v);
  for (const f of fatal) out.push('    · ' + f);
  for (const w of warn) out.push('    · ' + w);
  for (const i of info) out.push('    · (信息) ' + i);
  out.push('');

  if (fatal.length) fatalList.push(pkg);
  else if (verdict.some(v => v.startsWith('警告') || v.startsWith('风险'))) warnList.push(pkg);
  else okList.push(pkg);
}

// ---------- 5. 补丁引用检查 ----------
out.push('==== 补丁 insert 引用检查 ====');
for (const e of enabled) {
  if (isOfficial(e.name)) { out.push('  [跳过] ' + e.id + ' → ' + e.name + '（官方包，宿主提供）'); continue; }
  out.push(plugins.some(p => p.pkg === e.name)
    ? '  [OK] ' + e.id + ' → ' + e.name + '（已安装）'
    : '  [致命] ' + e.id + ' → ' + e.name + '（补丁引用了未安装的插件！重启会报错）');
}

// ---------- 6. 实测加载（--probe） ----------
if (wantProbe) {
  out.push('', '==== 实测加载（import 插件 main，执行顶层代码） ====');
  for (const pl of plugins) {
    if (probeOnly && !pl.pkg.includes(probeOnly.split('=')[1])) continue;
    const hf = hostFiles(pl.pj, pl.dir);
    if (!hf.length) { out.push('  ' + pl.pkg + ': 无 main 入口，跳过'); continue; }
    const fileUrl = 'file:///' + hf[0].split('\\').join('/');
    const code = 'import("' + fileUrl + '").then(()=>{console.log("LOAD_OK");process.exit(0)}).catch(e=>{console.log("LOAD_FAIL: "+e.message);process.exit(1)})';
    const res = await new Promise(resolve => {
      execFile(process.execPath, ['--input-type=module', '-e', code], { timeout: 20000 }, (err, stdout, stderr) => {
        const s = (stdout || '').trim();
        const e = (stderr || '').trim();
        resolve(s || (err ? '进程失败: ' + err.message : '') + (e && !s ? ' | ' + e.split('\n')[0].slice(0, 200) : ''));
      });
    });
    probes.push({ package: pl.pkg, result: res, passed: res.includes('LOAD_OK') });
    out.push('  ' + pl.pkg + ': ' + res);
  }
}

// ---------- 7. 总结 ----------
out.push('', '==== 总结 ====');
out.push('  profile: ' + profile + ' | node: ' + process.version);
out.push('  白名单: ' + whitelist.size + ' 个可解析包 | 外来插件: ' + plugins.length + ' 个');
out.push('  入口兼容(' + okList.length + '): ' + (okList.join(', ') || '无'));
out.push('  入口警告/风险(' + warnList.length + '): ' + (warnList.join(', ') || '无'));
out.push('  加载致命(' + fatalList.length + '): ' + (fatalList.join(', ') || '无'));
out.push('');
out.push('说明:');
out.push('  1. [加载致命] = 插件 main 入口顶层静态 import 的包在解析链上不存在，加载插件即崩溃。');
out.push('  2. [入口兼容] 仅表示依赖解析与所请求的 import probe 通过，不证明 Cordis 激活、工具注册、端到端功能或安全性。');
out.push('  3. 解析链 = 插件目录 node_modules → ~/.dsh/profiles/' + profile + '/node_modules（白名单）→ 逐级向上。');
out.push('  4. 官方 @deepseek-ai/* 包在 runtime 与 ~/.dsh/profiles/node_modules 齐全；但 symlink/junction 插件按真实路径解析，可能够不到 Profile 依赖。');
out.push('  5. 修复思路: 普通目录插件把缺失包装进 Profile；junction 插件在真实路径补齐依赖或改用物理安装；装完重跑本脚本。');
out.push('  6. --probe / --probe=<pkg> 会执行 host 入口顶层代码；请只在一次性测试 Profile 中运行未知插件。');

if (wantJson) {
  console.log(JSON.stringify({
    schemaVersion: 1,
    kind: 'dsh-plugin-import-compatibility',
    generatedAt: new Date().toISOString(),
    profile,
    nodeVersion: process.version,
    profileNodeModules: NM,
    summary: { importCompatible: okList.length, importWarning: warnList.length, loadFatal: fatalList.length },
    plugins: reports,
    probes,
    limitations: ['Does not prove Cordis activation, tool registration, functional behavior, cleanup, or security.'],
  }, null, 2));
} else {
  console.log(out.join('\n'));
}
