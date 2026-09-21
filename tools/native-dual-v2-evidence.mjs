// Pure leaves for the explicitly selected dual-ordinary-canary-v2 family only.
// Mirror Core's settings3/seed6/native2 contracts; no I/O, browser or Core imports.
// Source-parity checked against immutable Core 9ca7cc3f06c9f7b90128e24687a5ce6e960b6618; not runtime qualification.
import { isDeepStrictEqual } from 'node:util';
import { requireValue } from './native-runtime-integrity.mjs';

const need = condition => requireValue(condition, 'native-packaged-evidence-invalid');
const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const exact = (value, fields) => {
  need(object(value) && fields.every(field => Object.hasOwn(value, field)) &&
    Object.keys(value).length === fields.length && Object.keys(value).every(field => fields.includes(field)));
};
const equal = (left, right) => need(isDeepStrictEqual(left, right));
const hash = value => typeof value === 'string' && /^[a-f0-9]{64}$/u.test(value);
const identityFields = ['evidenceId', 'sourceCommit', 'sourceTree', 'runId', 'runAttempt', 'planSha256',
  'runtimeSha256', 'executableSha256', 'provisioningSha256', 'capabilitySha256'];
const settingsTrue = ['accountViewLoaded', 'retiredModelRolesAbsent', 'searchProviderCatalogLoaded',
  'providerOnlySearchRouting', 'fallbackProviderLabel'];

// Independently audited original alpha.35 source/checksum/Client pair, not receipt-selected policy.
// Freeze both levels: consumers may copy this fixture policy but cannot mutate its admission rules.
export const reviewedCopilot35 = Object.freeze({
  schemaVersion: 1, type: 'githubRelease', owner: 'cloga', repo: 'dsh-github-copilot',
  tag: 'v0.4.0-alpha.35', asset: 'dsh-github-copilot-0.4.0-alpha.35.tgz', assetId: 579078676,
  packageName: 'dsh-github-copilot', version: '0.4.0-alpha.35', size: 705000,
  sha256: 'ec4f0fa24b45d94686a396b2558ef6b7fc5d521b9d94e65dcff9f772421f496d',
  integrity: 'sha512-WCKmOsgXN1z/UuxJqKPp42VbCR9z/nPAWVvIReB0jjtU0144xu1nSn8toDxJ9q9Ij656vxLV35pPHbFwbo1qeA==',
  targetCommit: '6554417dc9a7544865e6c1bbdebf8b9a10e0a7af', dependencyRegistry: 'https://packagefeedproxy.microsoft.io/npm/',
  checksumManifest: Object.freeze({
    format: 'sha256sums', asset: 'SHA256SUMS', assetId: 579078699,
    url: 'https://github.com/cloga/dsh-github-copilot/releases/download/v0.4.0-alpha.35/SHA256SUMS', size: 104,
    sha256: '51930bf90fd22b04813494b301951b681a1b82a622351e93152f06ad8d3b93ab',
    integrity: 'sha512-X41UN3az6uzTTWAC1q9kZJ9XGTKdBulYuStmzW4GaCIYt9+5MGAcp+D0hyvOJ8pZkdrdetFI9fzPB1nrbIzysA==',
  }),
});
export const reviewedClient35 = '7b4566ef30e1c3c11e64aee527cea8bc5adbf0f22ca356cc8bd3ab07661fd368';

/** Require the complete reviewed alpha.35 tuple, never another family's fallback. */
export function assertReviewedV2Client(source, digest) {
  equal(source, reviewedCopilot35);
  equal(digest, reviewedClient35);
}

/** Exact settings3 retirement evidence; the Core bound is 1..256 characters per provider ID. */
export function assertV2Settings(value) {
  exact(value, ['schemaVersion', ...settingsTrue, 'registeredSearchProviders', 'realSearch']);
  equal(value.schemaVersion, 3);
  for (const field of settingsTrue) equal(value[field], true);
  equal(value.realSearch, false);
  const providers = value.registeredSearchProviders;
  need(Array.isArray(providers) && providers.every(provider =>
    typeof provider === 'string' && provider.length > 0 && provider.length <= 256));
  need(new Set(providers).size === providers.length && providers.includes('github-copilot-hosted'));
}

/** Original six-field seed receipt, deliberately without a schemaVersion field. */
export function assertV2Seed(value) {
  exact(value, ['sessionId', 'scope', 'workspaceRegistered', 'provider', 'seederModelCalls', 'liveAccountQuota']);
  equal(value.sessionId, 'desktop-inline-composer-synthetic');
  equal(value.scope, 'test-owned-persisted-session-with-synthetic-history-and-token-counts');
  equal(value.workspaceRegistered, true);
  equal(value.provider, 'github-copilot');
  equal(value.seederModelCalls, 0);
  equal(value.liveAccountQuota, false);
}

function geometry(value, viewportWidth, inline) {
  exact(value, ['viewportWidth', 'dock', 'time', 'usage', 'copilot', 'nativeStyle', 'copilotStyle']);
  equal(value.viewportWidth, viewportWidth);
  for (const name of ['dock', 'time', 'usage', 'copilot']) {
    const box = value[name];
    exact(box, ['x', 'y', 'width', 'height']);
    for (const [field, number] of Object.entries(box)) {
      need(typeof number === 'number' && Number.isFinite(number) && Math.abs(number) <= 16384);
      if (field === 'width' || field === 'height') need(number > 0);
    }
  }
  for (const name of ['nativeStyle', 'copilotStyle']) {
    const style = value[name];
    exact(style, ['fontSize', 'lineHeight', 'color']);
    for (const text of Object.values(style)) need(typeof text === 'string' && text.length > 0 && text.length <= 128);
    for (const field of ['fontSize', 'lineHeight']) {
      need(/^(?:\d+(?:\.\d+)?)px$/u.test(style[field]));
      const pixels = Number.parseFloat(style[field]);
      need(pixels > 0 && pixels <= 256);
    }
  }
  equal(value.copilotStyle, value.nativeStyle);
  const boxes = [value.time, value.usage, value.copilot];
  for (const box of boxes) {
    need(box.x >= value.dock.x - 1 && box.x + box.width <= value.dock.x + value.dock.width + 1);
    need(box.y >= value.dock.y - 1 && box.y + box.height <= value.dock.y + value.dock.height + 1);
    need(box.x >= -1 && box.x + box.width <= value.viewportWidth + 1);
  }
  for (let index = 0; index < boxes.length; index++) {
    for (const other of boxes.slice(index + 1)) {
      const box = boxes[index];
      need(box.x + box.width <= other.x + 1 || other.x + other.width <= box.x + 1 ||
        box.y + box.height <= other.y + 1 || other.y + other.height <= box.y + 1);
    }
  }
  // The narrow observation may wrap. There is no viewport-height field to invent or enforce.
  if (inline) {
    const center = value.usage.y + value.usage.height / 2;
    need(Math.abs(value.time.y + value.time.height / 2 - center) <= 1);
    need(Math.abs(value.copilot.y + value.copilot.height / 2 - center) <= 1);
    need(value.copilot.x >= value.usage.x + value.usage.width);
  }
}

/** Bind native2 observations to this family's full identity and its separately hashed original seed. */
export function assertV2Native(value, identity, source, seedSha256, installedClientSha256) {
  exact(value, ['schemaVersion', 'scope', ...identityFields, 'seedSha256', 'sessionHistory', 'quota', 'pluginSource',
    'installedClientSha256', 'geometry', 'nativeDialogs', 'copilotDialog', 'rendererErrors', 'realModelRound', 'realOAuth']);
  equal(value.schemaVersion, 2);
  equal(value.scope, 'actual-packaged-native-composer-and-released-client');
  need(object(identity) && identityFields.every(field => Object.hasOwn(identity, field)));
  for (const field of identityFields) equal(value[field], identity[field]);
  need(typeof identity.evidenceId === 'string' && /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/u.test(identity.evidenceId));
  for (const field of ['sourceCommit', 'sourceTree']) need(typeof identity[field] === 'string' && /^[a-f0-9]{40}$/u.test(identity[field]));
  for (const field of ['planSha256', 'runtimeSha256', 'executableSha256', 'provisioningSha256', 'capabilitySha256']) need(hash(identity[field]));
  for (const field of ['runId', 'runAttempt']) need(identity[field] === null || typeof identity[field] === 'string' && /^\d+$/u.test(identity[field]));
  need(hash(seedSha256));
  equal(value.seedSha256, seedSha256);
  equal(value.pluginSource, source);
  equal(value.installedClientSha256, installedClientSha256);
  assertReviewedV2Client(source, installedClientSha256);
  equal(value.sessionHistory, 'synthetic-persisted-in-isolated-home');
  equal(value.quota, 'signed-out-host-response-no-credentials');
  equal(value.realModelRound, false);
  equal(value.realOAuth, false);
  equal(value.rendererErrors, []);
  need(Array.isArray(value.geometry) && value.geometry.length === 2);
  geometry(value.geometry[0], 1280, true);
  geometry(value.geometry[1], 400, false);
  exact(value.nativeDialogs, ['time', 'usage']);
  for (const name of ['time', 'usage']) {
    const dialog = value.nativeDialogs[name];
    exact(dialog, ['opened', 'closedOnEscape', 'focusReturned']);
    for (const field of ['opened', 'closedOnEscape', 'focusReturned']) equal(dialog[field], true);
  }
  exact(value.copilotDialog, ['signedOutObserved', 'sessionCreditsCount', 'resetCount', 'epochTextCount', 'focusReturned']);
  equal(value.copilotDialog.signedOutObserved, true);
  equal(value.copilotDialog.focusReturned, true);
  for (const field of ['sessionCreditsCount', 'resetCount', 'epochTextCount']) equal(value.copilotDialog[field], 0);
}
