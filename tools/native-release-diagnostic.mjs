// Failure observability only: never publish source error text, paths or file contents.
import { closeSync, fstatSync, openSync, readSync } from 'node:fs';
import { join } from 'node:path';
import { physical } from './native-runtime-integrity.mjs';

export const diagnosticStages = Object.freeze(['source-import', 'source-fixture', 'observer', 'post-acceptance', 'final-runtime']);
export const diagnosticPhases = Object.freeze(['none', 'package-identity', ...['initial', 'restart'].flatMap(phase =>
  ['launch', 'version-menu', 'application', 'account', 'usage-readonly', 'settings-readonly', 'packaged-graph', 'closed'].map(step => `${phase}:${step}`)), 'restart:positive-usage']);
export const diagnosticCodes = Object.freeze(['unknown', 'desktop-startup', 'locator-timeout', 'electron-launch',
  'assertion', 'child-command', 'module-not-found', 'native-addon', 'access-denied', 'missing-file', 'package-export',
  'plugin-github-http-401', 'plugin-github-http-403', 'plugin-github-http-404', 'plugin-github-http-429',
  'plugin-github-http-5xx', 'plugin-github-http-other', 'plugin-github-redirect', 'plugin-github-policy', 'startup-fetch-failed']);

const httpCodes = new Map([['401','plugin-github-http-401'],['403','plugin-github-http-403'],
  ['404','plugin-github-http-404'],['429','plugin-github-http-429']]);
const fixedStartup = new Map([
  ['desktop plugin source: GitHub redirect limit exceeded','plugin-github-redirect'],
  ['desktop plugin source: GitHub redirect omitted its location','plugin-github-redirect'],
  ['desktop plugin source: GitHub request must use credential-free HTTPS','plugin-github-policy'],
  ['fetch failed','startup-fetch-failed'],
]);
// Core f255: github-release.ts emits these complete lines with plugin-source.ts's
// fixed subject; desktopErrorState joins AggregateError messages with newlines.
// The smoke fixture wraps #error text. Categories observe text, not cause/origin:
// 403 is not a rate-limit diagnosis, and bare fetch failure retains no cause chain.
function ownedStartupCategory(value) {
  if (value.length > 131072) return undefined; // Truncation must not manufacture an exact line.
  const wrapper = /^(?:Error: )?Packaged Desktop startup failed: ([\s\S]*)$/u.exec(value);
  if (!wrapper) return undefined;
  const codes = new Set();
  for (const line of wrapper[1].split(/\r?\n/u)) {
    const fixed = fixedStartup.get(line);
    if (fixed !== undefined) codes.add(fixed);
    const http = /^desktop plugin source: GitHub request failed with ([3-5][0-9]{2})$/u.exec(line);
    // The source handles redirects separately; successful/redirect statuses cannot emit this message.
    if (http && http[0] === line && !['301','302','303','307','308'].includes(http[1])) {
      codes.add(httpCodes.get(http[1]) ?? (http[1].startsWith('5') ? 'plugin-github-http-5xx' : 'plugin-github-http-other'));
    }
  }
  return codes.size === 1 ? codes.values().next().value : undefined;
}

export function classifySourceError(value) {
  if (typeof value !== 'string') return 'unknown';
  const original = value;
  value = value.slice(0, 131072);
  // Fixed output vocabulary only; input is never returned, truncated or redacted into output.
  if (/locator\.[A-Za-z]+: Timeout|TimeoutError:.*locator\./u.test(value)) return 'locator-timeout';
  if (/electron\.launch:|Electron failed to launch/u.test(value)) return 'electron-launch';
  if (/ERR_MODULE_NOT_FOUND|Cannot find (?:module|package)/u.test(value)) return 'module-not-found';
  if (/ERR_DLOPEN_FAILED|No usable native binding found/u.test(value)) return 'native-addon';
  if (/ERR_PACKAGE_PATH_NOT_EXPORTED/u.test(value)) return 'package-export';
  if (/\bEACCES\b|\bEPERM\b/u.test(value)) return 'access-denied';
  if (/\bENOENT\b/u.test(value)) return 'missing-file';
  const startup = ownedStartupCategory(original);
  if (startup !== undefined) return startup;
  if (value.includes('Packaged Desktop startup failed:')) return 'desktop-startup';
  if (/AssertionError|ERR_ASSERTION/u.test(value)) return 'assertion';
  if (/Command failed:/u.test(value)) return 'child-command';
  return 'unknown';
}

/** Build an owned fixed-vocabulary observation before private cleanup. */
export function sourceFailureDiagnostic(sourceOutput, stage, error) {
  const result = { stage: diagnosticStages.includes(stage) ? stage : 'source-fixture',
    code: classifySourceError(typeof error?.message === 'string' ? error.message : ''),
    sourceFailure: 'absent', sourcePhase: 'none' };
  let fd;
  try {
    const path = physical(join(sourceOutput, 'failure.json'), 'file');
    fd = openSync(path, 'r');
    const stat = fstatSync(fd);
    if (!stat.isFile() || stat.size <= 0 || stat.size > 131072) throw new Error('bounded diagnostic');
    const bytes = Buffer.alloc(131073);
    let length = 0;
    while (length < bytes.length) {
      const count = readSync(fd, bytes, length, bytes.length - length, null);
      if (!count) break;
      length += count;
    }
    if (length !== stat.size || length > 131072) throw new Error('changed diagnostic');
    const value = JSON.parse(bytes.subarray(0, length).toString('utf8'));
    if (value === null || typeof value !== 'object' || Array.isArray(value) ||
      !Array.isArray(value.timeline) || value.timeline.length > 64) throw new Error('invalid diagnostic');
    result.sourceFailure = 'present';
    const code = classifySourceError(value.error);
    if (code !== 'unknown') result.code = code;
    for (const row of value.timeline) {
      if (row !== null && typeof row === 'object' && diagnosticPhases.includes(row.event) && row.event !== 'none') {
        result.sourcePhase = row.event;
      }
    }
  } catch (failure) {
    // Missing source output occurs before the fixture's own try/catch; all other
    // malformed/oversized/reparse input remains unreadable, never a leaked error.
    result.sourceFailure = failure?.code === 'ENOENT' || failure?.message === 'native-evidence-missing' ? 'absent' : 'unreadable';
  } finally { if (fd !== undefined) closeSync(fd); }
  return result;
}
