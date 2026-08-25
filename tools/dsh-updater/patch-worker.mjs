// patch-worker.mjs — 目录选择器 worker.cjs 补丁（#768 CoUninitialize 崩溃 + #580/koffi.view 读取崩溃）
// 用法: node patch-worker.mjs <worker.cjs路径> [--force]
//   已补丁 -> 输出 {status:'already'}; 未补丁 -> 备份后应用 -> {status:'patched'};
//   文件缺失 -> {status:'missing'}; 片段不匹配 -> {status:'mismatch', detail}
'use strict';
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const SCRIPT_DIR = path.dirname(fileURLToPath(import.meta.url));

const args = process.argv.slice(2);
const target = path.resolve(args[0] || '');
const force = args.includes('--force');

const PATCH_READ = {
  old: `function readUtf16(koffi, address) {
\tconst bytes = Buffer.from(koffi.view(address, 32768));
\tlet end = 0;
\twhile (end + 1 < bytes.length && bytes[end] !== 0) end += 2;
\treturn bytes.toString("utf16le", 0, end);
}`,
  new: `function readUtf16(koffi, address) {
\t// Fix (local 2026-08-19): koffi.view() fatally crashes on this host
\t// (koffi 3.1.5 + Node 22: "FATAL ERROR: Error::New napi_get_last_error_info"),
\t// killing the worker right after the user picks a folder. Plain FFI calls
\t// work fine, so use lstrlenW for the exact length and RtlMoveMemory to
\t// copy the bytes instead of koffi's memory-view APIs.
\tconst kernel32 = koffi.load("kernel32.dll");
\tconst lstrlenW = kernel32.func("__stdcall", "lstrlenW", "int32", ["void *"]);
\tconst rtlMoveMemory = kernel32.func("__stdcall", "RtlMoveMemory", "void", ["void *", "void *", "uint32"]);
\tconst chars = lstrlenW(address);
\tif (chars <= 0) return "";
\tconst bytes = chars * 2;
\tconst raw = Buffer.alloc(bytes);
\trtlMoveMemory(raw, address, bytes);
\treturn raw.toString("utf16le", 0, bytes);
}`,
  marker: 'Fix (local 2026-08-19): koffi.view()',
};

const PATCH_COINIT = {
  old: `\t} finally {
\t\tbindings.coUninitialize();
\t}`,
  new: `\t} finally {
\t\t// Fix (upstream discussion #768): calling CoUninitialize after the modal
\t\t// dialog on this koffi STA thread segfaults on some Windows 11 builds,
\t\t// killing the worker before it reports its result. The worker is a
\t\t// short-lived child process that exits right after reporting; the OS
\t\t// reclaims the COM apartment, so omitting it is safe.
\t}`,
  marker: 'Fix (upstream discussion #768)',
};

// 本地品牌名补丁：客户端默认 "DSH Local Build" -> "DeepSeek Harness v<version>"
// （2026-08-22；版本动态取自 runtime package.json，窗口标题栏蓝色 logo 后显示
// "… — DeepSeek Harness v0.1.1-rc.2"；升级后重打自动换成新版本）。
// 覆盖三处：窗口标题默认(DocumentTitle)、侧边栏 fallback 品牌、静态 index.html title。
const BRAND_FROM = 'DSH Local Build';
const BRAND_FILES = [
  'node_modules/@deepseek-ai/dsh-client-ui-renderer/lib/client.js',
  'node_modules/@deepseek-ai/dsh-client-ui-sidebar/lib/client.js',
  'node_modules/@deepseek-ai/dsh-web-frontend/dist/index.html',
];
function applyBrand(runtimeRoot) {
  const rep = { status: 'brand', applied: [], skipped: [] };
  let version = '';
  try { version = JSON.parse(fs.readFileSync(path.join(runtimeRoot, 'package.json'), 'utf8')).version || ''; } catch { }
  const target = 'DeepSeek Harness' + (version ? ' v' + version : '');
  // matches "DeepSeek Harness" with an optional previous " v<ver>" suffix
  const re = /DeepSeek Harness(?: v[0-9][\w.\-]*)?/g;
  for (const rel of BRAND_FILES) {
    const p = path.join(runtimeRoot, rel);
    if (!fs.existsSync(p)) { rep.skipped.push(rel + ':missing'); continue; }
    const src = fs.readFileSync(p, 'utf8');
    if (src.includes(target)) { rep.skipped.push(rel + ':already'); continue; }
    const bak = p + '.brand-bak-' + new Date().toISOString().slice(0, 10).replace(/-/g, '');
    if (!fs.existsSync(bak)) fs.copyFileSync(p, bak);
    fs.writeFileSync(p, src.replace(re, target));
    rep.applied.push(rel);
  }
  return rep;
}

// LOCAL-VISION-FORCE：dsh-llm-deepseek adapter resolveModels 强制 vision 模型 image-capable
// + 移除遮蔽 0.1.1 的旧 web-NM adapter 副本（2026-08-22 终极根因：profiles\web\node_modules
//   @deepseek-ai\dsh-llm-deepseek 为旧 v0.1.0-rc.6（无 vision），遮蔽 runtime 0.1.1）。
const LLM_MARKER = 'LOCAL-VISION-FORCE';
const LLM_OLD = 'const inputModalities = model.inputModalities ?? ["text"];';
const LLM_NEW = 'let inputModalities = model.inputModalities ?? ["text"]; /* LOCAL-VISION-FORCE 2026-08-22 */ if (/vision|multimodal|image/i.test(model.id) && !inputModalities.includes("image")) { inputModalities = [...inputModalities, "image"]; }';
const WEB_NM_LLM = 'C:/Users/sephen/.dsh/profiles/web/node_modules/@deepseek-ai/dsh-llm-deepseek';
function applyAdapterPatches(runtimeRoot) {
  const rep = { status: 'adapter', applied: [], skipped: [] };
  const p = path.join(runtimeRoot, 'node_modules', '@deepseek-ai', 'dsh-llm-deepseek', 'lib', 'index.js');
  if (fs.existsSync(p)) {
    const src = fs.readFileSync(p, 'utf8');
    if (src.includes(LLM_MARKER)) rep.skipped.push('adapter:already');
    else if (src.includes(LLM_OLD)) {
      const bak = p + '.bak-' + new Date().toISOString().slice(0, 10).replace(/-/g, '');
      if (!fs.existsSync(bak)) fs.copyFileSync(p, bak);
      fs.writeFileSync(p, src.split(LLM_OLD).join(LLM_NEW));
      rep.applied.push('adapter:vision-force');
    } else rep.skipped.push('adapter:fragment-missing');
  } else rep.skipped.push('adapter:missing');
  // shadowing old adapter copy in the web profile NM layer
  if (fs.existsSync(WEB_NM_LLM)) {
    const st = fs.lstatSync(WEB_NM_LLM);
    if (st.isSymbolicLink()) rep.skipped.push('webnm:junction-ok');
    else { fs.renameSync(WEB_NM_LLM, WEB_NM_LLM + '.old-shadow'); rep.applied.push('webnm-removed-shadow'); }
  } else rep.skipped.push('webnm:none');
  return rep;
}

function main() {
  if (!target) { console.log(JSON.stringify({ status: 'no-target' })); process.exit(1); }
  if (!fs.existsSync(target)) { console.log(JSON.stringify({ status: 'missing', target })); process.exit(0); }

  // 品牌名补丁（独立于 worker 补丁，任何分支都执行）
  const runtimeRoot = path.resolve(target, '..', '..', '..', '..', '..');
  const brand = applyBrand(runtimeRoot);
  const adapter = applyAdapterPatches(runtimeRoot);

  // 桌面壳补丁（官方 @electron/asar 工具；应用运行时文件锁定会返回 locked 并跳过，
  // 升级流程中应用已停止 -> 自动执行）。旧手写重打包器已废弃（损坏 asar 事故）。
  let asarPatch = 'not-run';
  try {
    asarPatch = execFileSync(process.execPath, [path.join(SCRIPT_DIR, 'dsh-patch-asar-official.mjs')], { encoding: 'utf8' }).trim();
  } catch (e) {
    asarPatch = 'asar-patch-error: ' + (e && e.message ? e.message : String(e));
  }

  let src = fs.readFileSync(target, 'utf8');
  const already = src.includes(PATCH_READ.marker) && src.includes(PATCH_COINIT.marker);

  if (already && !force) {
    console.log(JSON.stringify({ status: 'already', target, brand, adapter, asarPatch }));
    process.exit(0);
  }

  // 备份原文件（带时间戳）
  const bak = target + '.bak-' + new Date().toISOString().slice(0, 10).replace(/-/g, '');
  if (!fs.existsSync(bak)) fs.copyFileSync(target, bak);

  const report = { status: 'patched', applied: [], skipped: [], target };
  for (const [name, p] of [['readUtf16', PATCH_READ], ['coUninitialize', PATCH_COINIT]]) {
    const isApplied = src.includes(p.marker);
    if (isApplied) { report.skipped.push(name); continue; }
    if (!src.includes(p.old)) { report.skipped.push(name + ':fragment-missing'); continue; }
    src = src.split(p.old).join(p.new);
    report.applied.push(name);
  }

  fs.writeFileSync(target, src);
  // 校验
  report.verify = {
    read: src.includes(PATCH_READ.marker),
    coinit: src.includes(PATCH_COINIT.marker),
  };
  if (!report.verify.read || !report.verify.coinit) report.status = 'partial';
  report.brand = brand;
  report.adapter = adapter;
  report.asarPatch = asarPatch;
  console.log(JSON.stringify(report));
}

main();
