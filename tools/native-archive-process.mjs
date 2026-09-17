// Bounded process transport for an already-selected, trusted archive tool.
// No executable discovery, installer execution, shell, ambient env copy or decoding.
// Caller owns a private ordinary directory and the fixed existing 7-Zip executable.
import { createHash } from 'node:crypto';
import { spawn as nativeSpawn } from 'node:child_process';
import { closeSync, constants, createWriteStream, fstatSync, lstatSync, openSync, unlinkSync } from 'node:fs';
import { basename, dirname, isAbsolute, resolve, win32 } from 'node:path';
import { Readable, Transform, Writable } from 'node:stream';
import { pipeline } from 'node:stream/promises';
import { inside, physical, relativeName } from './native-runtime-integrity.mjs';

const BLOCK = 64 * 1024;
const STDERR_LIMIT = 16n * 1024n;
const CAPTURE_LIMIT = 32n * 1024n * 1024n;
const FILE_LIMIT = 4n * 1024n ** 3n;
const closedChildren = new WeakSet();
const error = code => Object.assign(new Error(`native-archive-${code}`), { code: `native-archive-${code}` });
const need = (ok, code) => { if (!ok) throw error(code); };
const sameFile = (a, b) => a && b && a.dev === b.dev && a.ino === b.ino;
const exited = child => typeof child.exitCode === 'number' || typeof child.signalCode === 'string';

function waitWithin(promise, milliseconds) {
  return new Promise(resolveWait => {
    const timer = setTimeout(() => resolveWait({ settled: false }), milliseconds);
    Promise.resolve(promise).then(value => { clearTimeout(timer); resolveWait({ settled: true, value }); },
      () => { clearTimeout(timer); resolveWait({ settled: true, rejected: true }); });
  });
}
function closeOf(child) {
  return new Promise(resolveClose => {
    child.once('close', (code, signal) => { closedChildren.add(child); resolveClose({ code, signal }); });
  });
}

/** Stop ONLY the just-created child/tree and prove close before claiming cleanup.
 * The optional third argument is a narrow test seam, not a CLI or routing fallback.
 * A deadline is not a claim that a refused OS termination succeeded. */
export async function terminateArchiveChild(child, closePromise, {
  spawn = nativeSpawn, platform = process.platform, systemRoot = process.env.SystemRoot,
  timeoutMs = 5000,
} = {}) {
  need(child && Number.isSafeInteger(timeoutMs) && timeoutMs > 0 && timeoutMs <= 5000, 'termination-failed');
  if (closedChildren.has(child)) return;
  // A resolved externally supplied close promise is also usable in unit tests.
  const alreadyClosed = await waitWithin(closePromise, 0);
  if (alreadyClosed.settled && !alreadyClosed.rejected) return;
  if (exited(child)) {
    const closed = await waitWithin(closePromise, timeoutMs);
    need(closed.settled && !closed.rejected, 'termination-failed');
    return;
  }
  need(Number.isSafeInteger(child.pid) && child.pid > 0, 'termination-failed');
  if (platform !== 'win32') {
    let sent = false;
    try { sent = child.kill('SIGKILL'); } catch { /* fixed failure below */ }
    const closed = await waitWithin(closePromise, timeoutMs);
    need(sent === true && closed.settled && !closed.rejected, 'termination-failed');
    return;
  }
  need(typeof systemRoot === 'string' && /^[A-Za-z]:[\\/]/u.test(systemRoot) &&
    !systemRoot.slice(2).includes(':'), 'termination-failed');
  const taskkill = win32.join(systemRoot, 'System32', 'taskkill.exe');
  let killer;
  try {
    killer = spawn(taskkill, ['/PID', String(child.pid), '/T', '/F'], { shell: false, windowsHide: true,
      stdio: 'ignore', env: { SystemRoot: systemRoot, WINDIR: systemRoot } });
  } catch { throw error('termination-failed'); }
  let killerError = false;
  killer.on('error', () => { killerError = true; });
  const killerClose = closeOf(killer);
  const [killResult, childResult] = await Promise.all([
    waitWithin(killerClose, timeoutMs), waitWithin(closePromise, timeoutMs),
  ]);
  if (!killResult.settled) {
    // Bound and confirm cleanup of our taskkill helper too. Failure still means
    // termination-failed, even if the original process happened to close.
    let sent = closedChildren.has(killer) || exited(killer);
    if (!sent) { try { sent = killer.kill('SIGKILL') === true; } catch { sent = false; } }
    const helperClosed = await waitWithin(killerClose, timeoutMs);
    if (!helperClosed.settled || helperClosed.rejected) {
      // The OS may refuse termination. Do not let an unconfirmed owned handle
      // hide the bounded failure by keeping the reporting Node process alive.
      try { killer.unref?.(); } catch { /* still a fixed termination failure */ }
    }
    need(sent && helperClosed.settled && !helperClosed.rejected, 'termination-failed');
  }
  need(killResult.settled && !killResult.rejected && !killerError && killResult.value?.code === 0 &&
    !killResult.value?.signal && childResult.settled && !childResult.rejected, 'termination-failed');
}

function checkedEnv(value) {
  need(value !== null && typeof value === 'object' && !Array.isArray(value), 'input-invalid');
  const env = Object.create(null);
  for (const [name, text] of Object.entries(value)) {
    need(name.length > 0 && !/[=\0]/u.test(name) && typeof text === 'string' && !text.includes('\0'), 'input-invalid');
    env[name] = text;
  }
  return env;
}
function quota(value, fallback) {
  const limit = value === undefined ? fallback : typeof value === 'bigint' ? value :
    Number.isSafeInteger(value) ? BigInt(value) : -1n;
  need(limit >= 0n && limit <= BigInt(Number.MAX_SAFE_INTEGER), 'input-invalid');
  return limit;
}
function ownedOutput(path, cwd) {
  need(typeof path === 'string' && isAbsolute(path) && resolve(path) === path && inside(cwd, path) && path !== cwd, 'output-path-invalid');
  relativeName(basename(path));
  const parent = dirname(path);
  physical(parent, 'directory'); const parentIdentity = lstatSync(parent, { bigint: true });
  need(lstatSync(path, { throwIfNoEntry: false }) === undefined, 'output-exists');
  let fd;
  try { fd = openSync(path, constants.O_WRONLY | constants.O_CREAT | constants.O_EXCL | (constants.O_NOFOLLOW ?? 0), 0o600); }
  catch (cause) { throw error(cause.code === 'EEXIST' ? 'output-exists' : 'output-failed'); }
  const identity = fstatSync(fd, { bigint: true });
  // Exclusive creation plus inode checks protect ownership; the caller's private,
  // serialized directory remains a prerequisite, not an OS anti-TOCTOU claim.
  const owned = { path, parent, parentIdentity, identity, fd };
  try {
    physical(path, 'file');
    need(identity.isFile() && identity.nlink === 1n && sameFile(identity, lstatSync(path, { bigint: true })) &&
      sameFile(parentIdentity, lstatSync(parent, { bigint: true })), 'output-path-invalid');
  } catch {
    closeSync(fd); owned.fd = undefined;
    removeOwned(owned); throw error('output-path-invalid');
  }
  return owned;
}
function removeOwned(owned) {
  physical(owned.parent, 'directory');
  need(sameFile(owned.parentIdentity, lstatSync(owned.parent, { bigint: true })), 'cleanup-failed');
  const current = lstatSync(owned.path, { bigint: true, throwIfNoEntry: false });
  if (current === undefined) return;
  need(current.isFile() && !current.isSymbolicLink() && sameFile(owned.identity, current), 'cleanup-failed');
  unlinkSync(owned.path);
}

/** Run a fixed existing tool. Capture is capped at32MiB; file output defaults4GiB.
 * Parent stream high-water marks are64KiB. This does NOT bound decoder RSS/CPU;
 * the deadline and disposable CI resource boundary remain necessary. */
export async function runArchiveProcess(executable, args, options = {}) {
  let cwd; let env; let limit; let owned;
  try {
    need(typeof executable === 'string' && isAbsolute(executable), 'input-invalid'); physical(executable, 'file');
    need(Array.isArray(args) && args.every(arg => typeof arg === 'string' && !arg.includes('\0')), 'input-invalid');
    cwd = physical(options.cwd, 'directory'); env = checkedEnv(options.env);
    limit = quota(options.maxStdoutBytes, options.outputFile === undefined ? CAPTURE_LIMIT : FILE_LIMIT);
    need(options.outputFile !== undefined || limit <= CAPTURE_LIMIT, 'capture-limit-invalid');
    need(options.timeoutMs === undefined || (Number.isSafeInteger(options.timeoutMs) && options.timeoutMs > 0 && options.timeoutMs <= 180000), 'input-invalid');
    if (options.outputFile !== undefined) owned = ownedOutput(options.outputFile, cwd);
  } catch (cause) {
    if (/^native-archive-[a-z-]+$/u.test(cause?.message)) throw cause;
    throw error('path-invalid');
  }

  // Coalesce capture into bounded pages instead of retaining one Buffer object
  // per tiny stdout fragment. At32MiB there are at most512 capture pages.
  const pages = []; let page; let pageBytes = 0;
  const hash = createHash('sha256'); let bytes = 0n;
  let child; let source; let guard; let sink; let closePromise; let outputPromise; let stderrPromise;
  let timer; let failure; let sinkClosed = Promise.resolve(); let sinkFailure;
  try {
    sink = owned ? createWriteStream(owned.path, { fd: owned.fd, autoClose: true, highWaterMark: BLOCK }) :
      new Writable({ highWaterMark: BLOCK, decodeStrings: false, write(chunk, encoding, done) {
        let offset = 0;
        while (offset < chunk.length) {
          page ??= Buffer.allocUnsafe(BLOCK);
          const length = Math.min(BLOCK - pageBytes, chunk.length - offset);
          chunk.copy(page, pageBytes, offset, offset + length); offset += length; pageBytes += length;
          if (pageBytes === BLOCK) { pages.push(page); page = undefined; pageBytes = 0; }
        }
        done();
      }, final(done) {
        if (pageBytes > 0) pages.push(page.subarray(0, pageBytes));
        page = undefined; pageBytes = 0; done();
      } });
    sinkFailure = new Promise((resolveUnused, reject) => sink.on('error', cause => {
      reject(/^native-archive-/u.test(cause?.message) ? cause : error('output-failed'));
    }));
    sinkFailure.catch(() => {}); // Observe even if spawn/setup throws before the race.
    if (owned) {
      owned.fd = undefined; // The stream exclusively owns/auto-closes this descriptor.
      sinkClosed = new Promise(resolveClose => sink.once('close', resolveClose));
    }
    child = nativeSpawn(executable, args.slice(), { cwd, env, shell: false, windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] });
    closePromise = closeOf(child);
    const processFailure = new Promise((resolveUnused, reject) => child.on('error', () => reject(error('process-failed'))));
    processFailure.catch(() => {});
    need(child.stdout && child.stderr, 'process-failed');
    source = Readable.from((async function* () {
      try {
        for await (const chunk of child.stdout) {
          need(Buffer.isBuffer(chunk), 'stdout-failed');
          for (let offset = 0; offset < chunk.length; offset += BLOCK) yield chunk.subarray(offset, offset + BLOCK);
        }
      } catch (cause) { throw /^native-archive-/u.test(cause?.message) ? cause : error('stdout-failed'); }
    })(), { objectMode: false, highWaterMark: BLOCK });
    guard = new Transform({ highWaterMark: BLOCK, decodeStrings: false, transform(chunk, encoding, done) {
      if (!Buffer.isBuffer(chunk)) return done(error('stdout-failed'));
      const next = bytes + BigInt(chunk.length);
      if (next > limit) return done(error('output-limit')); // BEFORE hash, push or sink write.
      bytes = next; hash.update(chunk); done(null, chunk);
    } });
    outputPromise = pipeline(source, guard, sink).catch(cause => {
      throw /^native-archive-/u.test(cause?.message) ? cause : error('output-failed');
    });
    stderrPromise = (async () => {
      let size = 0n;
      try {
        for await (const chunk of child.stderr) {
          need(Buffer.isBuffer(chunk), 'stderr-failed'); size += BigInt(chunk.length);
          need(size <= STDERR_LIMIT, 'stderr-limit'); // Drain/discard, never decode/store/print.
        }
      } catch (cause) { throw /^native-archive-/u.test(cause?.message) ? cause : error('stderr-failed'); }
    })();
    const finished = Promise.all([closePromise, outputPromise, stderrPromise, sinkClosed]).then(([closed]) => {
      need(closed.code === 0 && !closed.signal, 'process-failed');
    });
    const deadline = new Promise((resolveUnused, reject) => { timer = setTimeout(() => reject(error('timeout')), options.timeoutMs ?? 180000); });
    await Promise.race([finished, processFailure, sinkFailure, deadline]);
    if (owned) {
      physical(owned.path, 'file');
      const current = lstatSync(owned.path, { bigint: true });
      need(sameFile(owned.identity, current) && current.nlink === 1n && current.size === bytes &&
        sameFile(owned.parentIdentity, lstatSync(owned.parent, { bigint: true })), 'output-path-invalid');
    }
    return { stdout: owned ? undefined : Buffer.concat(pages, Number(bytes)), bytes: Number(bytes), sha256: hash.digest('hex') };
  } catch (cause) {
    failure = /^native-archive-[a-z-]+$/u.test(cause?.message) ? cause : error('process-failed');
    // Destroy only our pipes/sink; every promise has a rejection observer before
    // any termination wait, including cases where the OS refuses to stop a child.
    const settling = Promise.allSettled([outputPromise, stderrPromise, sinkClosed].filter(Boolean));
    source?.destroy(); guard?.destroy(); sink?.destroy(); child?.stdout?.destroy(); child?.stderr?.destroy();
    if (child && closePromise) {
      try { await terminateArchiveChild(child, closePromise, { systemRoot: env.SystemRoot ?? env.SYSTEMROOT ?? env.WINDIR }); }
      catch {
        failure = error('termination-failed');
        if (!closedChildren.has(child)) {
          try { child.unref?.(); } catch { /* failure remains explicit; never claim stopped */ }
        }
      }
    }
    const settled = await waitWithin(settling, 5000);
    if (!settled.settled && failure.message !== 'native-archive-termination-failed') failure = error('cleanup-failed');
    if (owned) {
      try {
        if (owned.fd !== undefined) { closeSync(owned.fd); owned.fd = undefined; }
        if (!settled.settled) throw error('cleanup-failed');
        removeOwned(owned);
      } catch { if (failure.message !== 'native-archive-termination-failed') failure = error('cleanup-failed'); }
    }
    throw failure;
  } finally { clearTimeout(timer); }
}
