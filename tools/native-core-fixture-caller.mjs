// Used only by the dedicated qualification CLI, never the agent/Host process.
import { isDeepStrictEqual } from 'node:util';
import { requireValue } from './native-runtime-integrity.mjs';
const need = value => requireValue(value, 'native-release-smoke-caller-invalid');

/** Capture genuine Ops workflow identity; the archived Ops source intentionally has no .git. */
export function captureOpsCaller(environment = process.env) {
  need(environment.GITHUB_ACTIONS === 'true' && environment.GITHUB_REPOSITORY === 'cloga/dsh-windows-ops' &&
    typeof environment.GITHUB_SHA === 'string' && /^[a-f0-9]{40}$/u.test(environment.GITHUB_SHA) &&
    typeof environment.GITHUB_RUN_ID === 'string' && /^[1-9]\d*$/u.test(environment.GITHUB_RUN_ID) &&
    typeof environment.GITHUB_RUN_ATTEMPT === 'string' && /^[1-9]\d*$/u.test(environment.GITHUB_RUN_ATTEMPT));
  return Object.freeze({ repository: environment.GITHUB_REPOSITORY, sourceCommit: environment.GITHUB_SHA,
    runId: environment.GITHUB_RUN_ID, runAttempt: environment.GITHUB_RUN_ATTEMPT });
}

/** Omit unrelated Ops SHA only for the isolated Core call; restore it even after import/observer failure. */
export async function withCoreFixtureEnvironment(caller, invoke, environment = process.env) {
  need(isDeepStrictEqual(captureOpsCaller(environment), caller) && typeof invoke === 'function');
  const sourceCommit = environment.GITHUB_SHA;
  delete environment.GITHUB_SHA;
  try { return await invoke(); }
  finally { environment.GITHUB_SHA = sourceCommit; }
}
