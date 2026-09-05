#!/usr/bin/env node
/** Official GitHub HTTPS operations. Node >=22. No global config writes. */
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import crypto from 'node:crypto';
import { spawn } from 'node:child_process';
import { pathToFileURL } from 'node:url';

export class NetworkError extends Error {
  constructor(category, message, status) { super(message); this.category = category; this.status = status; }
}
export function classify(text, status) {
  if (status === 401 || status === 403) return 'auth-or-permission';
  if (status === 429 || /rate limit/i.test(text)) return 'rate-limit';
  if (status === 404 || /repository not found/i.test(text)) return 'not-found';
  if (/non-fast-forward|fetch first|rejected|protected branch|GH006|GH013/i.test(text)) return 'rejected';
  if (/certificate|CERT_|host key verification/i.test(text)) return 'tls-trust';
  if (/authentication failed|invalid credentials|permission denied|could not read Username|access denied/i.test(text)) return 'auth-or-permission';
  if (status >= 500 || /ECONNRESET|ECONNREFUSED|ENOTFOUND|EAI_AGAIN|ETIMEDOUT|UND_ERR_CONNECT_TIMEOUT|UND_ERR_SOCKET|UND_ERR_HEADERS_TIMEOUT|UND_ERR_BODY_TIMEOUT|TimeoutError|timed? ?out|could not resolve|could not connect|failed to connect|connection.*reset|recv failure|TLS.*handshake|SSL.*handshake|unexpected disconnect|remote end hung up|early EOF/i.test(text)) return 'network';
  return 'other';
}
export function tokenFromFile(file) {
  if (!file) throw new NetworkError('configuration', 'Pass --token-file pointing to the user-designated .env.');
  let text;
  try { text = fs.readFileSync(file, 'utf8'); } catch { throw new NetworkError('configuration', 'Designated token file is unavailable.'); }
  const rows = text.replace(/^\uFEFF/, '').split(/\r?\n/).filter(l => /^\s*(?:export\s+)?GH_TOKEN\s*=/.test(l));
  if (rows.length !== 1) throw new NetworkError('configuration', 'Token file must contain exactly one GH_TOKEN assignment.');
  let token = rows[0].replace(/^\s*(?:export\s+)?GH_TOKEN\s*=\s*/, '').trim();
  if ((token.startsWith('"') && token.endsWith('"')) || (token.startsWith("'") && token.endsWith("'"))) token = token.slice(1, -1);
  if (!token || /[\s\x00-\x1f\x7f]/.test(token)) throw new NetworkError('configuration', 'GH_TOKEN is empty or malformed.');
  return token;
}
export function githubRepo(url) {
  const m = /^https:\/\/github\.com\/([A-Za-z0-9_.-]+)\/([A-Za-z0-9_.-]+?)(?:\.git)?\/?$/.exec(url);
  if (!m || ['.', '..'].includes(m[1]) || ['.', '..'].includes(m[2])) throw new NetworkError('configuration', 'Remote must be a credential-free official https://github.com/OWNER/REPO URL.');
  return `https://github.com/${m[1]}/${m[2]}.git`;
}
export function childEnv(token) {
  const env = { ...process.env };
  // Do not inherit tracing, command-scope config, credential injection, or disabled TLS checks.
  for (const k of Object.keys(env)) if (/^(GIT_TRACE|GIT_CONFIG_|GIT_CURL_VERBOSE|GIT_SSL_NO_VERIFY|GIT_ASKPASS|SSH_ASKPASS|NODE_DEBUG|GH_TOKEN|GITHUB_TOKEN)/i.test(k)) delete env[k];
  const config = [['credential.helper', ''], ['core.askPass', ''], ['http.sslVerify', 'true'], ['http.followRedirects', 'false'], ['http.extraHeader', ''], ['http.https://github.com/.extraHeader', ''], ['http.lowSpeedLimit', '1'], ['http.lowSpeedTime', '20']];
  if (token) config.push(['http.https://github.com/.extraHeader', 'Authorization: Basic ' + Buffer.from(`x-access-token:${token}`).toString('base64')]);
  env.GIT_CONFIG_COUNT = String(config.length);
  config.forEach(([k,v],i) => { env[`GIT_CONFIG_KEY_${i}`] = k; env[`GIT_CONFIG_VALUE_${i}`] = v; });
  env.GIT_TERMINAL_PROMPT = '0';
  return env;
}
export function run(command, args, options = {}) {
  return new Promise(resolve => {
    let text = '', done = false, timedOut = false;
    const child = spawn(command, args, { cwd: options.cwd, env: options.env, windowsHide: true, shell: false, stdio: ['ignore', 'pipe', 'pipe'] });
    const finish = code => { if (done) return; done = true; clearTimeout(timer); resolve({ code, text, timedOut }); };
    const timer = setTimeout(() => {
      timedOut = true;
      if (process.platform === 'win32' && child.pid) {
        const killer = spawn('taskkill.exe', ['/PID', String(child.pid), '/T', '/F'], { windowsHide: true, stdio: 'ignore' });
        killer.on('error', () => child.kill());
      } else child.kill();
    }, options.timeout ?? 60000);
    const append = chunk => { text = (text + chunk.toString()).slice(-1024 * 1024); };
    child.stdout.on('data', append); child.stderr.on('data', append);
    child.on('error', () => finish(127)); child.on('close', code => finish(code ?? 1));
  });
}
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
export async function retry(task, { attempts = 3, vpn, onNetwork = async () => {}, wait = sleep } = {}) {
  let triedVpn = false;
  for (let i = 0; i < attempts; i++) {
    try { return await task(); } catch (e) {
      if (e.category !== 'network' || i === attempts - 1) throw e;
      if (vpn && !triedVpn) { triedVpn = true; await onNetwork(vpn); }
      await wait(1000 * 2 ** i);
    }
  }
}
async function vpnConnect(name) {
  if (name !== 'MSFTVPN') throw new NetworkError('configuration', 'Only the explicitly documented MSFTVPN fallback is supported.');
  const r = await run('rasdial.exe', [name], { timeout: 30000, env: childEnv() });
  console.error(JSON.stringify({ event: 'vpn-attempt', connectedCommandSucceeded: r.code === 0, note: 'The original operation must still pass. No disconnect is performed.' }));
}
export function requireTlsVerification() {
  if (process.env.NODE_TLS_REJECT_UNAUTHORIZED === '0') throw new NetworkError('tls-trust', 'NODE_TLS_REJECT_UNAUTHORIZED=0 is unsafe; refusing all HTTPS operations.');
}
export async function request(url, { token, fetchImpl = fetch, method = 'GET' } = {}) {
  requireTlsVerification();
  const u = new URL(url);
  if (token && u.origin !== 'https://api.github.com') throw new NetworkError('configuration', 'API credentials are restricted to api.github.com.');
  try {
    const r = await fetchImpl(u, { method, redirect: 'manual', signal: AbortSignal.timeout(20000), headers: { Accept: 'application/vnd.github+json', 'User-Agent': 'dsh-windows-ops-network', ...(token ? { Authorization: `Bearer ${token}` } : {}) } });
    if (r.status >= 300 && r.status < 400) throw new NetworkError('redirect', 'API redirect refused; verify the canonical repository URL.', r.status);
    if (!r.ok) throw new NetworkError(classify('', r.status), `GitHub HTTP ${r.status}`, r.status);
    return r;
  } catch (e) {
    if (e instanceof NetworkError) throw e;
    throw new NetworkError(classify(`${e.name} ${e.cause?.code ?? ''} ${e.message}`), 'HTTPS transport failed (credentials and raw response suppressed).');
  }
}
export async function verifyIdentity(token, expected, options) {
  const r = await request('https://api.github.com/user', { token, ...options });
  let j;
  try { j = await r.json(); } catch (e) {
    throw new NetworkError(classify(`${e.name} ${e.cause?.code ?? ''} ${e.message}`), 'GitHub identity response could not be read; body suppressed.');
  }
  if (j.login !== expected) throw new NetworkError('identity', 'Authenticated GitHub account differs from --account.');
  return j.login;
}
export async function gitOperation({ repoPath, remote = 'origin', operation, branch, token, runner = run, retryOptions = {} }) {
  if (!['ls-remote', 'fetch', 'push'].includes(operation)) throw new NetworkError('configuration', 'Git operation must be ls-remote, fetch or push.');
  if (!/^[A-Za-z0-9][A-Za-z0-9_.-]*$/.test(remote)) throw new NetworkError('configuration', 'Invalid remote name.');
  const env = childEnv(token), cwd = path.resolve(repoPath);
  for (const k of Object.keys(env)) if (/^GIT_(DIR|WORK_TREE|INDEX_FILE|COMMON_DIR|OBJECT_DIRECTORY|ALTERNATE_OBJECT_DIRECTORIES)$/.test(k)) delete env[k];
  const git = args => runner('git', args, { cwd, env, timeout: 90000 });
  const guard = await git(['config', '--get-regexp', '^url\\..*\\.(insteadof|pushinsteadof)$']);
  if (guard.code === 0) throw new NetworkError('configuration', 'URL rewrite rules detected. Review them manually; no authenticated request was sent.');
  if (guard.code !== 1) throw new NetworkError('configuration', 'Unable to inspect Git URL rewrite rules.');
  const inspectionEnv = { ...env };
  // Remove only the final Authorization record from this local configuration inspection.
  if (token) {
    const last = Number(env.GIT_CONFIG_COUNT) - 1;
    inspectionEnv.GIT_CONFIG_COUNT = String(last);
    delete inspectionEnv[`GIT_CONFIG_KEY_${last}`];
    delete inspectionEnv[`GIT_CONFIG_VALUE_${last}`];
  }
  const security = await runner('git', ['config', '--get-regexp', '^http\\..*(sslverify|followredirects|extraheader)$'], { cwd, env: inspectionEnv, timeout: 10000 });
  if (![0,1].includes(security.code)) throw new NetworkError('configuration', 'Cannot inspect scoped Git HTTP security settings.');
  for (const line of security.text.split(/\r?\n/).filter(Boolean)) {
    const m = /^(\S+)\s*(.*)$/.exec(line);
    if (!m) throw new NetworkError('configuration', 'Cannot parse Git HTTP security settings.');
    const key = m[1].toLowerCase(), value = m[2].trim().toLowerCase();
    if ((key.endsWith('.sslverify') && !['true','yes','on','1'].includes(value)) ||
        (key.endsWith('.followredirects') && !['false','no','off','0'].includes(value)) ||
        (key.endsWith('.extraheader') && value)) throw new NetworkError('configuration', 'Unsafe or conflicting scoped Git HTTP settings detected; review TLS, redirects and extra headers manually.');
  }
  const r = await git(['remote', 'get-url', '--all', remote]);
  if (r.code !== 0 || r.text.trim().split(/\r?\n/).length !== 1) throw new NetworkError('configuration', 'Expected one fetch URL for this remote.');
  let url = githubRepo(r.text.trim());
  if (operation === 'push') {
    const p = await git(['remote', 'get-url', '--push', '--all', remote]);
    if (p.code !== 0 || p.text.trim().split(/\r?\n/).length !== 1 || githubRepo(p.text.trim()) !== url) throw new NetworkError('configuration', 'Push URL differs from fetch URL; refusing an implicit destination change.');
  }
  let sha;
  if (operation === 'push') {
    if (!branch || branch.startsWith('-') || /[\s:]/.test(branch)) throw new NetworkError('configuration', 'An explicit branch name is required.');
    const check = await git(['check-ref-format', `refs/heads/${branch}`]);
    if (check.code !== 0) throw new NetworkError('configuration', 'Invalid branch ref.');
    const defaultRef = await retry(async () => {
      const result = await git(['ls-remote', '--symref', url, 'HEAD']);
      if (result.code !== 0) throw new NetworkError(result.timedOut ? 'network' : classify(result.text), 'Cannot determine remote default branch.');
      const match = /^ref: refs\/heads\/(\S+)\s+HEAD$/m.exec(result.text);
      if (!match) throw new NetworkError('configuration', 'Remote default branch is unknown; refusing push.');
      return match[1];
    }, retryOptions);
    if (['master', 'main', defaultRef].includes(branch)) throw new NetworkError('rejected', 'Direct push to the default/main/master branch is disabled. Use a feature branch and PR.');
    const head = await git(['rev-parse', '--verify', 'HEAD']);
    if (head.code !== 0 || !/^[0-9a-f]{40,64}$/.test(head.text.trim())) throw new NetworkError('configuration', 'Cannot resolve HEAD commit.');
    sha = head.text.trim();
  }
  const args = operation === 'push' ? ['push', '--porcelain', '--no-follow-tags', '--recurse-submodules=no', url, `${sha}:refs/heads/${branch}`] : operation === 'fetch' ? ['fetch', '--no-recurse-submodules', '--no-prune', '--no-prune-tags', '--no-tags', url, `refs/heads/*:refs/remotes/${remote}/*`] : ['ls-remote', url, 'HEAD'];
  // No force, hook bypass, global URL mutation, or shell expansion.
  let reconciled = false;
  await retry(async () => {
    const result = await git(args);
    if (result.code === 0) return;
    const category = result.timedOut ? 'network' : classify(result.text);
    if (operation === 'push' && category === 'network') {
      // The server may have accepted the push even when its reply was lost.
      const probe = await git(['ls-remote', url, `refs/heads/${branch}`]);
      if (probe.code !== 0) throw new NetworkError('uncertain-push', 'Push outcome unknown: remote verification failed. Do not blindly retry.');
      const remoteSha = probe.text.trim().split(/\s+/)[0];
      if (remoteSha === sha) { reconciled = true; return; }
      // Remote HEAD differs or is absent. Retrying the frozen SHA remains non-force.
    }
    throw new NetworkError(category, `Git ${operation} failed (${category}); raw output suppressed to protect credentials.`);
  }, retryOptions);
  return { operation, repository: url, ...(sha ? { sha, branch, reconciled } : {}), ok: true };
}
const DOWNLOAD_HOSTS = new Set(['github.com','api.github.com','raw.githubusercontent.com','codeload.github.com','release-assets.githubusercontent.com','objects.githubusercontent.com','github-releases.githubusercontent.com','objects-origin.githubusercontent.com']);
export function checkedDownloadUrl(value) {
  let u; try { u = new URL(value); } catch { throw new NetworkError('configuration', 'Invalid download URL.'); }
  if (u.protocol !== 'https:' || !DOWNLOAD_HOSTS.has(u.hostname) || u.username || u.password || (u.port && u.port !== '443')) throw new NetworkError('configuration', 'Only credential-free official GitHub HTTPS download hosts are allowed.');
  return u;
}
export async function download({ url, output, sha256, fetchImpl = fetch, retryOptions = {} }) {
  requireTlsVerification();
  checkedDownloadUrl(url);
  if (!output) throw new NetworkError('configuration', 'Pass --output with an artifact destination.');
  if (!/^[0-9a-f]{64}$/i.test(sha256 ?? '')) throw new NetworkError('configuration', 'A SHA-256 from a trusted source is required.');
  const dest = path.resolve(output);
  const hashFile = async file => { const h = crypto.createHash('sha256'); for await (const c of fs.createReadStream(file)) h.update(c); return h.digest('hex'); };
  if (fs.existsSync(dest)) {
    if ((await hashFile(dest)) === sha256.toLowerCase()) return { ok: true, cached: true, output: dest, sha256: sha256.toLowerCase() };
    throw new NetworkError('integrity', 'Destination exists with different bytes; refusing to overwrite.');
  }
  fs.mkdirSync(path.dirname(dest), { recursive: true });
  return retry(async () => {
    const temp = `${dest}.${crypto.randomUUID()}.part`;
    try {
      let u = checkedDownloadUrl(url), response;
      for (let hop = 0; hop < 6; hop++) {
        response = await fetchImpl(u, { redirect: 'manual', signal: AbortSignal.timeout(60000), headers: { 'User-Agent': 'dsh-windows-ops-network' } });
        if (response.status >= 300 && response.status < 400) {
          const loc = response.headers.get('location'); await response.body?.cancel();
          if (!loc) throw new NetworkError('redirect', 'Missing redirect location.');
          u = checkedDownloadUrl(new URL(loc, u)); response = undefined; continue;
        }
        break;
      }
      if (!response) throw new NetworkError('redirect', 'Too many download redirects.');
      if (!response.ok) { await response.body?.cancel(); throw new NetworkError(classify('', response.status), `Download HTTP ${response.status}`); }
      const h = crypto.createHash('sha256'); let bytes = 0;
      const handle = await fs.promises.open(temp, 'wx');
      try { for await (const chunk of response.body) { bytes += chunk.length; if (bytes > 256 * 1024 * 1024) throw new NetworkError('size', 'Download exceeds 256 MiB limit.'); h.update(chunk); await handle.writeFile(chunk); } } finally { await handle.close(); }
      if (!bytes || h.digest('hex') !== sha256.toLowerCase()) throw new NetworkError('integrity', 'Downloaded bytes do not match trusted SHA-256.');
      // Exclusive publication: do not overwrite a destination created concurrently.
      await fs.promises.link(temp, dest);
      return { ok: true, cached: false, output: dest, bytes, sha256: sha256.toLowerCase() };
    } catch (e) {
      if (e instanceof NetworkError) throw e;
      throw new NetworkError(classify(`${e.name} ${e.cause?.code ?? ''} ${e.message}`), 'Download failed; no unverified destination was published.');
    } finally { await fs.promises.rm(temp, { force: true }).catch(() => {}); }
  }, retryOptions);
}
function argsOf(argv) {
  const [command, ...args] = argv, options = {};
  for (let i = 0; i < args.length; i += 2) {
    if (!/^--[a-z][a-z0-9-]*$/.test(args[i]) || !args[i+1] || args[i+1].startsWith('--')) throw new NetworkError('configuration', 'Options require --name value pairs.');
    if (args[i] in options) throw new NetworkError('configuration', 'Duplicate option.');
    options[args[i]] = args[i+1];
  }
  const valid = new Set(['--token-file','--account','--repo','--remote','--operation','--branch','--url','--output','--sha256','--vpn']);
  for (const k of Object.keys(options)) if (!valid.has(k)) throw new NetworkError('configuration', 'Unknown option.');
  return { command, options };
}
export async function main(argv) {
  const { command, options: o } = argsOf(argv);
  if (o['--vpn'] && o['--vpn'] !== 'MSFTVPN') throw new NetworkError('configuration', 'Only the saved MSFTVPN profile is supported.');
  const retryOptions = { vpn: o['--vpn'], onNetwork: vpnConnect };
  if (command === 'download') return download({ url: o['--url'], output: o['--output'], sha256: o['--sha256'], retryOptions });
  if (!['check','git'].includes(command)) throw new NetworkError('configuration', 'Usage: github-network.mjs check|git|download --option value. See docs/github-network.md.');
  const token = tokenFromFile(o['--token-file']);
  if (!o['--account']) throw new NetworkError('configuration', 'Pass the expected --account before authenticating.');
  const login = await retry(() => verifyIdentity(token, o['--account']), retryOptions);
  if (command === 'git') {
    if (!o['--repo']) throw new NetworkError('configuration', 'Pass --repo with the existing repository path.');
    return gitOperation({ repoPath: o['--repo'], remote: o['--remote'], operation: o['--operation'], branch: o['--branch'], token, retryOptions });
  }
  const endpoints = ['https://github.com','https://api.github.com','https://raw.githubusercontent.com/github/gitignore/main/Node.gitignore'];
  const probes = [];
  for (const url of endpoints) { const start = Date.now(); try { const r = await request(url, { method: 'HEAD' }); probes.push({ host: new URL(url).hostname, status: r.status, ms: Date.now()-start }); } catch (e) { probes.push({ host: new URL(url).hostname, error: e.category }); } }
  return { ok: probes.every(p => p.status === 200), login, node: process.version, platform: os.platform(), probes, note: 'Short-lived probes are not a guarantee of long-term reliability or push permission.' };
}
if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  main(process.argv.slice(2)).then(r => { console.log(JSON.stringify(r, null, 2)); if (r.ok === false) process.exitCode = 1; }).catch(e => { console.error(JSON.stringify({ ok: false, category: e.category ?? 'other', message: e instanceof NetworkError ? e.message : 'Operation failed; raw exception suppressed.' })); process.exitCode = 1; });
}
