// Inert technical-listing/argument/format tests. No 7-Zip, installer or runtime execution.
import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { test } from 'node:test';
import { archiveArguments, archiveLimits, extractNativeAsarInstaller, parseArchiveListing, require7zMagic, selectNsisPayload } from '../tools/native-asar-extract.mjs';
const record = (path, size, extra = '') => `Path = ${path}\nSize = ${size}\nPacked Size = 8\n${extra}\n`;
const listing = (...records) => Buffer.from(records.join('\n'));

test('NSIS regular-file unknown remains null, never zero or Packed Size', () => {
  const parsed = parseArchiveListing(listing(record('$PLUGINSDIR/regular.dll', ''), record('$PLUGINSDIR/app-64.7z', '')), 'nsis');
  assert.equal(parsed.entries[0].directory, false); assert.equal(parsed.entries[0].size, null);
  assert.equal(parsed.declaredTotalBytes, null); assert.equal(selectNsisPayload(parsed).size, null);
});
test('NSIS known solid estimates remain informational without an output bound', () => {
  const parsed = parseArchiveListing(listing(record('app-64.7z', '9223372036854775807')), 'nsis');
  assert.equal(selectNsisPayload(parsed).size, (1n << 63n) - 1n);
  assert.equal(parsed.declaredTotalBytes, null);
});
test('NSIS known zero and unknown are distinct', () => {
  const parsed = parseArchiveListing(listing(record('empty', '0'), record('app-64.7z', '')), 'nsis');
  assert.equal(parsed.entries[0].size, 0n); assert.equal(parsed.entries[1].size, null);
});
for (const size of ['', ' ', 'unknown', '-1', '1.5', '0x10', '18446744073709551616']) {
  test(`inner 7z rejects unavailable/invalid Size ${JSON.stringify(size)}`, () => {
    assert.throws(() => parseArchiveListing(listing(record('dsh/file', size)), '7z'), /native-archive-/);
  });
}
test('inner known-size sum accepts exact16GiB and rejects +1 without overflow', () => {
  const max = archiveLimits.innerBytes;
  assert.equal(parseArchiveListing(listing(record('one', String(max))), '7z').declaredTotalBytes, max);
  assert.throws(() => parseArchiveListing(listing(record('one', String(max)), record('two', '1')), '7z'), /inner-size-limit/);
});
for (const [name, bytes] of [
  ['missing Size', Buffer.from('Path = app-64.7z\nPacked Size = 8\n')],
  ['duplicate Size numeric+blank', Buffer.from('Path = app-64.7z\nSize = 4\nSize = \n')],
  ['duplicate Path', Buffer.from('Path = app-64.7z\nPath = other\nSize = \n')],
  ['duplicate Folder', Buffer.from('Path = app-64.7z\nSize = \nFolder = -\nFolder = +\n')],
  ['non-property control line', Buffer.from('Path = app-64.7z\nSize = \nnot a property\n')],
]) {
  test(`outer NSIS still rejects ${name}`, () => assert.throws(() => parseArchiveListing(bytes, 'nsis'), /record-invalid/));
}
for (const path of ['../escape', '/absolute', 'C:/absolute', 'file:stream', 'bad./file', 'bad /file', 'nul/file',
  'directory//file', 'directory/./file', 'directory/../file', 'bad*file', 'bad?file', 'bad\u0000file', 'bad\u007ffile']) {
  test(`all NSIS entries validate paths, including unselected ${JSON.stringify(path)}`, () => {
    assert.throws(() => parseArchiveListing(listing(record(path, ''), record('app-64.7z', '')), 'nsis'), /native-/);
  });
}
for (const extra of ['Symbolic Link = target\n', 'Hard Link = target\n', 'Reparse Point = yes\n',
  'Alternate Stream = data\n', 'Attributes = A lrwxrwxrwx\n', 'Attributes = A prw-r--r--\n',
  'Attributes = Reparse\n', 'Encrypted = +\n', 'Anti = +\n', 'Folder = false\n', 'Folder = -\nAttributes = D\n']) {
  test(`all entries reject unsafe type/flags ${extra.trim()}`, () => {
    assert.throws(() => parseArchiveListing(listing(record('unselected', '', extra), record('app-64.7z', '')), 'nsis'), /native-archive-/);
  });
}
test('case aliases and file-as-parent conflicts remain rejected', () => {
  assert.throws(() => parseArchiveListing(listing(record('Foo', ''), record('foo', ''), record('app-64.7z', '')), 'nsis'), /path-alias/);
  assert.throws(() => parseArchiveListing(listing(record('Foo', ''), record('Foo/child', ''), record('app-64.7z', '')), 'nsis'), /path-alias/);
});
test('inner directory records require known zero size', () => {
  assert.equal(parseArchiveListing(listing(record('dsh', '0', 'Folder = +\nAttributes = D\n')), '7z').declaredTotalBytes, 0);
  assert.throws(() => parseArchiveListing(listing(record('dsh', '', 'Folder = +\n')), '7z'), /inner-size-unknown/);
  assert.throws(() => parseArchiveListing(listing(record('dsh', '1', 'Folder = +\n')), '7z'), /type-invalid/);
});
for (const entries of [[], [record('app-32.7z', '')], [record('APP-64.7Z', '')],
  [record('one/app-64.7z', ''), record('two/app-64.7z', '')],
  [record('app-64.7z', ''), record('app-32.7z', '')], [record('app-64.7z', '', 'Folder = +\n')]]) {
  test(`exact payload selection rejects absent/alternate/duplicate/directory (${entries.length} entries)`, () => {
    const parsed = entries.length ? parseArchiveListing(listing(...entries), 'nsis') : { entries: [] };
    assert.throws(() => selectNsisPayload(parsed), /payload-selection-invalid/);
  });
}
test('format-pinned stream uses a literal validated member and no output archive paths', () => {
  const input = resolve('inert.exe'); const member = '-literal/$PLUGINSDIR/app-64.7z';
  const args = archiveArguments('stream-nsis', input, member);
  assert.deepEqual(args, ['x', '-tNsis', '-so', '-spd', '-bd', '-bso0', '-bsp0', '-bse2', '--', input, member]);
  assert.ok(!args.some(a => a.startsWith('-o')));
  assert.ok(archiveArguments('list-nsis', input).includes('-tNsis'));
  assert.ok(archiveArguments('list-7z', input).includes('-t7z'));
  const inner = archiveArguments('extract-7z', input, resolve('private-output'));
  assert.ok(inner.includes('-t7z')); assert.ok(!inner.includes('-tNsis'));
});
test('magic check distinguishes exact7z data from executable or malformed bytes', t => {
  const root = mkdtempSync(join(tmpdir(), 'native-archive-magic-')); t.after(() => rmSync(root, { recursive: true, force: true }));
  const file = join(root, 'payload.7z');
  writeFileSync(file, Buffer.from([0x37, 0x7a, 0xbc, 0xaf, 0x27, 0x1c, 0, 0])); assert.doesNotThrow(() => require7zMagic(file));
  for (const data of [Buffer.from('MZnot-7z'), Buffer.from([0x37, 0x7a]), Buffer.from('PKnot-7z')]) {
    writeFileSync(file, data); assert.throws(() => require7zMagic(file), /inner-format-invalid/);
  }
});
test('no accidental local extraction and no empty/malformed listing acceptance', async () => {
  const saved = process.env.GITHUB_ACTIONS; delete process.env.GITHUB_ACTIONS;
  try { await assert.rejects(extractNativeAsarInstaller({}), /ci-only/); }
  finally { if (saved !== undefined) process.env.GITHUB_ACTIONS = saved; }
  assert.throws(() => parseArchiveListing(Buffer.alloc(0), 'nsis'), /listing-limit/);
  assert.throws(() => parseArchiveListing(Buffer.from([0xff]), 'nsis'), /listing-invalid/);
});
test('workflow delegates extraction without executing installer or full outer unpack', () => {
  const workflow = readFileSync(new URL('../.github/workflows/native-asar-release.yml', import.meta.url), 'utf8');
  assert.ok(workflow.includes('native-asar-extract.mjs'));
  assert.ok(!workflow.includes('& $sevenZip x $installer'));
});
