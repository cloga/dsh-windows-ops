import { readFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const action = 'Review the preset and exact target artifacts before retrying; do not overwrite user instructions.';
const failure = code => ({
  valid: false, status: 'user-preset-config-blocked',
  diagnostics: [{ preset: '', row: '', plugin: '', version: '', key: '', code, action }],
});
const codes = new Set([
  'entry-list-invalid', 'entry-invalid', 'entry-id-conflict', 'dynamic-group-unsupported',
  'group-plugin-unsupported', 'plugin-specifier-unsupported', 'dynamic-config-unsupported',
  'plugin-unresolvable-or-import-unsupported', 'plugin-contract-unsupported', 'schema-export-conflict',
  'schema-contract-unsupported', 'schema-result-unsupported', 'config-invalid', 'schema-validation-failed',
  'preset-input-changed', 'manifest-invalid', 'target-or-validator-unsupported',
]);
const contextFields = {
  preset: /^(?:|\.agent-presets\/[^/\\\x00-\x1f]{1,128}\/agent\.cordis\.yml)$/,
  row: /^(?:|[1-9]\d*(?:\.[1-9]\d*)*\.?)$/,
  plugin: /^(?:|(?:@[a-z0-9][a-z0-9._-]*\/)?[a-z0-9][a-z0-9._-]*)$/,
  version: /^(?:|\d+\.\d+\.\d+(?:-[a-zA-Z0-9.-]+)?(?:\+[a-zA-Z0-9.-]+)?)$/,
};
function cleanContext(item) {
  return Object.fromEntries(Object.entries(contextFields).map(([key, pattern]) => {
    if (typeof item[key] !== 'string' || item[key].length > 256 || !pattern.test(item[key])) {
      throw new Error('protocol');
    }
    return [key, item[key]];
  }));
}

// The supervisor never imports target code, and never forwards child exception streams.
let result;
try {
  const request = JSON.parse(readFileSync(0, 'utf8'));
  if (!Number.isInteger(request.timeoutMs) || request.timeoutMs < 1000 || request.timeoutMs > 60000) {
    throw new Error('request');
  }
  const worker = fileURLToPath(new URL('./dsh-preset-config-worker.mjs', import.meta.url));
  const args = [
    '--permission', '--no-addons', '--no-warnings', '--disable-proto=throw',
    '--experimental-import-meta-resolve', '--max-old-space-size=192',
    `--allow-fs-read=${worker}`, `--allow-fs-read=${request.root}`,
    ...request.manifests.map(item => `--allow-fs-read=${item.path}`),
    worker,
  ];
  const child = spawnSync(process.execPath, args, {
    input: JSON.stringify(request), encoding: 'utf8', timeout: request.timeoutMs,
    maxBuffer: 262144, windowsHide: true, env: { SystemRoot: process.env.SystemRoot ?? '' },
  });
  if (child.error?.code === 'ETIMEDOUT') result = failure('validator-timeout');
  else if (child.error || child.status !== 0) result = failure('validator-process-failed');
  else {
    const payload = JSON.parse(child.stdout);
    // Reject noise or foreign protocol fields rather than letting imports print through the gate.
    const allowed = new Set(['valid', 'status', 'diagnostics', 'rows']);
    if (Object.keys(payload).some(key => !allowed.has(key)) ||
        typeof payload.valid !== 'boolean' ||
        !Array.isArray(payload.diagnostics) || !Array.isArray(payload.rows) ||
        payload.diagnostics.length > 256 || payload.rows.length > 4096 ||
        payload.valid !== (payload.diagnostics.length === 0)) throw new Error('protocol');
    const diagnostics = payload.diagnostics.map(item => {
      if (!codes.has(item.code) || typeof item.key !== 'string' || item.key.length > 2304 ||
          !/^(?:|\$(?:\.(?:[a-zA-Z_][a-zA-Z0-9_-]{0,63}|\*))*)$/.test(item.key)) throw new Error('protocol');
      return { ...cleanContext(item), key: item.key, code: item.code, action };
    });
    const rows = payload.rows.map(item => {
      if (!['schema-valid', 'schema-less-passthrough'].includes(item.status)) throw new Error('protocol');
      return { ...cleanContext(item), status: item.status };
    });
    result = {
      valid: diagnostics.length === 0,
      status: diagnostics.length ? 'user-preset-config-blocked' : 'user-preset-config-verified',
      diagnostics, rows,
    };
  }
} catch {
  result = failure('validator-protocol-invalid');
}
process.stdout.write(JSON.stringify(result));
