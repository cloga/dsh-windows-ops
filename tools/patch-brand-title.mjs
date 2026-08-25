// =============================================================================
// [HISTORICAL - 2026-08-25] Electron 时代工具：Tauri 壳已将其功能取代——
//   品牌补丁由 patch-worker.mjs applyBrand 覆盖（3 文件），窗口标题由壳/dsh-tauri 管理。
//   保留仅作版本号嵌入标题的思路参考，不再用于本机。
// =============================================================================
// patch-brand-title.mjs - Windows packaged DSH: window-title brand + version
//
// Why: the official DSH client default window title is a local-build marker
// ("DSH Local Build") with no product name or version. The Electron window
// title (native title bar after the blue logo, and the browser tab title)
// follows the page's document.title, which is set by
// @deepseek-ai/dsh-client-ui-renderer#DocumentTitle.js:
//
//   const DEFAULT_CLIENT_TITLE = "DSH Local Build";
//   document.title = sessionTitle ? `${sessionTitle} — ${productTitle}` : productTitle;
//
// This script rewrites DEFAULT_CLIENT_TITLE to "DeepSeek Harness v<version>",
// where <version> is read live from the runtime package.json - so after every
// runtime upgrade the title auto-carries the NEW version (idempotent: rerun
// after upgrades; already-patched files are skipped).
//
// Usage:
//   node patch-brand-title.mjs <runtime-root>          # e.g. .../resources/runtime
//   DSH_BRAND_TITLE_NAME="My Harness" node patch-brand-title.mjs <runtime-root>
// Env overrides:
//   DSH_BRAND_TITLE_NAME   - product name (default "DeepSeek Harness")
//   DSH_BRAND_INCLUDE_VER  - "0" to omit the version suffix (default "1")
//
// Backs up each touched file as .brand-bak-<yyyymmdd> before the first patch.
// Official runtime files touched:
//   node_modules/@deepseek-ai/dsh-client-ui-renderer/lib/client.js   (DocumentTitle)
//   node_modules/@deepseek-ai/dsh-client-ui-sidebar/lib/client.js    (sidebar brand fallback)
//   node_modules/@deepseek-ai/dsh-web-frontend/dist/index.html       (static <title>)
import fs from 'node:fs';
import path from 'node:path';

const runtimeRoot = process.argv[2];
if (!runtimeRoot || !fs.existsSync(path.join(runtimeRoot, 'package.json'))) {
  console.error('usage: node patch-brand-title.mjs <runtime-root>  (runtime root containing package.json)');
  process.exit(2);
}

const productName = process.env.DSH_BRAND_TITLE_NAME || 'DeepSeek Harness';
const includeVersion = process.env.DSH_BRAND_INCLUDE_VER !== '0';
let version = '';
try { version = JSON.parse(fs.readFileSync(path.join(runtimeRoot, 'package.json'), 'utf8')).version || ''; } catch {}

const target = productName + ((includeVersion && version) ? ' v' + version : '');
// Two old forms exist across versions: the local-build marker
// ("DSH Local Build") and the shipped product name with an optional
// version suffix ("DeepSeek Harness v0.1.0-rc.8"). Replace either with
// the target string, so the patch stays idempotent across upgrades.
const re = /DSH Local Build|DeepSeek Harness(?: v[0-9][\w.\-]*)?/g;

const FILES = [
  'node_modules/@deepseek-ai/dsh-client-ui-renderer/lib/client.js',
  'node_modules/@deepseek-ai/dsh-client-ui-sidebar/lib/client.js',
  'node_modules/@deepseek-ai/dsh-web-frontend/dist/index.html',
];

const rep = { status: 'brand', target, applied: [], skipped: [] };
let encounteredDshLocalBuild = false;

for (const rel of FILES) {
  const p = path.join(runtimeRoot, rel);
  if (!fs.existsSync(p)) { rep.skipped.push(rel + ':missing'); continue; }
  const src = fs.readFileSync(p, 'utf8');
  if (!/(DSH Local Build|DeepSeek Harness)/.test(src)) { rep.skipped.push(rel + ':no-title-match'); continue; }
  if (src.includes(target)) { rep.skipped.push(rel + ':already'); continue; }
  if (/DSH Local Build/.test(src)) encounteredDshLocalBuild = true;
  const bak = p + '.brand-bak-' + new Date().toISOString().slice(0, 10).replace(/-/g, '');
  if (!fs.existsSync(bak)) fs.copyFileSync(p, bak);
  fs.writeFileSync(p, src.replace(re, target));
  rep.applied.push(rel);
}

console.log(JSON.stringify(rep));
if (encounteredDshLocalBuild) {
  console.error('note: replaced the local-build marker "DSH Local Build" with the product name (real upstream may show it by design; see docs).');
}

