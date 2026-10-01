// Optional source-owned ordinary acceptance. No acquisition, execution, or live-account claim.
import { isDeepStrictEqual } from 'node:util';
import { hashValid, object, requireValue } from './native-runtime-integrity.mjs';

const exact = (value, keys) => object(value) && Object.keys(value).length === keys.length &&
  keys.every(key => Object.hasOwn(value, key));

// Dynamic browser rectangles are observations, not reproducible cross-run byte identities.
export function assertNativeComposerGeometry(value, viewportWidth) {
  const need = condition => requireValue(condition, 'native-release-composer-mismatch');
  need(exact(value, ['viewportWidth', 'dock', 'time', 'usage', 'copilot', 'nativeStyle', 'copilotStyle']) &&
    value.viewportWidth === viewportWidth);
  for (const box of [value.dock, value.time, value.usage, value.copilot]) {
    need(exact(box, ['x', 'y', 'width', 'height']) && Object.values(box).every(Number.isFinite) &&
      box.width > 0 && box.height > 0 && Number.isFinite(box.x + box.width) && Number.isFinite(box.y + box.height));
  }
  const boxes = [value.time, value.usage, value.copilot];
  for (const box of boxes) {
    need(box.x >= value.dock.x - 1 && box.x + box.width <= value.dock.x + value.dock.width + 1 &&
      box.x >= -1 && box.x + box.width <= viewportWidth + 1);
  }
  for (let index = 0; index < boxes.length; index++) for (const other of boxes.slice(index + 1)) {
    const box = boxes[index];
    need(box.x + box.width <= other.x + 1 || other.x + other.width <= box.x + 1 ||
      box.y + box.height <= other.y + 1 || other.y + other.height <= box.y + 1);
  }
  if (viewportWidth === 1280) {
    const center = value.usage.y + value.usage.height / 2;
    need(Math.abs(value.time.y + value.time.height / 2 - center) <= 1 &&
      Math.abs(value.copilot.y + value.copilot.height / 2 - center) <= 1 &&
      value.copilot.x >= value.usage.x + value.usage.width);
  }
  const style = value.nativeStyle;
  need(exact(style, ['fontSize', 'lineHeight', 'color']) && isDeepStrictEqual(style, value.copilotStyle));
  for (const key of ['fontSize', 'lineHeight']) need(typeof style[key] === 'string' &&
    /^\d+(?:\.\d+)?px$/u.test(style[key]) && Number.isFinite(Number.parseFloat(style[key])) && Number.parseFloat(style[key]) > 0);
  need(typeof style.color === 'string' && style.color.trim().length > 0 && style.color.length <= 256 &&
    !/[\u0000-\u001f]/u.test(style.color));
}

// Formal callers authenticate this file against proof.sha256; fresh callers deliberately
// read their own new file without matching dynamic rectangles to another run's hash.
export function verifyNativeComposerEvidence(lock, accepted, read) {
  const desktop = lock.components.desktop;
  const native = desktop.releaseChannel.nativeProvisioning;
  const proof = native.nativeComposerAcceptance;
  if (proof === undefined) return;
  const need = value => requireValue(value, 'native-release-composer-mismatch');
  need(exact(proof, ['schemaVersion', 'sha256', 'installedClientSha256']) && proof.schemaVersion === 1 &&
    hashValid(proof.sha256) && hashValid(proof.installedClientSha256) &&
    native.settingsAcceptance?.schemaVersion === 3 && native.usageAcceptance?.schemaVersion === 1 &&
    native.usagePositiveAcceptance?.schemaVersion === 1 &&
    native.usagePositiveAcceptance.installedClientSha256 === proof.installedClientSha256 &&
    native.packagedAcceptance === undefined);
  const value = read('native-composer-geometry.json', proof.sha256);
  need(exact(value, ['schemaVersion', 'scope', 'sourceCommit', 'sessionHistory', 'quota', 'runtimeSha256',
    'pluginSource', 'installedClientSha256', 'geometry', 'nativeDialogs', 'copilotDialog', 'rendererErrors', 'realModelRound', 'realOAuth']) &&
    value.schemaVersion === 1 && value.scope === 'actual-packaged-native-composer-and-released-client' &&
    value.sourceCommit === desktop.source.commit && value.sourceCommit === accepted.sourceCommit &&
    value.sessionHistory === 'synthetic-persisted-in-isolated-home' && value.quota === 'signed-out-host-response-no-credentials' &&
    value.runtimeSha256 === desktop.installedRuntimeDescriptor.sha256 && value.installedClientSha256 === proof.installedClientSha256 &&
    isDeepStrictEqual(value.pluginSource, accepted.plugin) && isDeepStrictEqual(value, accepted.nativeComposer) &&
    value.realModelRound === false && value.realOAuth === false && accepted.isolatedHome === true &&
    accepted.realModelRound === false && accepted.realOAuth === false && accepted.realSearch === false && accepted.liveAccountQuota === false &&
    Array.isArray(value.rendererErrors) && value.rendererErrors.length === 0);
  const plugin = lock.components.copilotIntegration;
  need(object(value.pluginSource) && value.pluginSource.packageName === plugin.package.name &&
    value.pluginSource.targetCommit === plugin.source.commit && value.pluginSource.version === plugin.package.version &&
    value.pluginSource.sha256 === plugin.package.artifact.sha256 && value.pluginSource.assetId === plugin.package.artifact.assetId);
  need(Array.isArray(value.geometry) && value.geometry.length === 2);
  for (const [index, width] of [1280, 400].entries()) assertNativeComposerGeometry(value.geometry[index], width);
  need(exact(value.nativeDialogs, ['time', 'usage']));
  for (const name of ['time', 'usage']) {
    const dialog = value.nativeDialogs[name];
    need(exact(dialog, ['opened', 'closedOnEscape', 'focusReturned']) && dialog.opened === true &&
      dialog.closedOnEscape === true && dialog.focusReturned === true);
  }
  const dialog = value.copilotDialog;
  need(exact(dialog, ['signedOutObserved', 'sessionCreditsCount', 'resetCount', 'epochTextCount', 'focusReturned']) &&
    dialog.signedOutObserved === true && dialog.sessionCreditsCount === 0 && dialog.resetCount === 0 &&
    dialog.epochTextCount === 0 && dialog.focusReturned === true);
  need(Array.isArray(accepted.timeline));
  const events = accepted.timeline.map(row => row?.event);
  const required = ['restart:closed', 'native-composer:seeded', 'native-composer:closed'];
  need(required.every((event, index) => events.filter(value => value === event).length === 1 &&
    (index === 0 || events.indexOf(event) > events.indexOf(required[index - 1]))));
}

// The caller authenticates deterministic settings/menu bytes in both formal and fresh paths.
export function verifySettingsV3Evidence(lock, accepted, read) {
  const code = 'native-release-settings-v3-mismatch';
  const need = value => requireValue(value, code);
  const desktop = lock.components.desktop;
  const proof = desktop.releaseChannel.nativeProvisioning.settingsAcceptance;
  need(object(proof) && proof.schemaVersion === 3 &&
    ['initialSha256', 'restartSha256', 'initialVersionMenuSha256', 'restartVersionMenuSha256'].every(key => hashValid(proof[key])));
  need(accepted.searchProviderCatalogLoaded === true && accepted.providerOnlySearchRouting === true &&
    accepted.fallbackProviderLabel === true && accepted.manageCompatibilityDisclosureAbsent === true &&
    accepted.realSearch === false && accepted.realOAuth === false && accepted.realModelRound === false &&
    accepted.verificationNavigationExercised === false && accepted.manualVerificationAddressObserved === false &&
    !Object.hasOwn(accepted, 'modelRolesViewLoaded') && !Object.hasOwn(accepted, 'currentWorkspaceReadOnly') &&
    Array.isArray(accepted.settingsAcceptance) && accepted.settingsAcceptance.length === 2);
  const observations = []; const menus = [];
  for (const phase of ['initial', 'restart']) {
    const settings = read(`${phase}-settings-readonly.json`, proof[`${phase}Sha256`]);
    need(exact(settings, ['schemaVersion', 'accountViewLoaded', 'retiredModelRolesAbsent',
      'searchProviderCatalogLoaded', 'providerOnlySearchRouting', 'fallbackProviderLabel', 'registeredSearchProviders', 'realSearch']) &&
      settings.schemaVersion === 3 && settings.accountViewLoaded === true && settings.retiredModelRolesAbsent === true &&
      settings.searchProviderCatalogLoaded === true && settings.providerOnlySearchRouting === true &&
      settings.fallbackProviderLabel === true && settings.realSearch === false);
    const ids = settings.registeredSearchProviders;
    need(Array.isArray(ids) && ids.every(id => typeof id === 'string' && id.length > 0) &&
      new Set(ids).size === ids.length && ids.includes('github-copilot-hosted'));
    observations.push(settings);
    const menu = read(`${phase}-version-menu.json`, proof[`${phase}VersionMenuSha256`]);
    need(object(menu) && menu.applicationMenuLabel === 'Application' &&
      menu.aboutMenuLabel === `About Desktop ${desktop.version}…` && menu.desktopVersion === desktop.version &&
      menu.aboutDispatchCount === 1 && menu.nativeModalOpened === false);
    menus.push(menu);
  }
  need(isDeepStrictEqual(observations[0], observations[1]) &&
    isDeepStrictEqual(accepted.settingsAcceptance, observations) &&
    isDeepStrictEqual(menus[0], menus[1]) && isDeepStrictEqual(accepted.versionMenus, menus));
}
