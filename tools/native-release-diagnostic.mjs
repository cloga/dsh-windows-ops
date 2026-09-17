// Failure observability only: never publish source error text, paths or file contents.
import { closeSync, fstatSync, openSync, readSync } from 'node:fs';
import { join } from 'node:path';
import { physical } from './native-runtime-integrity.mjs';

export const diagnosticStages = Object.freeze(['source-import', 'source-fixture', 'observer', 'post-acceptance', 'final-runtime']);
export const diagnosticPhases = Object.freeze(['none', 'package-identity', ...['initial', 'restart'].flatMap(phase =>
  ['launch', 'application', 'account', 'settings-readonly', 'packaged-graph', 'closed'].map(step => `${phase}:${step}`))]);
export const diagnosticCodes = Object.freeze(['unknown', 'desktop-startup', 'locator-timeout', 'electron-launch',
  'assertion', 'child-command', 'module-not-found', 'native-addon', 'access-denied', 'missing-file', 'package-export']);

export function classifySourceError(value) {
  if (typeof value !== 'string') return 'unknown';
  value = value.slice(0, 131072);
  // Fixed output vocabulary only; input is never returned, truncated or redacted into output.
  if (/locator\.[A-Za-z]+: Timeout|TimeoutError:.*locator\./u.test(value)) return 'locator-timeout';
  if (/electron\.launch:|Electron failed to launch/u.test(value)) return 'electron-launch';
  if (/ERR_MODULE_NOT_FOUND|Cannot find (?:module|package)/u.test(value)) return 'module-not-found';
  if (/ERR_DLOPEN_FAILED|No usable native binding found/u.test(value)) return 'native-addon';
  if (/ERR_PACKAGE_PATH_NOT_EXPORTED/u.test(value)) return 'package-export';
  if (/\bEACCES\b|\bEPERM\b/u.test(value)) return 'access-denied';
  if (/\bENOENT\b/u.test(value)) return 'missing-file';
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
