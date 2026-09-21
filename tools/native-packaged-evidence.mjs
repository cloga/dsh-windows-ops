// Read-only alpha.2 evidence adapters. CI receipts are not ordinary acceptance or local activation.
import { closeSync, fstatSync, lstatSync, openSync, readFileSync } from 'node:fs';
import { join, win32 } from 'node:path';
import { isDeepStrictEqual } from 'node:util';
import { hashValid, object, physical, requireValue, sha256, validateDescriptor } from './native-runtime-integrity.mjs';

const need = condition => requireValue(condition, 'native-packaged-evidence-invalid');
const exact = (value, required, optional = []) => {
  need(object(value) && required.every(key => Object.hasOwn(value, key)) &&
    Object.keys(value).every(key => required.includes(key) || optional.includes(key)));
};
const flags = (value, yes, no = []) => {
  need(object(value));
  for (const key of yes) need(value[key] === true);
  for (const key of no) need(value[key] === false);
};
const equal = (left, right) => need(isDeepStrictEqual(left, right));
const uuid = value => typeof value === 'string' && /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/u.test(value);
const positive = value => typeof value === 'string' && /^[1-9]\d*$/u.test(value);
const identityKeys = ['evidenceId', 'sourceCommit', 'sourceTree', 'runId', 'runAttempt', 'planSha256',
  'runtimeSha256', 'executableSha256', 'provisioningSha256', 'capabilitySha256'];
const functionalTrue = ['isolatedHome', 'onboardingNoticeDismissed', 'actualGraphVerified', 'ancestorSdkJunction',
  'accountEntryVisible', 'manageCompatibilityDisclosureAbsent', 'modelRolesViewLoaded', 'currentWorkspaceReadOnly',
  'searchProviderCatalogLoaded', 'providerOnlySearchRouting', 'fallbackProviderLabel'];
const functionalFalse = ['ancestorSdkLoaded', 'liveAccountQuota', 'realOAuth', 'verificationNavigationExercised',
  'manualVerificationAddressObserved', 'realModelRound', 'realSearch', 'installerUpgradeVerified'];
const functionalKeys = ['schemaVersion', 'scope', ...identityKeys, 'functionalAssertionsCompleted', 'normalAcceptanceCompleted',
  'cleanupVerified', ...functionalTrue, ...functionalFalse, 'desktopVersion', 'runtimeVersion', 'versionMenus', 'plugin',
  'transport', 'restartReceiptSha256', 'copilotUsageCapability', 'signedOutCopilotUsage', 'hostQuotaNoNetworkEvidence', 'timeline'];
const settingsTrue = ['modelRolesViewLoaded', 'currentWorkspaceReadOnly', 'searchProviderCatalogLoaded',
  'providerOnlySearchRouting', 'fallbackProviderLabel'];
const usageCapability = { id: 'account-quota-composer-usage', required: true,
  evidenceScope: 'synthetic-quota-and-public-remote-ui-contracts-not-live-account-access',
  signedOutNetworkRegressionDeclared: true, lifecycleRegressionDeclared: true };
const signedOut = { usageTriggerCount: 0, accountUsageTextCount: 0, usageSurfaceAbsent: true,
  hostQuotaRequestInstrumentation: 'not-available-in-packaged-smoke' };
const phases = ['initial', 'restart'];
// Independently reviewed original alpha.33 tuple. Receipts, environment and callers cannot choose this policy.
// Matches Core's copilot-usage-client-policy.ts; unknown tuples need a new original-artifact review.
const reviewedCopilot33 = {
  schemaVersion: 1, type: 'githubRelease', owner: 'cloga', repo: 'dsh-github-copilot',
  tag: 'v0.4.0-alpha.33', asset: 'dsh-github-copilot-0.4.0-alpha.33.tgz', assetId: 578199183,
  packageName: 'dsh-github-copilot', version: '0.4.0-alpha.33', size: 724820,
  sha256: 'b293d40351f2e732969bac88c3906280b50c47a011bbeac1dc68bc4a8b0de480',
  integrity: 'sha512-fMONh2Thsu3YTv26DnGWFDlNg2vx3tYE6Cqm4/Aq5LmLwJo71weRZHTkJpRnenDbWkzcu4yNmk7u+GUJxb0bQw==',
  targetCommit: 'aa90fe434da8b2172faa1446afa0a0fd006afe00', dependencyRegistry: 'https://packagefeedproxy.microsoft.io/npm/',
  checksumManifest: { format: 'sha256sums', asset: 'SHA256SUMS', assetId: 578199206,
    url: 'https://github.com/cloga/dsh-github-copilot/releases/download/v0.4.0-alpha.33/SHA256SUMS', size: 104,
    sha256: 'f81df10b7fd6e40b2319a42de1f04c3b7f7eccc57809b51623c9145f2a3df076',
    integrity: 'sha512-KFNap+UgDynhZycHuHOdd/hbPL/0VR+AdKPP6cebS5IENSJG+g4zo4NtGoCpWMTrTEgqvrlyWCK4MZkzjtzeDQ==' },
};
function reviewedPositiveClient(source, digest) {
  equal(source, reviewedCopilot33);
  need(digest === '6d6a7df36c377b7485b31d45511a8b582f5b745a1030a7f6e4c35a181ad52435');
}
const proofV2 = lock => lock.components.desktop.releaseChannel.nativeProvisioning.packagedAcceptance?.format === 'combined-suite-v2';
const positiveTransport = 'not-provided-to-isolated-fixture';
const positiveTrue = ['sessionSubscribed', 'removedSessionHidesUsage', 'otherProviderHidesUsage', 'clientDisposalRemovesUsage',
  'applicationMountPreserved', 'syntheticSiblingPreserved', 'inheritedSessionScopeVerified', 'explicitUndefinedSessionScopeAbsent',
  'removedSessionRestoresUsage', 'closedSessionHidesUsage', 'closedSessionRestoresUsage', 'restoredProviderShowsUsage',
  'subscriptionsReleased', 'syntheticContextDisposed'];
function positiveCases(cases) {
  need(Array.isArray(cases) && cases.length === 2);
  for (const [index, provider] of ['github-copilot', 'github-copilot-preview'].entries()) {
    const value = cases[index];
    exact(value, ['scope', 'provider', 'usageText', 'quotaReads', 'selectorErrors', 'forbiddenRemoteCalls', 'hostTransport', ...positiveTrue]);
    need(value.scope === 'packaged-renderer-released-client-synthetic-session-and-quota' && value.provider === provider &&
      value.hostTransport === positiveTransport && typeof value.usageText === 'string' && value.usageText.length <= 256 &&
      /(?:^|[^0-9.])7\s+used(?![A-Za-z])/u.test(value.usageText) && /(?:^|[^0-9.])13\s+left(?![A-Za-z0-9])/u.test(value.usageText) && value.quotaReads === 4 &&
      value.selectorErrors === 0 && value.forbiddenRemoteCalls === 0);
    flags(value, positiveTrue);
  }
}
function positiveUsage(lock, root, accepted) {
  const record = read(root, 'positive-usage.json', undefined, 64 * 1024); const value = record.value;
  exact(value, ['runtimeSha256', 'installedClientSha256', 'pluginSource', 'cases', 'originalSignedOutApplicationRestored', 'hostTransport']);
  need(value.runtimeSha256 === lock.components.desktop.installedRuntimeDescriptor.sha256 &&
    value.originalSignedOutApplicationRestored === true && value.hostTransport === positiveTransport &&
    accepted.positiveUsageHostTransport === positiveTransport);
  reviewedPositiveClient(value.pluginSource, value.installedClientSha256);
  equal(value.pluginSource, accepted.plugin); positiveCases(value.cases); equal(value.cases, accepted.positiveCopilotUsage);
  return record.sha256;
}

function read(root, file, digest, maximum = 32 * 1024 * 1024) {
  const path = physical(join(root, file), 'file');
  const fd = openSync(path, 'r');
  try {
    const before = fstatSync(fd);
    need(before.isFile() && before.size > 0 && before.size <= maximum);
    const bytes = readFileSync(fd); const after = fstatSync(fd);
    need(bytes.length === before.size && after.size === before.size && after.mtimeMs === before.mtimeMs);
    const hash = sha256(bytes);
    if (digest !== undefined) need(hashValid(digest) && hash === digest);
    let value; try { value = JSON.parse(bytes.toString('utf8').replace(/^\uFEFF/u, '')); } catch { need(false); }
    need(object(value)); return { value, sha256: hash, bytes };
  } finally { closeSync(fd); }
}
function absent(root, file) { need(lstatSync(join(root, file), { throwIfNoEntry: false }) === undefined); }

// Selection belongs to the independently reviewed caller lock, never receipt filenames.
export function usesCombinedPackagedEvidence(lock) {
  const channel = lock.components.desktop.releaseChannel;
  const proof = channel.nativeProvisioning.packagedAcceptance;
  if (channel.upstreamVersion !== '0.1.6-alpha.2') { need(proof === undefined); return false; }
  exact(proof, ['schemaVersion', 'format', 'suiteSha256', 'qualificationSha256', 'runId', 'runAttempt', 'workflowRunSha256', 'workflowJobSha256']);
  need(proof.schemaVersion === 1 && ['combined-suite-v1', 'combined-suite-v2'].includes(proof.format) && positive(proof.runId) && positive(proof.runAttempt));
  for (const key of ['suiteSha256', 'qualificationSha256', 'workflowRunSha256', 'workflowJobSha256']) need(hashValid(proof[key]));
  return true;
}
function expectedIdentity(lock, run) {
  const desktop = lock.components.desktop; const channel = desktop.releaseChannel;
  need(positive(run.runId) && positive(run.runAttempt));
  const expected = { sourceCommit: desktop.source.commit, sourceTree: desktop.source.tree, runId: run.runId, runAttempt: run.runAttempt,
    planSha256: channel.build.planSha256, runtimeSha256: desktop.installedRuntimeDescriptor.sha256,
    executableSha256: desktop.installedExecutable.sha256, provisioningSha256: channel.nativeProvisioning.plan.sha256,
    capabilitySha256: channel.nativeProvisioning.capabilitySha256 };
  for (const key of ['sourceCommit', 'sourceTree']) need(typeof expected[key] === 'string' && /^[a-f0-9]{40}$/u.test(expected[key]));
  for (const key of identityKeys.slice(5)) need(hashValid(expected[key]));
  return expected;
}
function identity(value, expected, evidenceId) {
  need(uuid(value.evidenceId) && (evidenceId === undefined || value.evidenceId === evidenceId));
  for (const [key, leaf] of Object.entries(expected)) equal(value[key], leaf);
}
function functional(value, lock, expected, ordinary = false) {
  const v2 = proofV2(lock);
  exact(value, v2 ? [...functionalKeys, 'positiveCopilotUsage', 'positiveUsageHostTransport'] : functionalKeys); identity(value, expected);
  const desktop = lock.components.desktop;
  need(value.schemaVersion === (v2 ? 2 : 1) && value.scope === (ordinary ? 'packaged-acceptance' : 'packaged-functional-observations'));
  if (v2) { positiveCases(value.positiveCopilotUsage); need(value.positiveUsageHostTransport === positiveTransport); }
  flags(value, [...functionalTrue, 'functionalAssertionsCompleted'], functionalFalse);
  need(value.normalAcceptanceCompleted === ordinary && value.cleanupVerified === ordinary);
  need(value.desktopVersion === desktop.version && value.runtimeVersion === desktop.releaseChannel.upstreamVersion);
  need(value.transport === 'official Web-backed Desktop Host with packaged Electron dsh-app origin bridge');
  need(value.hostQuotaNoNetworkEvidence === 'immutable-plugin-ci-regression-only');
  equal(value.copilotUsageCapability, usageCapability); equal(value.signedOutCopilotUsage, [signedOut, signedOut]);
  need(hashValid(value.restartReceiptSha256) && Array.isArray(value.versionMenus) && value.versionMenus.length === 2);
  need(Array.isArray(value.timeline) && value.timeline.length <= 32);
  let previous = -1;
  const events = value.timeline.map(row => {
    exact(row, ['event', 'milliseconds']);
    need(typeof row.milliseconds === 'number' && Number.isFinite(row.milliseconds) && row.milliseconds >= previous);
    previous = row.milliseconds; return row.event;
  });
  const steps = ['launch', 'version-menu', 'application', 'account', 'usage-readonly', 'settings-readonly', 'packaged-graph', 'closed'];
  if (v2) {
    const expected = ['package-identity'];
    for (const phase of phases) for (const step of steps) {
      expected.push(`${phase}:${step}`);
      if (step === 'application' && events.includes(`${phase}:provider-deferred`)) expected.push(`${phase}:provider-deferred`);
      if (phase === 'restart' && step === 'packaged-graph') expected.push('restart:positive-usage');
    }
    equal(events, expected);
  } else {
    equal(events.filter(event => !phases.some(phase => event === `${phase}:provider-deferred`)),
      ['package-identity', ...phases.flatMap(phase => steps.map(step => `${phase}:${step}`))]);
  }
}

/** Alpha.2 phase semantics; fresh menus are observed, not compared to another run's window IDs. */
export function verifyPackagedPhaseEvidence(lock, accepted, directory) {
  const desktop = lock.components.desktop; const channel = desktop.releaseChannel; const native = channel.nativeProvisioning;
  need(channel.upstreamVersion === '0.1.6-alpha.2' && native.settingsAcceptance?.schemaVersion === 2 && native.usageAcceptance?.schemaVersion === 1);
  flags(accepted, functionalTrue, functionalFalse);
  equal(accepted.copilotUsageCapability, usageCapability); equal(accepted.signedOutCopilotUsage, [signedOut, signedOut]);
  need(accepted.hostQuotaNoNetworkEvidence === 'immutable-plugin-ci-regression-only');
  let providers;
  for (const [index, phase] of phases.entries()) {
    need(hashValid(native.settingsAcceptance[`${phase}Sha256`]) &&
      hashValid(native.settingsAcceptance[`${phase}VersionMenuSha256`]) && hashValid(native.usageAcceptance[`${phase}Sha256`]));
    const settings = read(directory, `${phase}-settings-readonly.json`, native.settingsAcceptance[`${phase}Sha256`]).value;
    exact(settings, [...settingsTrue, 'registeredSearchProviders', 'realSearch']); flags(settings, settingsTrue, ['realSearch']);
    const ids = settings.registeredSearchProviders;
    need(Array.isArray(ids) && ids.every(id => typeof id === 'string' && id.length > 0) && new Set(ids).size === ids.length && ids.includes('github-copilot-hosted'));
    if (providers !== undefined) equal(ids, providers); providers = ids;
    const menu = read(directory, `${phase}-version-menu.json`).value;
    exact(menu, ['applicationMenuLabel', 'aboutMenuLabel', 'desktopVersion', 'windowId', 'popupCount', 'aboutDispatchCount', 'nativePopupOpened', 'nativeModalOpened']);
    need(['Application', '应用'].includes(menu.applicationMenuLabel) && menu.desktopVersion === desktop.version &&
      menu.aboutMenuLabel === `${menu.applicationMenuLabel === '应用' ? '关于' : 'About'} Desktop ${desktop.version}…` &&
      Number.isSafeInteger(menu.windowId) && menu.windowId > 0 && menu.popupCount === 1 && menu.aboutDispatchCount === 1);
    flags(menu, [], ['nativePopupOpened', 'nativeModalOpened']); equal(menu, accepted.versionMenus?.[index]);
    const usage = read(directory, `${phase}-usage-readonly.json`, native.usageAcceptance[`${phase}Sha256`]).value;
    equal(usage, { capability: usageCapability, signedOut });
  }
}

function packagedFiles(lock, root, accepted, formal = true) {
  const desktop = lock.components.desktop; const channel = desktop.releaseChannel; const native = channel.nativeProvisioning;
  const records = {};
  const take = (label, file, digest) => { const result = read(root, file, digest); records[label] = result.sha256; return result.value; };
  const runtime = read(root, 'desktop-runtime.json', desktop.installedRuntimeDescriptor.sha256);
  validateDescriptor(runtime.bytes, runtime.sha256, channel.upstreamVersion); records['packaged.runtime'] = runtime.sha256;
  const plan = take('packaged.provisioning', 'provisioning-plan.json', native.plan.sha256);
  if (formal) equal(plan, read(root, 'desktop-provisioning.json', native.plan.sha256).value);
  need(plan.plugins?.length === 1 && plan.plugins[0].required === true); equal(accepted.plugin, plan.plugins[0].source);
  equal(take('packaged.capability', 'capability.json', native.capabilitySha256), channel.managedCapability);
  const executable = take('packaged.executable', 'executable.json');
  exact(executable, ['file', 'sha256', 'productVersion', 'companyName', 'productName', 'fileDescription', 'signature']);
  need(executable.file === desktop.installedExecutable.relativePath && executable.sha256 === desktop.installedExecutable.sha256 &&
    executable.productVersion === `${desktop.version.split('-')[0]}.0` && executable.signature === 'NotSigned' &&
    executable.productName === channel.identity.productName && executable.fileDescription === channel.identity.productName);
  verifyPackagedPhaseEvidence(lock, accepted, root);
  if (proofV2(lock)) records['packaged.positiveUsage'] = positiveUsage(lock, root, accepted);
  let previousGraph;
  for (const phase of phases) {
    for (const [suffix, label] of [['settings-readonly', 'settings'], ['version-menu', 'menu'], ['usage-readonly', 'usage']]) {
      take(`packaged.${phase}.${label}`, `${phase}-${suffix}.json`,
        formal && label === 'menu' ? native.settingsAcceptance[`${phase}VersionMenuSha256`] : undefined);
    }
    const graph = take(`packaged.${phase}.graph`, `${phase}-packaged-graph.json`);
    exact(graph, ['valid', 'runtimeSha256', 'executable', 'nodeVersion', 'electronVersion', 'runAsNode', 'nodePath',
      'nodeOptionsPresent', 'electronNoAsarPresent', 'cwd', 'profile', 'runtimeRoot', 'resolutionMode']);
    flags(graph, ['valid'], ['nodeOptionsPresent', 'electronNoAsarPresent']);
    need(graph.runtimeSha256 === runtime.sha256 && graph.nodePath === null && graph.runAsNode === '1' && graph.resolutionMode === 'runtime' &&
      graph.nodeVersion === runtime.value.release.nodeVersion && typeof graph.electronVersion === 'string' && /^\d+\.\d+\.\d+$/u.test(graph.electronVersion) &&
      typeof graph.executable === 'string' && win32.isAbsolute(graph.executable) && win32.basename(graph.executable) === desktop.installedExecutable.relativePath &&
      typeof graph.runtimeRoot === 'string' && win32.normalize(graph.runtimeRoot) === win32.join(win32.dirname(graph.executable), 'resources', 'app.asar', 'dsh') &&
      typeof graph.profile === 'string' && win32.isAbsolute(graph.profile) && /[\\/]profiles[\\/]desktop$/u.test(graph.profile) && graph.cwd === graph.profile);
    if (previousGraph !== undefined) equal(graph, previousGraph); previousGraph = graph;
    const store = take(`packaged.${phase}.receipts`, `${phase}-desktop-plugin-receipts.json`, accepted.restartReceiptSha256);
    exact(store, ['schemaVersion', 'receipts', 'owners']); need(store.schemaVersion === 1);
    const name = plan.plugins[0].source.packageName; exact(store.receipts, [name]); exact(store.owners, [name]); need(store.owners[name] === 'release');
    const receipt = store.receipts[name]; equal(receipt.source, plan.plugins[0].source);
    need(receipt.schemaVersion === 1 && receipt.packageName === name && receipt.version === accepted.plugin.version &&
      receipt.artifactSha256 === accepted.plugin.sha256 && receipt.assetId === accepted.plugin.assetId &&
      receipt.releaseId === lock.components.copilotIntegration.package.artifact.releaseId);
    equal(receipt.states, { staged: true, health: 'passed', activated: true, rolledBack: false, verified: true });
    equal(receipt.capability, native.buildReceiptCompatibility.capability);
    const state = take(`packaged.${phase}.provisioning`, `${phase}-desktop-plugin-provisioning-state.json`);
    need(state.schemaVersion === 1 && state.planSha256 === native.plan.planSha256 && state.composition === 'active');
    flags(state, ['verified'], ['rolledBack']); equal(state.removed, []);
    equal(state.capability, channel.managedCapability.provisioning.capability);
    equal(state.plugins, [{ name, version: accepted.plugin.version, required: true, status: 'active', source: accepted.plugin, receipt }]);
    const profile = take(`packaged.${phase}.profile`, `${phase}-package.json`);
    need(profile.name === '@deepseek-ai/dsh-desktop-runtime' && profile.private === true &&
      profile.dependencies?.[name] === `file:.desktop-plugin-artifacts/${accepted.plugin.sha256}.tgz` &&
      Array.isArray(profile.dsh?.profile?.bundles) && profile.dsh.profile.bundles.includes(name));
  }
  return records;
}

function verifyWorkflow(lock, root, proof) {
  const channel = lock.components.desktop.releaseChannel;
  const run = read(root, 'core-qualification/workflow-run.json', proof.workflowRunSha256).value;
  const job = read(root, 'core-qualification/workflow-job.json', proof.workflowJobSha256).value;
  need(Number.isSafeInteger(run.id) && String(run.id) === proof.runId && Number.isSafeInteger(run.run_attempt) && String(run.run_attempt) === proof.runAttempt &&
    run.head_sha === lock.components.desktop.source.commit && run.repository?.full_name === 'cloga/deepseek-harness' &&
    run.path === '.github/workflows/desktop-fork-release.yml' && run.event === 'workflow_dispatch' && run.status === 'completed' && run.conclusion === 'success' &&
    run.html_url === `https://github.com/cloga/deepseek-harness/actions/runs/${proof.runId}` && channel.build.runUrl === run.html_url &&
    channel.build.attempt === run.run_attempt);
  need(Number.isSafeInteger(job.id) && job.id > 0 && job.run_id === run.id && job.run_attempt === run.run_attempt && job.head_sha === run.head_sha &&
    job.name === 'Build unsigned fork installer' && job.status === 'completed' && job.conclusion === 'success' &&
    Array.isArray(job.steps) && job.steps.length <= 1000 && job.steps.every(object));
  for (const name of ['Verify packaged Copilot account and restart', 'Verify real installed Desktop upgrade', 'Verify complete release qualification']) {
    const matches = job.steps.filter(step => step.name === name);
    need(matches.length === 1 && matches[0].status === 'completed' && matches[0].conclusion === 'success' &&
      Number.isSafeInteger(matches[0].number) && matches[0].number > 0);
  }
}

function installedSettings(value, baseline = false) {
  const yes = baseline ? ['modelRolesViewLoaded', 'searchProviderCatalogLoaded'] : settingsTrue;
  exact(value, [...yes, 'registeredSearchProviders', 'realSearch']); flags(value, yes, ['realSearch']);
  const ids = value.registeredSearchProviders;
  need(Array.isArray(ids) && ids.every(id => typeof id === 'string' && id.length > 0) &&
    new Set(ids).size === ids.length && ids.includes('github-copilot-hosted'));
}
function archivedInstalledEvidence(lock, directory, summary) {
  const root = join(directory, 'core-qualification', 'installed'); physical(root, 'directory');
  const take = (file, input) => read(root, file, summary.inputs[input]).value;
  const desktop = lock.components.desktop;
  const acquisition = take('acquisition.json', 'baseline.acquisition');
  exact(acquisition, ['schemaVersion', 'releaseId', 'immutable', 'tag', 'sourceCommit', 'manifestSha256', 'installerSha256', 'receiptSha256', 'installerExecuted']);
  need(acquisition.schemaVersion === 1 && Number.isSafeInteger(acquisition.releaseId) && acquisition.releaseId > 0 &&
    typeof acquisition.sourceCommit === 'string' && /^[a-f0-9]{40}$/u.test(acquisition.sourceCommit) &&
    typeof acquisition.tag === 'string' && /^dsh-desktop-v\d+\.\d+\.\d+-[A-Za-z0-9.-]+$/u.test(acquisition.tag));
  flags(acquisition, ['immutable'], ['installerExecuted']);
  for (const [field, input] of [['manifestSha256', 'baseline.manifest'], ['installerSha256', 'baseline.installer'], ['receiptSha256', 'baseline.receipt']]) equal(acquisition[field], summary.inputs[input]);
  const upgrade = take('installer-upgrade.json', 'upgrade.result');
  const upgradeTrue = ['succeeded', 'installerUpgradeVerified', 'runningApplicationRefusalVerified', 'sameCustomPathVerified',
    'actualInstalledHostAndClientVerified', 'candidateRestartVerified', 'retainedHomeFileVerified', 'separateSameVersionPackagedPluginAcceptanceVerified'];
  const upgradeFalse = ['pluginUserChoicesVerified', 'draftAttachmentRefusalVerified', 'promotionFailureRollbackVerified', 'managedHandoffVerified', 'postSuccessDowngradeVerified'];
  exact(upgrade, ['schemaVersion', 'sourceCommit', ...upgradeTrue, ...upgradeFalse, 'installationRoot', 'baselineProcessBinding', 'cleanupErrors', 'secondaryErrors', 'failure']);
  need(upgrade.schemaVersion === 1 && upgrade.sourceCommit === desktop.source.commit);
  flags(upgrade, upgradeTrue, upgradeFalse); equal(upgrade.cleanupErrors, []); equal(upgrade.secondaryErrors, []); need(upgrade.failure === null);
  const processFlags = ['pathAvailable', 'providerNormalized', 'directParentMatches', 'basenameMatches', 'hashMatches'];
  exact(upgrade.baselineProcessBinding, processFlags); flags(upgrade.baselineProcessBinding, processFlags);
  // Observed hosted paths remain original evidence, never paths to open or rewrite on this machine.
  need(typeof upgrade.installationRoot === 'string' && win32.isAbsolute(upgrade.installationRoot) &&
    win32.basename(upgrade.installationRoot) === desktop.releaseChannel.identity.packageName &&
    win32.basename(win32.dirname(upgrade.installationRoot)) === 'Installed App');
  let retainedEnvSha256;
  for (const phase of ['baseline', 'candidate', 'candidate-restart']) {
    absent(root, `${phase}-failure.json`);
    const value = take(`${phase}.json`, `upgrade.${phase}`);
    const yes = ['actualInstalledApplication', 'sameRetainedHome', 'isolatedUserData'];
    const no = ['pluginUserChoicesVerified', 'draftAttachmentRefusalVerified', 'realOAuth', 'realModelRound', 'managedHandoffVerified'];
    exact(value, ['sourceCommit', 'version', 'executableSha256', 'runtimeSha256', ...yes, ...no, 'actualHostSettingsViews', 'retainedEnvSha256']);
    flags(value, yes, no);
    for (const key of ['executableSha256', 'runtimeSha256', 'retainedEnvSha256']) need(hashValid(value[key]));
    if (phase === 'baseline') {
      need(value.sourceCommit === acquisition.sourceCommit && acquisition.tag === `dsh-desktop-v${value.version}`);
      retainedEnvSha256 = value.retainedEnvSha256;
    } else {
      need(value.sourceCommit === desktop.source.commit && value.version === desktop.version &&
        value.executableSha256 === desktop.installedExecutable.sha256 && value.runtimeSha256 === desktop.installedRuntimeDescriptor.sha256);
      equal(value.retainedEnvSha256, retainedEnvSha256);
    }
    installedSettings(value.actualHostSettingsViews, phase === 'baseline');
  }
  const cleanupFlags = ['ownedHomeRemoved', 'ownedElectronDataRemoved', 'isolatedPackageAcceptanceDataRemoved'];
  const cleanup = take('profile-cleanup.json', 'upgrade.cleanup'); exact(cleanup, cleanupFlags); flags(cleanup, cleanupFlags);
  const packages = take('package-acceptance.json', 'upgrade.packages');
  const packageTrue = ['succeeded', 'preparedGraphVerified', 'declinePreservedGraphVerified', 'discardPreservedGraphVerified',
    'liveDraftAttachmentVetoVerified', 'attachmentOnlyVetoVerified', 'draftOnlyVetoVerified', 'consentGraphPromotionVerified',
    'newHostGenerationVerified', 'installedDisabledAfterConsentVerified', 'enabledFixtureRunningAfterSeparateRestartVerified',
    'copilotDisabledChoiceAcrossRestartVerified', 'copilotRemovalChoiceAcrossRestartVerified', 'zeroModelRequestsVerified', 'cleanupVerified'];
  const packageFalse = ['newlyInstalledTargetHealthyAtFirstConsent', 'verifiedGithubReleaseReceiptForFixture', 'choicesAcrossInstallerUpgradeVerified',
    'draftPersistedAcrossQuitVerified', 'promotionFailureRollbackVerified', 'managedHandoffVerified'];
  exact(packages, ['schemaVersion', 'sourceCommit', 'scope', ...packageTrue, ...packageFalse, 'checkpoints', 'shellIncarnations', 'pageErrors', 'cleanupErrors', 'secondaryErrors']);
  need(packages.schemaVersion === 1 && packages.sourceCommit === desktop.source.commit && packages.scope === 'candidate-installed-desktop-same-version-isolated-home');
  flags(packages, packageTrue, packageFalse);
  for (const key of ['pageErrors', 'cleanupErrors', 'secondaryErrors']) equal(packages[key], []);
  need(Array.isArray(packages.checkpoints) && packages.checkpoints.length > 0 &&
    Array.isArray(packages.shellIncarnations) && packages.shellIncarnations.length > 0);
  for (const shell of packages.shellIncarnations) {
    flags(shell, ['launchReturned', 'bound', 'exited', 'launcherExited']);
    need(Number.isSafeInteger(shell.pid) && shell.pid > 0 && Number.isSafeInteger(shell.launcherPid) && shell.launcherPid > 0 && uuid(shell.launchId));
  }
}

/** Read original formal combined receipts; unavailable installed root records remain CI-attested, not offline-replayed. */
export function readCombinedPackagedEvidence(lock, directory) {
  need(usesCombinedPackagedEvidence(lock)); physical(directory, 'directory'); absent(directory, 'acceptance.json');
  const desktop = lock.components.desktop; const channel = desktop.releaseChannel; const native = channel.nativeProvisioning;
  const proof = native.packagedAcceptance; const expected = expectedIdentity(lock, proof);
  // The declared execution must also be the run recorded by the original public metadata.
  equal(read(directory, 'release.json', channel.manifestRawSha256).value.build, channel.build);
  equal(read(directory, 'build-receipt.json', channel.buildReceipt.sha256).value.buildInputs, channel.build);
  const suite = read(directory, 'packaged-suite.json', proof.suiteSha256);
  exact(suite.value, ['schemaVersion', 'scope', ...identityKeys, 'functionalAssertionsCompleted', 'errorPropagationVerified', 'cleanupVerified', 'normalAcceptanceCompleted', 'receipts']);
  need(suite.value.schemaVersion === 1 && suite.value.scope === 'packaged-functional-with-unexpected-observer-failure');
  flags(suite.value, ['functionalAssertionsCompleted', 'errorPropagationVerified', 'cleanupVerified'], ['normalAcceptanceCompleted']);
  identity(suite.value, expected); exact(suite.value.receipts, ['functional', 'failure', 'observer']);
  const receipts = {};
  for (const [key, file] of [['functional', 'functional-results.json'], ['failure', 'failure.json'], ['observer', 'observer-cleanup.json']]) {
    const binding = suite.value.receipts[key]; exact(binding, ['file', 'sha256']); need(binding.file === file && hashValid(binding.sha256));
    receipts[key] = read(directory, file, binding.sha256); identity(receipts[key].value, expected, suite.value.evidenceId);
  }
  const f = receipts.functional.value; functional(f, lock, expected);
  const failure = receipts.failure.value;
  exact(failure, ['schemaVersion', 'scope', ...identityKeys, 'error', 'cleanupCompleted', 'cleanupVerified', 'cleanupErrors', 'diagnosticErrors'],
    ['visibleText', 'stderrTail', 'stderrTruncated', 'timeline', 'profileFilesPresentBeforeCleanup', 'realOAuth', 'realModelRound', 'realSearch', 'verificationNavigationExercised', 'manualVerificationAddressObserved']);
  need(failure.schemaVersion === 2 && failure.scope === 'packaged-acceptance-failure' && typeof failure.error === 'string' &&
    /^Error: packaged observer cleanup canary [a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/u.test(failure.error));
  flags(failure, ['cleanupCompleted', 'cleanupVerified']); equal(failure.cleanupErrors, []); equal(failure.diagnosticErrors, []);
  for (const key of ['realOAuth', 'realModelRound', 'realSearch', 'verificationNavigationExercised', 'manualVerificationAddressObserved']) {
    if (Object.hasOwn(failure, key)) need(failure[key] === false);
  }
  for (const key of ['visibleText', 'stderrTail']) if (Object.hasOwn(failure, key)) need(typeof failure[key] === 'string' && failure[key].length <= 131072);
  if (Object.hasOwn(failure, 'stderrTruncated')) need(typeof failure.stderrTruncated === 'boolean');
  if (Object.hasOwn(failure, 'profileFilesPresentBeforeCleanup')) {
    exact(failure.profileFilesPresentBeforeCleanup, ['package.json', 'desktop-plugin-receipts.json', 'desktop-plugin-provisioning-state.json']);
    need(Object.values(failure.profileFilesPresentBeforeCleanup).every(value => typeof value === 'boolean'));
  }
  if (failure.timeline !== undefined) {
    need(Array.isArray(failure.timeline)); equal(failure.timeline.slice(0, -1), f.timeline);
    const last = failure.timeline.at(-1); exact(last, ['event', 'milliseconds']);
    need(last.event === 'failure' && Number.isFinite(last.milliseconds) && last.milliseconds >= f.timeline.at(-1).milliseconds);
  }
  const observer = receipts.observer.value;
  const observerFlags = ['observerInvokedOnce', 'errorPropagationVerified', 'ordinaryAcceptanceWithheld', 'cleanupVerified', 'ownedHomeRemoved', 'ownedProfileRemoved', 'ownedLegacySdkRemoved'];
  exact(observer, ['schemaVersion', 'scope', ...identityKeys, ...observerFlags, 'normalAcceptanceCompleted', 'functionalSha256', 'failureSha256']);
  need(observer.schemaVersion === 3 && observer.scope === 'unexpected-observer-failure-cleanup');
  flags(observer, observerFlags, ['normalAcceptanceCompleted']);
  equal(observer.functionalSha256, receipts.functional.sha256); equal(observer.failureSha256, receipts.failure.sha256);
  const hashes = packagedFiles(lock, directory, f);
  const helper = read(directory, 'helper-acceptance.json'); equal(helper.value, native.helperAcceptance);
  need(helper.value.helperSha256 === native.helperSha256 && helper.value.isolatedBootstrap === 'passed' && helper.value.nodePath === null && helper.value.nodeOptions === null &&
    helper.value.manifestTransport === 'synthetic fetch only; receipt and installer requests forbidden');
  flags(helper.value, ['validSyntheticHandoffAcknowledged', 'cancellationCompleted'], ['liveHandoff', 'installerStarted']);
  hashes['packaged.helper'] = helper.sha256;
  for (const key of ['functional', 'failure', 'observer']) hashes[`packaged.${key}`] = receipts[key].sha256;
  hashes['packaged.suite'] = suite.sha256;
  Object.assign(hashes, { plan: channel.build.planSha256, 'candidate.manifest': channel.manifestRawSha256,
    'candidate.receipt': channel.buildReceipt.sha256, 'candidate.installer': desktop.artifact.sha256, 'candidate.provisioning': native.plan.sha256 });
  const summary = read(directory, 'core-qualification/qualification.json', proof.qualificationSha256).value;
  exact(summary, ['schemaVersion', 'scope', 'sourceCommit', 'sourceTree', 'runId', 'runAttempt', 'version', 'sequence', 'inputs',
    'packagedFunctionalVerified', 'unexpectedObserverFailureCleanupVerified', 'actualInstalledUpgradeVerified', 'sameVersionPackageAcceptanceVerified', 'normalPackagedAcceptanceCompleted', 'limits']);
  need(summary.schemaVersion === 1 && summary.scope === 'ci-only-fork-qualification' && summary.version === desktop.version && summary.sequence === channel.sequence);
  for (const key of ['sourceCommit', 'sourceTree', 'runId', 'runAttempt']) equal(summary[key], expected[key]);
  flags(summary, ['packagedFunctionalVerified', 'unexpectedObserverFailureCleanupVerified', 'actualInstalledUpgradeVerified', 'sameVersionPackageAcceptanceVerified'], ['normalPackagedAcceptanceCompleted']);
  equal(summary.limits, { helperTransport: 'synthetic fetch only; receipt and installer requests forbidden', liveHandoff: false,
    menuObservation: 'intercepted-model-and-dispatch-not-native-popup-or-modal', realOAuth: false, realModelRound: false, realSearch: false, liveAccountQuota: false,
    choicesAcrossInstallerUpgradeVerified: false, promotionFailureRollbackVerified: false, managedHandoffVerified: false, postSuccessDowngradeVerified: false });
  // Only unavailable root/baseline inputs remain CI-attested. Archived installed records must independently pass below.
  const ciOnly = ['baselinePin', 'baseline.manifest', 'baseline.receipt', 'baseline.installer', 'upgrade.owner', 'upgrade.validated', 'upgrade.retained'];
  const archived = ['baseline.acquisition', 'upgrade.result', 'upgrade.baseline', 'upgrade.candidate', 'upgrade.candidate-restart', 'upgrade.cleanup', 'upgrade.packages'];
  exact(summary.inputs, [...Object.keys(hashes), ...ciOnly, ...archived]);
  for (const value of Object.values(summary.inputs)) need(hashValid(value));
  for (const [key, digest] of Object.entries(hashes)) equal(summary.inputs[key], digest);
  archivedInstalledEvidence(lock, directory, summary);
  verifyWorkflow(lock, directory, proof);
  return f;
}

/** Fresh Ops ordinary owner evidence uses Ops run identity, never the formal Core run's identity. */
export function verifyFreshOrdinaryPackagedEvidence(lock, directory, run) {
  need(usesCombinedPackagedEvidence(lock)); physical(directory, 'directory');
  for (const file of ['failure.json', 'observer-cleanup.json', 'packaged-suite.json']) absent(directory, file);
  const expected = expectedIdentity(lock, run);
  const provisional = read(directory, 'functional-results.json').value;
  const accepted = read(directory, 'acceptance.json').value;
  functional(provisional, lock, expected); functional(accepted, lock, expected, true);
  equal(accepted, { ...provisional, scope: 'packaged-acceptance', normalAcceptanceCompleted: true, cleanupVerified: true });
  // Acquisition already bound the public plan. Validate the owner's original fresh phase files, not formal paths/window IDs.
  packagedFiles(lock, directory, accepted, false);
  return accepted;
}
