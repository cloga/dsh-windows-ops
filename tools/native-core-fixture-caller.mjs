// Used only by the dedicated qualification CLI, never the agent/Host process.
import { isDeepStrictEqual } from 'node:util';
import { requireValue } from './native-runtime-integrity.mjs';
const need = value => requireValue(value, 'native-release-smoke-caller-invalid');
const sourceKeys = ['commit', 'tree', 'version', 'upstreamVersion', 'executableSha256', 'runtimeSha256', 'planSha256'];
function sourceFacts(value) {
  need(value !== null && typeof value === 'object' && !Array.isArray(value) &&
    Object.keys(value).length === sourceKeys.length && sourceKeys.every(key => Object.hasOwn(value, key)));
  for (const key of ['commit', 'tree']) need(typeof value[key] === 'string' && /^[a-f0-9]{40}$/u.test(value[key]));
  for (const key of ['executableSha256', 'runtimeSha256', 'planSha256']) need(typeof value[key] === 'string' && /^[a-f0-9]{64}$/u.test(value[key]));
  need(value.upstreamVersion === '0.1.6-alpha.2' && typeof value.version === 'string' && /^0\.1\.6(?:-[A-Za-z0-9.-]+)?$/u.test(value.version));
  return Object.freeze(Object.fromEntries(sourceKeys.map(key => [key, value[key]])));
}

/** Capture genuine Ops workflow identity; the archived Ops source intentionally has no .git. */
export function captureOpsCaller(environment = process.env) {
  need(environment.GITHUB_ACTIONS === 'true' && environment.GITHUB_REPOSITORY === 'cloga/dsh-windows-ops' &&
    typeof environment.GITHUB_SHA === 'string' && /^[a-f0-9]{40}$/u.test(environment.GITHUB_SHA) &&
    typeof environment.GITHUB_RUN_ID === 'string' && /^[1-9]\d*$/u.test(environment.GITHUB_RUN_ID) &&
    typeof environment.GITHUB_RUN_ATTEMPT === 'string' && /^[1-9]\d*$/u.test(environment.GITHUB_RUN_ATTEMPT));
  return Object.freeze({ repository: environment.GITHUB_REPOSITORY, sourceCommit: environment.GITHUB_SHA,
    runId: environment.GITHUB_RUN_ID, runAttempt: environment.GITHUB_RUN_ATTEMPT });
}

/** Call only after verifyAcquisition/verifySource; this data adapter does not replace either preflight. */
export function expectedCoreSource(lock, verifiedSource) {
  const desktop = lock.components.desktop; const channel = desktop.releaseChannel;
  need(verifiedSource?.sourceRepository === 'cloga/deepseek-harness' &&
    verifiedSource.sourceCommit === desktop.source.commit && verifiedSource.sourceTree === desktop.source.tree &&
    verifiedSource.version === desktop.version && verifiedSource.upstreamVersion === channel.upstreamVersion);
  return sourceFacts({ commit: desktop.source.commit, tree: desktop.source.tree, version: desktop.version,
    upstreamVersion: channel.upstreamVersion, executableSha256: desktop.installedExecutable.sha256,
    runtimeSha256: desktop.installedRuntimeDescriptor.sha256, planSha256: channel.build.planSha256 });
}

/** Pass explicit verified Core facts through import/call without deleting, spoofing or restoring Ops environment. */
export async function invokeCoreFixture(caller, expected, invoke, environment = process.env) {
  need(isDeepStrictEqual(captureOpsCaller(environment), caller) && typeof invoke === 'function');
  const facts = sourceFacts(expected);
  let result; let failed = false; let failure;
  try { result = await invoke(facts); } catch (error) { failed = true; failure = error; }
  // Detect caller drift without writing process.env or masking the original Core/import/observer exception.
  try { need(isDeepStrictEqual(captureOpsCaller(environment), caller)); }
  catch (error) { if (!failed) { failed = true; failure = error; } }
  if (failed) throw failure;
  need(isDeepStrictEqual(result, facts)); // The explicit API returns independently observed Core facts, not void.
  return result;
}
