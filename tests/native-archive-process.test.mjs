// Tiny owned Node children and fake processes only. No 7-Zip/installer execution.
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import childProcess from 'node:child_process';
import { EventEmitter, once } from 'node:events';
import fs from 'node:fs';
import { syncBuiltinESMExports } from 'node:module';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { PassThrough, Writable } from 'node:stream';
import { test } from 'node:test';
import { runArchiveProcess, terminateArchiveChild } from '../tools/native-archive-process.mjs';

const BLOCK = 64 * 1024;
const digest = bytes => createHash('sha256').update(bytes).digest('hex');
const env = () => Object.fromEntries(['SystemRoot', 'WINDIR'].filter(k => process.env[k]).map(k => [k, process.env[k]]));
function fixture(t) {
  const root = fs.mkdtempSync(join(tmpdir(), 'native-archive-runner-'));
  t.after(() => fs.rmSync(root, { recursive: true, force: true })); return root;
}
function fakeChild(pid = 12345) {
  const child = new EventEmitter();
  Object.assign(child, { pid, exitCode: null, signalCode: null,
    stdout: new PassThrough({ highWaterMark: BLOCK }), stderr: new PassThrough({ highWaterMark: BLOCK }) });
  child.finish = (code = 0, signal = null) => {
    child.stdout?.end(); child.stderr?.end(); child.exitCode = code; child.signalCode = signal;
    child.emit('close', code, signal);
  };
  child.kill = () => { queueMicrotask(() => child.finish(null, 'SIGKILL')); return true; };
  child.unrefs = 0; child.unref = () => { child.unrefs++; };
  return child;
}
function spawnFixture(t, action, inspect = () => {}) {
  let started;
  t.mock.method(childProcess, 'spawn', (executable, args, options) => {
    if (/taskkill\.exe$/iu.test(executable)) {
      assert.deepEqual(args, ['/PID', String(started.pid), '/T', '/F']);
      assert.equal(options.stdio, 'ignore'); assert.equal(options.shell, false);
      const killer = fakeChild(12346);
      setImmediate(() => { started.finish(null, 'SIGKILL'); killer.finish(0); });
      return killer;
    }
    inspect(executable, args, options); started = fakeChild(); setImmediate(() => action(started)); return started;
  });
  syncBuiltinESMExports(); t.after(() => { t.mock.restoreAll(); syncBuiltinESMExports(); });
  return () => started;
}

for (const output of [false, true]) {
  test(`real tiny Node raw binary stdout ${output ? 'file' : 'capture'} preserves null ff and BOM`, async t => {
    const root = fixture(t); const bytes = Buffer.from([0, 255, 239, 187, 191, 0, 13, 10, 128, 254]);
    const outputFile = output ? join(root, 'payload.7z') : undefined;
    const result = await runArchiveProcess(process.execPath, ['-e', `process.stdout.write(Buffer.from([${[...bytes]}]))`],
      { cwd: root, env: env(), maxStdoutBytes: bytes.length, outputFile });
    assert.equal(result.bytes, bytes.length); assert.equal(result.sha256, digest(bytes));
    if (output) { assert.equal(result.stdout, undefined); assert.deepEqual(fs.readFileSync(outputFile), bytes); }
    else assert.deepEqual(result.stdout, bytes);
  });
}

test('literal argument array and explicit environment are passed without shell or ambient values', async t => {
  const root = fixture(t); const args = ['x y', '--literal', '$(never-shell)', 'quote"', '百分比%#'];
  const passed = { SAFE: 'only-this' };
  spawnFixture(t, child => child.finish(), (executable, actual, options) => {
    assert.equal(executable, process.execPath); assert.deepEqual(actual, args); assert.notEqual(actual, args);
    assert.deepEqual({ ...options.env }, passed); assert.equal(options.shell, false); assert.equal(options.windowsHide, true);
    assert.deepEqual(options.stdio, ['ignore', 'pipe', 'pipe']); assert.equal(options.cwd, root);
  });
  const result = await runArchiveProcess(process.execPath, args, { cwd: root, env: passed, maxStdoutBytes: 0 });
  assert.equal(result.bytes, 0); assert.deepEqual(result.stdout, Buffer.alloc(0)); assert.equal(result.sha256, digest(Buffer.alloc(0)));
});

for (const [label, options] of [
  ['no explicit env', {}], ['unsafe budget', { env: {}, maxStdoutBytes: Number.MAX_SAFE_INTEGER + 1 }],
  ['negative budget', { env: {}, maxStdoutBytes: -1 }], ['capture too large', { env: {}, maxStdoutBytes: 4 * 1024 ** 3 }],
  ['deadline too large', { env: {}, timeoutMs: 180001 }], ['zero deadline', { env: {}, timeoutMs: 0 }],
  ['nonstring env', { env: { BAD: 1 } }], ['invalid env key', { env: { 'BAD=KEY': 'x' } }],
]) {
  test(`rejects ${label} before launch`, async t => {
    const root = fixture(t); let launched = false;
    spawnFixture(t, () => {}, () => { launched = true; });
    await assert.rejects(runArchiveProcess(process.execPath, [], { cwd: root, ...options }), /native-archive-/);
    assert.equal(launched, false);
  });
}

test('preexisting output and escaped output are never overwritten/deleted or launched', async t => {
  const root = fixture(t); const path = join(root, 'existing.7z'); fs.writeFileSync(path, 'preserve'); let launched = false;
  spawnFixture(t, () => {}, () => { launched = true; });
  await assert.rejects(runArchiveProcess(process.execPath, [], { cwd: root, env: {}, outputFile: path }), /native-archive-output-exists/);
  await assert.rejects(runArchiveProcess(process.execPath, [], { cwd: root, env: {}, outputFile: join(dirname(root), 'outside.7z') }), /native-archive-output-path-invalid/);
  assert.equal(fs.readFileSync(path, 'utf8'), 'preserve'); assert.equal(launched, false);
});

test('reparse output parents and existing dangling links fail before launch', async t => {
  const root = fixture(t); const target = join(root, 'target'); fs.mkdirSync(target);
  const link = join(root, 'link'); fs.symlinkSync(target, link, 'junction'); let launched = false;
  spawnFixture(t, () => {}, () => { launched = true; });
  await assert.rejects(runArchiveProcess(process.execPath, [], { cwd: root, env: {}, outputFile: join(link, 'new.7z') }), /native-archive-path-invalid/);
  assert.equal(fs.existsSync(join(target, 'new.7z')), false);
  fs.unlinkSync(link); fs.symlinkSync(join(root, 'absent'), link, 'junction');
  await assert.rejects(runArchiveProcess(process.execPath, [], { cwd: root, env: {}, outputFile: link }), /native-archive-output-exists/);
  assert.equal(launched, false);
});

for (const file of [false, true]) {
  for (const overflow of [false, true]) {
    test(`BigInt byte budget ${overflow ? 'rejects +1' : 'accepts exact'} in ${file ? 'file' : 'capture'} mode`, async t => {
      const root = fixture(t); const outputFile = file ? join(root, 'owned.7z') : undefined;
      const bytes = Buffer.alloc(BLOCK + (overflow ? 1 : 0), 255);
      spawnFixture(t, child => { child.stdout.end(bytes); child.stderr.end(); child.finish(); });
      const task = runArchiveProcess(process.execPath, [], { cwd: root, env: env(), maxStdoutBytes: BigInt(BLOCK), outputFile });
      if (overflow) { await assert.rejects(task, /native-archive-output-limit/); if (file) assert.equal(fs.existsSync(outputFile), false); }
      else { const result = await task; assert.equal(result.bytes, BLOCK); assert.equal(result.sha256, digest(bytes)); }
    });
  }
}

for (const [label, action, reason] of [
  ['nonzero', child => { child.stdout.write('partial'); child.finish(9); }, 'process-failed'],
  ['stdout error', child => { child.stdout.destroy(new Error('private-stdout-error')); child.stderr.end(); child.finish(); }, 'stdout-failed'],
  ['stderr error', child => { child.stderr.destroy(new Error('private-stderr-error')); child.stdout.end(); child.finish(); }, 'stderr-failed'],
  ['stderr over bound', child => { child.stderr.end(Buffer.alloc(16385, 255)); child.stdout.end(); child.finish(); }, 'stderr-limit'],
  ['process error', child => { child.emit('error', new Error('private-spawn-error')); child.finish(-1); }, 'process-failed'],
]) {
  test(`rejects ${label} and removes only its own partial file`, async t => {
    const root = fixture(t); const outputFile = join(root, 'owned.7z'); const keep = join(root, 'keep.txt'); fs.writeFileSync(keep, 'unchanged');
    spawnFixture(t, action);
    await assert.rejects(runArchiveProcess(process.execPath, [], { cwd: root, env: env(), outputFile }),
      { message: `native-archive-${reason}` });
    assert.equal(fs.existsSync(outputFile), false); assert.equal(fs.readFileSync(keep, 'utf8'), 'unchanged');
  });
}

test('stderr at bound is drained/discarded without UTF conversion or inclusion', async t => {
  const root = fixture(t);
  spawnFixture(t, child => { child.stderr.end(Buffer.alloc(16384, 255)); child.stdout.end(Buffer.from([0, 255])); child.finish(); });
  const result = await runArchiveProcess(process.execPath, [], { cwd: root, env: env(), maxStdoutBytes: 2 });
  assert.deepEqual(result.stdout, Buffer.from([0, 255])); assert.deepEqual(Object.keys(result).sort(), ['bytes', 'sha256', 'stdout']);
});

test('deadline stops only the owned fake process/tree and removes owned partial output', async t => {
  const root = fixture(t); const outputFile = join(root, 'timeout.7z');
  const child = spawnFixture(t, running => running.stdout.write('partial'));
  await assert.rejects(runArchiveProcess(process.execPath, [], { cwd: root, env: env(), outputFile, timeoutMs: 30 }), /native-archive-timeout/);
  assert.equal(child().exitCode, null); assert.equal(child().signalCode, 'SIGKILL'); assert.equal(fs.existsSync(outputFile), false);
});

test('backpressure keeps sink writes serialized in 64KiB blocks and waits for sink finish', async t => {
  const root = fixture(t); const outputFile = join(root, 'slow.7z'); let pending = 0; let maximum = 0; let writes = 0; let finished = false;
  const realWriteSync = fs.writeSync;
  t.mock.method(fs, 'createWriteStream', (path, options) => {
    assert.equal(options.highWaterMark, BLOCK); assert.equal(options.autoClose, true);
    return new Writable({ highWaterMark: BLOCK,
      write(chunk, encoding, done) { assert.ok(chunk.length <= BLOCK); pending++; maximum = Math.max(maximum, pending); writes++;
        realWriteSync(options.fd, chunk); setTimeout(() => { pending--; done(); }, 2); },
      final(done) { setTimeout(() => { finished = true; done(); }, 5); },
      destroy(cause, done) { fs.closeSync(options.fd); done(cause); } });
  });
  spawnFixture(t, async child => {
    for (let n = 0; n < 12; n++) if (!child.stdout.write(Buffer.alloc(BLOCK, n))) await once(child.stdout, 'drain');
    child.finish();
  });
  syncBuiltinESMExports();
  const result = await runArchiveProcess(process.execPath, [], { cwd: root, env: env(), maxStdoutBytes: 12 * BLOCK, outputFile });
  assert.equal(maximum, 1); assert.equal(writes, 12); assert.equal(finished, true); assert.equal(result.bytes, 12 * BLOCK);
  assert.equal(fs.statSync(outputFile).size, result.bytes);
});

test('budget rejects a block BEFORE any over-budget sink write', async t => {
  const root = fixture(t); const outputFile = join(root, 'bound.7z'); let written = 0;
  t.mock.method(fs, 'createWriteStream', (path, options) => new Writable({ highWaterMark: BLOCK,
    write(chunk, encoding, done) { written += chunk.length; assert.ok(written <= BLOCK); fs.writeSync(options.fd, chunk); done(); },
    destroy(cause, done) { fs.closeSync(options.fd); done(cause); } }));
  spawnFixture(t, child => { child.stdout.end(Buffer.alloc(BLOCK + 1)); child.finish(); }); syncBuiltinESMExports();
  await assert.rejects(runArchiveProcess(process.execPath, [], { cwd: root, env: env(), maxStdoutBytes: BLOCK, outputFile }), /native-archive-output-limit/);
  assert.equal(written, BLOCK); assert.equal(fs.existsSync(outputFile), false);
});

test('sink errors are fixed and owned partial output is removed', async t => {
  const root = fixture(t); const outputFile = join(root, 'sink-error.7z');
  t.mock.method(fs, 'createWriteStream', (path, options) => new Writable({
    write(chunk, encoding, done) { done(new Error('private-sink-error')); },
    destroy(cause, done) { fs.closeSync(options.fd); done(cause); } }));
  spawnFixture(t, child => { child.stdout.end(Buffer.alloc(10)); child.finish(); }); syncBuiltinESMExports();
  await assert.rejects(runArchiveProcess(process.execPath, [], { cwd: root, env: env(), outputFile }), { message: 'native-archive-output-failed' });
  assert.equal(fs.existsSync(outputFile), false);
});

test('spawn exception closes and removes only the newly created output', async t => {
  const root = fixture(t); const outputFile = join(root, 'spawn-error.7z');
  t.mock.method(childProcess, 'spawn', () => { throw new Error('private-spawn-exception'); });
  syncBuiltinESMExports(); t.after(() => { t.mock.restoreAll(); syncBuiltinESMExports(); });
  await assert.rejects(runArchiveProcess(process.execPath, [], { cwd: root, env: env(), outputFile }), { message: 'native-archive-process-failed' });
  assert.equal(fs.existsSync(outputFile), false);
});

test('inode replacement is preserved and reported as cleanup failure, never unlinked as ours', async t => {
  const root = fixture(t); const outputFile = join(root, 'owned.7z'); const moved = join(root, 'moved-owned.7z');
  spawnFixture(t, child => {
    fs.renameSync(outputFile, moved); fs.writeFileSync(outputFile, 'foreign-replacement'); child.finish(9);
  });
  await assert.rejects(runArchiveProcess(process.execPath, [], { cwd: root, env: env(), outputFile }), { message: 'native-archive-cleanup-failed' });
  assert.equal(fs.readFileSync(outputFile, 'utf8'), 'foreign-replacement'); assert.equal(fs.existsSync(moved), true);
});

test('confirmed successful child close needs no unref escape', async t => {
  const root = fixture(t); const getChild = spawnFixture(t, child => child.finish(0));
  await runArchiveProcess(process.execPath, [], { cwd: root, env: env() });
  assert.equal(getChild().unrefs, 0);
});

test('run-level refused termination reports failure without pretending the fake child stopped', async t => {
  const root = fixture(t); const outputFile = join(root, 'refused.7z'); let child;
  t.mock.method(childProcess, 'spawn', (executable, args) => {
    if (/taskkill\.exe$/iu.test(executable)) {
      assert.deepEqual(args, ['/PID', String(child.pid), '/T', '/F']);
      const killer = fakeChild(12346); setImmediate(() => killer.finish(1)); return killer;
    }
    child = fakeChild(); child.kill = () => false; setImmediate(() => child.stdout.write('partial')); return child;
  });
  syncBuiltinESMExports(); t.after(() => { t.mock.restoreAll(); syncBuiltinESMExports(); });
  await assert.rejects(runArchiveProcess(process.execPath, [], { cwd: root, env: env(), outputFile, timeoutMs: 20 }),
    { message: 'native-archive-termination-failed' });
  assert.equal(child.exitCode, null); assert.equal(child.signalCode, null); assert.equal(fs.existsSync(outputFile), false);
  assert.equal(child.unrefs, 1, 'unconfirmed owned handle must not keep bounded failure reporter alive');
});

for (const [label, killerCode, closeOriginal] of [['success', 0, true], ['failed taskkill', 1, true], ['unclosed original', 0, false]]) {
  test(`checked Windows owned-tree termination: ${label}`, async () => {
    const child = fakeChild(); let resolveOriginal; const closed = new Promise(r => { resolveOriginal = r; }); let calls = 0;
    const terminate = terminateArchiveChild(child, closed, { platform: 'win32', systemRoot: 'C:\\Windows', timeoutMs: 20,
      spawn(executable, args, options) {
        calls++; assert.equal(executable, 'C:\\Windows\\System32\\taskkill.exe');
        assert.deepEqual(args, ['/PID', '12345', '/T', '/F']); assert.equal(options.shell, false); assert.equal(options.stdio, 'ignore');
        assert.deepEqual(options.env, { SystemRoot: 'C:\\Windows', WINDIR: 'C:\\Windows' });
        const killer = fakeChild(); setImmediate(() => { killer.finish(killerCode); if (closeOriginal) resolveOriginal({ code: null, signal: 'SIGKILL' }); }); return killer;
      } });
    if (label === 'success') await terminate;
    else await assert.rejects(terminate, { message: 'native-archive-termination-failed' });
    assert.equal(calls, 1);
  });
}

for (const mode of ['kill-false', 'close-missing', 'close-confirmed']) {
  test(`hung taskkill helper cleanup is checked and bounded: ${mode}`, async () => {
    const child = fakeChild(); let killerStops = 0; let helperClosed = false;
    const killer = fakeChild(6789); killer.kill = () => {
      killerStops++;
      if (mode === 'close-confirmed') setImmediate(() => { helperClosed = true; killer.finish(null, 'SIGKILL'); });
      return mode !== 'kill-false';
    };
    await assert.rejects(terminateArchiveChild(child, new Promise(() => {}), { platform: 'win32', systemRoot: 'C:\\Windows', timeoutMs: 20,
      spawn() { return killer; } }), { message: 'native-archive-termination-failed' });
    assert.equal(killerStops, 1); assert.equal(child.exitCode, null); assert.equal(helperClosed, mode === 'close-confirmed');
    assert.equal(killer.unrefs, mode === 'close-confirmed' ? 0 : 1);
  });
}

test('already-closed child is not killed; missing PID and taskkill startup errors fail closed', async () => {
  const child = fakeChild(); let calls = 0;
  await terminateArchiveChild(child, Promise.resolve({ code: 1 }), { platform: 'win32', spawn() { calls++; } });
  assert.equal(calls, 0);
  await assert.rejects(terminateArchiveChild({ pid: undefined }, new Promise(() => {}), { platform: 'win32', timeoutMs: 10 }), /native-archive-termination-failed/);
  await assert.rejects(terminateArchiveChild(child, new Promise(() => {}), { platform: 'win32', systemRoot: 'C:\\Windows', timeoutMs: 10,
    spawn() { throw new Error('private-taskkill-start-error'); } }), { message: 'native-archive-termination-failed' });
});
