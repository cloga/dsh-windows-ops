// CI-only data extraction of one verified NSIS release. Never executes an installer.
// The maintained existing runner 7-Zip supplies all binary-format decoding.
import { closeSync, lstatSync, mkdirSync, openSync, readSync, readdirSync } from 'node:fs';
import { dirname, isAbsolute, join, relative, resolve, sep } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { parseArgs, TextDecoder } from 'node:util';
import { hashFile, hashValid, inside, physical, relativeName, safeReason } from './native-runtime-integrity.mjs';
import { probeEnvironment } from './native-asar-runtime.mjs';
import { runArchiveProcess } from './native-archive-process.mjs';

export const archiveLimits = Object.freeze({ listingBytes: 32 * 1024 * 1024, payloadBytes: 4 * 1024 ** 3,
  innerBytes: 16 * 1024 ** 3, entries: 200000, depth: 128, timeoutMs: 180000 });
const need = (condition, reason) => { if (!condition) throw new Error(`native-archive-${reason}`); };
const longMax = (1n << 63n) - 1n;
const stages = ['preflight', 'nsis-listing', 'nsis-selected-stream', '7z-listing', '7z-extraction', 'extracted-inventory'];
async function atStage(stage, run) {
  try { return await run(); }
  catch (error) { const failure = new Error(safeReason(error)); failure.stage = stage; throw failure; }
}
function listingPath(value) {
  need(typeof value === 'string' && value.length > 0 && value.length <= 32760 && !/\x7f/u.test(value), 'path-invalid');
  const name = value.replaceAll('\\', '/'); relativeName(name);
  need(name.split('/').length <= archiveLimits.depth, 'path-depth-limit');
  return name;
}
function sizeValue(value, format) {
  // NsisHandler can expose VT_EMPTY for a REGULAR file. Numeric solid sizes can
  // also be estimates. Neither unknown nor estimated NSIS sizes bound output.
  if (value.trim() === '') { need(format === 'nsis', 'inner-size-unknown'); return null; }
  need(/^\d+$/u.test(value), 'size-invalid');
  const parsed = BigInt(value); need(parsed <= longMax, 'size-invalid'); return parsed;
}

/** Parse 7-Zip technical-list metadata, not NSIS/7z binary structures. */
export function parseArchiveListing(bytes, format) {
  need(format === 'nsis' || format === '7z', 'format-invalid');
  need(Buffer.isBuffer(bytes) && bytes.length > 0 && bytes.length <= archiveLimits.listingBytes, 'listing-limit');
  let text;
  try { text = new TextDecoder('utf-8', { fatal: true }).decode(bytes).replace(/^\uFEFF/u, ''); }
  catch { throw new Error('native-archive-listing-invalid'); }
  const entries = []; const aliases = new Set(); let total = 0n;
  for (const block of text.split(/(?:\r?\n)[ \t]*(?:\r?\n)+/u)) {
    if (block.trim() === '') continue;
    need(entries.length < archiveLimits.entries, 'entry-limit');
    const fields = Object.create(null);
    for (const line of block.split(/\r?\n/u)) {
      if (line === '') continue;
      const match = /^([A-Za-z][A-Za-z0-9 ]*) = ([^\r\n]*)$/u.exec(line);
      need(match && !Object.hasOwn(fields, match[1]), 'record-invalid');
      fields[match[1]] = match[2];
      need(Object.keys(fields).length <= 64, 'record-invalid');
    }
    need(Object.hasOwn(fields, 'Path') && Object.hasOwn(fields, 'Size'), 'record-invalid');
    const path = listingPath(fields.Path);
    need(!aliases.has(path.toLowerCase()), 'path-alias'); aliases.add(path.toLowerCase());
    for (const name of Object.keys(fields)) {
      need(!/^(?:Symbolic Link|Hard Link|Reparse(?: Point)?|Alternate Stream)$/iu.test(name), 'link-or-special-entry');
    }
    for (const flag of ['Folder', 'Encrypted', 'Anti']) {
      need(fields[flag] === undefined || ['+', '-'].includes(fields[flag]), 'type-invalid');
    }
    need(fields.Encrypted !== '+' && fields.Anti !== '+', 'link-or-special-entry');
    const attributes = fields.Attributes ?? '';
    need(!/\bReparse\b/iu.test(attributes + ' ' + (fields.Characteristics ?? '')), 'link-or-special-entry');
    const unixType = /(?:^|\s)([dlpsbc-])[rwxstST-]{9}(?:\s|$)/u.exec(attributes)?.[1];
    need(unixType === undefined || unixType === 'd' || unixType === '-', 'link-or-special-entry');
    const attributeDirectory = /^D/iu.test(attributes) || unixType === 'd';
    need(!(fields.Folder === '-' && attributeDirectory), 'type-invalid');
    const directory = fields.Folder === '+' || attributeDirectory;
    const size = sizeValue(fields.Size, format);
    if (format === '7z') {
      need(size !== null && size <= BigInt(archiveLimits.innerBytes), 'inner-size-limit');
      need(!directory || size === 0n, 'type-invalid');
      need(total <= BigInt(archiveLimits.innerBytes) - size, 'inner-size-limit'); total += size;
    }
    entries.push({ path, directory, size });
  }
  need(entries.length > 0, 'empty-listing');
  const files = new Set(entries.filter(e => !e.directory).map(e => e.path.toLowerCase()));
  for (const entry of entries) {
    const parents = entry.path.toLowerCase().split('/'); parents.pop();
    while (parents.length > 0) { need(!files.has(parents.join('/')), 'path-alias'); parents.pop(); }
  }
  return { entries, declaredTotalBytes: format === '7z' ? Number(total) : null };
}

export function selectNsisPayload(listing) {
  const matches = listing.entries.filter(e => /^app-.*\.7z$/iu.test(e.path.split('/').at(-1)));
  need(matches.length === 1 && !matches[0].directory && matches[0].path.split('/').at(-1) === 'app-64.7z', 'payload-selection-invalid');
  return matches[0];
}
export function archiveArguments(operation, archive, outputOrMember) {
  need(typeof archive === 'string' && isAbsolute(archive), 'arguments-invalid');
  if (operation === 'list-nsis') return ['l', '-tNsis', '-slt', '-ba', '-bd', '-bsp0', '-sccUTF-8', '--', archive];
  if (operation === 'list-7z') return ['l', '-t7z', '-slt', '-ba', '-bd', '-bsp0', '-sccUTF-8', '--', archive];
  if (operation === 'stream-nsis') {
    const member = listingPath(outputOrMember);
    need(member.split('/').at(-1) === 'app-64.7z', 'payload-selection-invalid');
    // -spd disables wildcard interpretation; -- ends switch parsing. No archive
    // path is ever used as an output path: stdout goes to one fixed owned file.
    return ['x', '-tNsis', '-so', '-spd', '-bd', '-bso0', '-bsp0', '-bse2', '--', archive, member];
  }
  need(operation === 'extract-7z' && typeof outputOrMember === 'string' && isAbsolute(outputOrMember), 'arguments-invalid');
  return ['x', '-t7z', '-y', '-bd', '-bso0', '-bsp0', '-bse2', `-o${outputOrMember}`, '--', archive];
}
export function require7zMagic(path) {
  physical(path, 'file'); const buffer = Buffer.alloc(6); const fd = openSync(path, 'r');
  try { need(readSync(fd, buffer, 0, buffer.length, 0) === 6 && buffer.equals(Buffer.from([0x37, 0x7a, 0xbc, 0xaf, 0x27, 0x1c])), 'inner-format-invalid'); }
  finally { closeSync(fd); }
}
function assertExtractedTree(root, listing) {
  const expected = new Map(listing.entries.filter(e => !e.directory).map(e => [e.path, e.size]));
  const actual = new Set(); let count = 0;
  const visit = (directory, depth) => {
    need(depth <= archiveLimits.depth, 'path-depth-limit');
    for (const entry of readdirSync(directory, { withFileTypes: true })) {
      need(++count <= archiveLimits.entries, 'entry-limit');
      const path = join(directory, entry.name); const name = listingPath(relative(root, path).split(sep).join('/'));
      need(!entry.isSymbolicLink(), 'extracted-reparse');
      if (entry.isDirectory()) { physical(path, 'directory'); visit(path, depth + 1); }
      else {
        physical(path, 'file');
        need(expected.has(name) && BigInt(lstatSync(path).size) === expected.get(name), 'extracted-inventory-mismatch');
        actual.add(name);
      }
    }
  };
  visit(root, 0); need(actual.size === expected.size, 'extracted-inventory-mismatch');
}

export async function extractNativeAsarInstaller({ sevenZip, installer, expectedSha256, expectedBytes, workRoot }) {
  need(process.platform === 'win32' && process.env.GITHUB_ACTIONS === 'true', 'ci-only');
  need(typeof process.env.RUNNER_TEMP === 'string' && isAbsolute(process.env.RUNNER_TEMP) &&
    typeof process.env.ProgramFiles === 'string' && isAbsolute(process.env.ProgramFiles), 'private-root-invalid');
  const temp = physical(resolve(process.env.RUNNER_TEMP), 'directory');
  need(dirname(temp) !== temp, 'private-root-invalid');
  physical(workRoot, 'directory'); probeEnvironment(workRoot);
  need(inside(temp, workRoot) && resolve(workRoot) !== temp && inside(workRoot, installer), 'private-root-invalid');
  const expectedTool = resolve(process.env.ProgramFiles ?? '', '7-Zip', '7z.exe');
  need(resolve(sevenZip).toLowerCase() === expectedTool.toLowerCase(), 'tool-invalid'); physical(sevenZip, 'file');
  need(hashValid(expectedSha256) && Number.isSafeInteger(expectedBytes) && expectedBytes > 0 && expectedBytes <= archiveLimits.payloadBytes, 'installer-identity-invalid');
  physical(installer, 'file');
  need(lstatSync(installer).size === expectedBytes && hashFile(installer) === expectedSha256, 'installer-identity-mismatch');
  const nsisRoot = join(workRoot, 'nsis'); const outputRoot = join(workRoot, 'application');
  need(lstatSync(nsisRoot, { throwIfNoEntry: false }) === undefined && lstatSync(outputRoot, { throwIfNoEntry: false }) === undefined, 'output-exists');
  const env = probeEnvironment(workRoot); delete env.ELECTRON_RUN_AS_NODE;
  const run = (args, extra = {}) => runArchiveProcess(sevenZip, args, { cwd: workRoot, env,
    maxStdoutBytes: archiveLimits.listingBytes, timeoutMs: archiveLimits.timeoutMs, ...extra });
  const outer = await atStage('nsis-listing', async () => parseArchiveListing((await run(archiveArguments('list-nsis', installer))).stdout, 'nsis'));
  const selected = await atStage('nsis-listing', () => selectNsisPayload(outer));
  need(hashFile(installer) === expectedSha256, 'installer-changed');
  mkdirSync(nsisRoot, { mode: 0o700 });
  const payload = join(nsisRoot, 'app-64.7z');
  const streamed = await atStage('nsis-selected-stream', () => run(archiveArguments('stream-nsis', installer, selected.path), {
    outputFile: payload, maxStdoutBytes: archiveLimits.payloadBytes }));
  await atStage('nsis-selected-stream', () => {
    need(hashFile(installer) === expectedSha256 && streamed.bytes > 0 && hashFile(payload) === streamed.sha256, 'stream-identity-mismatch');
    require7zMagic(payload);
  });
  const innerHash = streamed.sha256;
  const inner = await atStage('7z-listing', async () => parseArchiveListing((await run(archiveArguments('list-7z', payload))).stdout, '7z'));
  need(hashFile(payload) === innerHash, 'inner-changed');
  mkdirSync(outputRoot, { mode: 0o700 });
  // The pinned 7z decoder's regular-file writer clamps bytes to the SAME item.Size
  // exposed by its listing. Exhaustive known-size validation and this one unchanged
  // archive bound regular payload bytes; no NSIS estimate is used as that bound.
  await atStage('7z-extraction', () => run(archiveArguments('extract-7z', payload, outputRoot), { maxStdoutBytes: 1024 * 1024 }));
  await atStage('extracted-inventory', () => {
    need(hashFile(payload) === innerHash, 'inner-changed'); assertExtractedTree(outputRoot, inner);
  });
  return { schemaVersion: 1, valid: true, extraction: 'selected-nsis-payload-to-strict-7z',
    payloadBytes: streamed.bytes, payloadSha256: innerHash, nsisEntryCount: outer.entries.length,
    nsisSelectedSizeKnown: selected.size !== null, innerEntryCount: inner.entries.length,
    innerDeclaredBytes: inner.declaredTotalBytes, installerSha256: expectedSha256 };
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  try {
    const { values } = parseArgs({ options: { 'seven-zip': { type: 'string' }, installer: { type: 'string' },
      'installer-sha256': { type: 'string' }, 'installer-bytes': { type: 'string' }, 'work-root': { type: 'string' } }, allowPositionals: false });
    need(Object.values(values).every(v => typeof v === 'string') && Object.keys(values).length === 5, 'arguments-invalid');
    const result = await extractNativeAsarInstaller({ sevenZip: resolve(values['seven-zip']), installer: resolve(values.installer),
      expectedSha256: values['installer-sha256'], expectedBytes: Number(values['installer-bytes']), workRoot: resolve(values['work-root']) });
    process.stdout.write(JSON.stringify(result) + '\n');
  } catch (error) {
    process.stdout.write(JSON.stringify({ schemaVersion: 1, valid: false, stage: stages.includes(error.stage) ? error.stage : 'preflight', reason: safeReason(error) }) + '\n'); process.exitCode = 1;
  }
}
