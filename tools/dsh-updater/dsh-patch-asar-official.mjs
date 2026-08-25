// dsh-patch-asar-official.mjs - desktop shell patch via OFFICIAL @electron/asar
// purpose: pass --no-open to the web service so 0.1.1's default openBrowser
//          does not open an extra browser tab on every app start.
// IMPLEMENTATION NOTE (2026-08-22): the previous handwritten asar re-packager
//   (dsh-patch-asar.mjs, now .DISABLED) rebuilt the byte layout by hand and
//   corrupted the archive (entry moved to src/files/ -> Electron could not
//   find src/main.mjs -> silent exit). This script extracts to a real temp
//   directory, patches the source file, and re-packs with the OFFICIAL tool.
//   NEVER hand-edit asar bytes again.
// Usage: node dsh-patch-asar-official.mjs   (idempotent, mismatch-safe)
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

// @electron/asar v4 is ESM-only: load it with a dynamic import.
const ASAR_PKG_DIR = 'C:/Users/sephen/.dsh/tools/asar-tool/node_modules/@electron/asar';
const asarMain = JSON.parse(fs.readFileSync(path.join(ASAR_PKG_DIR, 'package.json'), 'utf8')).main || 'lib/asar.js';
const asarMod = await import(pathToFileURL(path.join(ASAR_PKG_DIR, asarMain)).href);
const asar = asarMod.default ?? asarMod;

const APP = 'D:/deepseek-harness/DeepSeek Harness/resources/app.asar';
const MARKER = "'--no-open'";
const OLD_ARGS = "'web', '--host', '127.0.0.1', '--port', '0'";
const NEW_ARGS = "'web', '--host', '127.0.0.1', '--port', '0', '--no-open'";

function normList(raw) {
  return raw.map((e) => String(e).replace(/\\/g, '/'));
}

async function main() {  // 0. sanity: current archive must expose the real entry layout
  const entries = normList(asar.listPackage(APP));
  const hasMain = entries.includes('/src/main.mjs');
  const hasPkg = entries.includes('/package.json');
  if (!hasMain || !hasPkg) {
    console.log(JSON.stringify({ status: 'abort-not-original-layout', hasMain, hasPkg }));
    process.exit(3);
  }

  // 1. is it already patched?
  const currentMain = asar.extractFile(APP, 'src/main.mjs').toString('utf8');
  if (currentMain.includes(MARKER)) {
    console.log(JSON.stringify({ status: 'already', hasMain, hasPkg }));
    process.exit(0);
  }
  if (!currentMain.includes(OLD_ARGS)) {
    console.log(JSON.stringify({ status: 'mismatch', detail: 'spawn args pattern not found' }));
    process.exit(2);
  }

  // 2. extract to real temp dir, patch the source file
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'dsh-asar-'));
  asar.extractAll(APP, tmp);
  const mainSrc = path.join(tmp, 'src', 'main.mjs');
  let patched = fs.readFileSync(mainSrc, 'utf8').split(OLD_ARGS).join(NEW_ARGS);
  fs.writeFileSync(mainSrc, patched);

  // 3. backup then pack with the official tool
  const bak = APP + '.bak-before-noopen';
  if (!fs.existsSync(bak)) fs.copyFileSync(APP, bak);
  const newFile = APP + '.new';
  if (fs.existsSync(newFile)) fs.rmSync(newFile, { recursive: true, force: true });
  await asar.createPackage(tmp, newFile);

  // 4. verify before swap
  const vEntries = normList(asar.listPackage(newFile));
  const okMain = vEntries.includes('/src/main.mjs');
  const okPkg = vEntries.includes('/package.json');
  const checkMain = asar.extractFile(newFile, 'src/main.mjs').toString('utf8');
  const pkg = JSON.parse(asar.extractFile(newFile, 'package.json').toString('utf8'));
  const okMarker = checkMain.includes(MARKER);
  const okMainField = pkg.main === 'src/main.mjs';
  if (!okMain || !okPkg || !okMarker || !okMainField) {
    console.log(JSON.stringify({ status: 'verify-failed', okMain, okPkg, okMarker, okMainField }));
    process.exit(4);
  }

  // 5. swap (only possible while the app is closed; locked app => skip)
  try {
    fs.rmSync(APP, { force: true });
    fs.renameSync(newFile, APP);
  } catch (e) {
    try { fs.rmSync(newFile, { force: true }); } catch { }
    console.log(JSON.stringify({ status: 'locked', detail: (e && e.message) || String(e), backup: bak }));
    process.exit(0);
  }
  console.log(JSON.stringify({
    status: 'patched',
    backup: bak,
    entries: vEntries,
    mainField: pkg.main,
    verified: { okMain, okPkg, okMarker, okMainField },
  }));
  // cleanup temp
  try { fs.rmSync(tmp, { recursive: true, force: true }); } catch { }
}

await main();
