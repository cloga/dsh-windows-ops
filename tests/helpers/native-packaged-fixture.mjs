// INERT GENERATED INPUTS ONLY. Never source, publication, installed upgrade or runtime evidence.
import { cpSync, mkdirSync, mkdtempSync, readFileSync, rmSync, unlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { sha256 } from '../../tools/native-runtime-integrity.mjs';
const root = fileURLToPath(new URL('../../', import.meta.url));
const canonical = value => Array.isArray(value) ? `[${value.map(canonical).join(',')}]` :
  value !== null && typeof value === 'object' ? `{${Object.keys(value).sort().map(key => `${JSON.stringify(key)}:${canonical(value[key])}`).join(',')}}` : JSON.stringify(value);
export function packagedFixture(t) {
  const lock = JSON.parse(readFileSync(join(root, 'deployments/windows-copilot.lock.json')));
  const directory = mkdtempSync(join(tmpdir(), 'ops-inert-combined-'));
  t.after(() => rmSync(directory, { recursive: true, force: true }));
  const d = lock.components.desktop; const c = d.releaseChannel; const n = c.nativeProvisioning;
  delete n.usagePositiveAcceptance; // This inert alpha.2 fixture does not exercise the optional positive contract.
  cpSync(join(root, n.fixtureRoot.replaceAll('\\', '/')), directory, { recursive: true });
  const get = file => JSON.parse(readFileSync(join(directory, file)));
  const put = (file, value) => { const path = join(directory, file); mkdirSync(dirname(path), { recursive: true }); writeFileSync(path, JSON.stringify(value)); return digest(file); };
  const digest = file => sha256(readFileSync(join(directory, file)));
  c.upstreamVersion = '0.1.6-alpha.2'; c.build.runUrl = 'https://github.com/cloga/deepseek-harness/actions/runs/123'; c.build.attempt = 2;
  const names = ['@deepseek-ai/dsh', '@deepseek-ai/dsh-desktop-host'];
  const runtime = { schemaVersion: 1, platform: 'win32', arch: 'x64',
    release: { schemaVersion: 1, version: c.upstreamVersion, hostProtocolVersion: 4, nodeVersion: '24.18.1', pnpmVersion: '11.7.0' },
    sharedPackages: names.map(name => ({ name, path: `node_modules/${name}`, version: c.upstreamVersion })),
    files: names.map(name => ({ path: `node_modules/${name}/package.json`, bytes: 0, sha256: sha256(''), executable: false })).sort((a, b) => a.path < b.path ? -1 : 1) };
  d.installedRuntimeDescriptor.sha256 = put('desktop-runtime.json', runtime);
  const receipt = get('build-receipt.json'); receipt.artifacts.runtimeSha256 = d.installedRuntimeDescriptor.sha256;
  receipt.buildInputs = c.build;
  delete receipt.receiptSha256; receipt.receiptSha256 = sha256(canonical(receipt));
  c.buildReceipt.receiptSha256 = receipt.receiptSha256; c.buildReceipt.sha256 = put('build-receipt.json', receipt);
  const manifest = get('release.json'); manifest.installedEvidence.runtimeSha256 = d.installedRuntimeDescriptor.sha256;
  manifest.build = c.build;
  manifest.buildReceipt.sha256 = c.buildReceipt.sha256; manifest.buildReceipt.receiptSha256 = c.buildReceipt.receiptSha256;
  delete manifest.manifestSha256; manifest.manifestSha256 = sha256(canonical(manifest));
  c.manifestSha256 = manifest.manifestSha256; c.manifestRawSha256 = put('release.json', manifest);
  const plan = get('desktop-provisioning.json'); cpSync(join(directory, 'desktop-provisioning.json'), join(directory, 'provisioning-plan.json'));
  put('executable.json', { file: d.installedExecutable.relativePath, sha256: d.installedExecutable.sha256,
    productVersion: `${d.version.split('-')[0]}.0`, companyName: 'inert', productName: c.identity.productName,
    fileDescription: c.identity.productName, signature: 'NotSigned' });
  const identity = { evidenceId: 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee', sourceCommit: d.source.commit, sourceTree: d.source.tree,
    runId: '123', runAttempt: '2', planSha256: c.build.planSha256, runtimeSha256: d.installedRuntimeDescriptor.sha256,
    executableSha256: d.installedExecutable.sha256, provisioningSha256: n.plan.sha256, capabilitySha256: n.capabilitySha256 };
  const capability = { id: 'account-quota-composer-usage', required: true, evidenceScope: 'synthetic-quota-and-public-remote-ui-contracts-not-live-account-access', signedOutNetworkRegressionDeclared: true, lifecycleRegressionDeclared: true };
  const signedOut = { usageTriggerCount: 0, accountUsageTextCount: 0, usageSurfaceAbsent: true, hostQuotaRequestInstrumentation: 'not-available-in-packaged-smoke' };
  const f = { schemaVersion: 1, scope: 'packaged-functional-observations', ...identity,
    functionalAssertionsCompleted: true, normalAcceptanceCompleted: false, cleanupVerified: false,
    isolatedHome: true, onboardingNoticeDismissed: true, actualGraphVerified: true, ancestorSdkJunction: true,
    accountEntryVisible: true, manageCompatibilityDisclosureAbsent: true, modelRolesViewLoaded: true, currentWorkspaceReadOnly: true,
    searchProviderCatalogLoaded: true, providerOnlySearchRouting: true, fallbackProviderLabel: true,
    ancestorSdkLoaded: false, liveAccountQuota: false, realOAuth: false, verificationNavigationExercised: false,
    manualVerificationAddressObserved: false, realModelRound: false, realSearch: false, installerUpgradeVerified: false,
    desktopVersion: d.version, runtimeVersion: c.upstreamVersion, versionMenus: [], plugin: plan.plugins[0].source,
    transport: 'official Web-backed Desktop Host with packaged Electron dsh-app origin bridge',
    restartReceiptSha256: digest('initial-desktop-plugin-receipts.json'), copilotUsageCapability: capability,
    signedOutCopilotUsage: [signedOut, signedOut], hostQuotaNoNetworkEvidence: 'immutable-plugin-ci-regression-only', timeline: [] };
  let milliseconds = 0; const event = event => f.timeline.push({ event, milliseconds: milliseconds++ }); event('package-identity');
  for (const [index, phase] of ['initial', 'restart'].entries()) {
    const menu = { applicationMenuLabel: index ? '应用' : 'Application',
      aboutMenuLabel: `${index ? '关于' : 'About'} Desktop ${d.version}…`, desktopVersion: d.version,
      windowId: index + 7, popupCount: 1, aboutDispatchCount: 1, nativePopupOpened: false, nativeModalOpened: false };
    f.versionMenus.push(menu); n.settingsAcceptance[`${phase}VersionMenuSha256`] = put(`${phase}-version-menu.json`, menu);
    n.settingsAcceptance[`${phase}Sha256`] = put(`${phase}-settings-readonly.json`, { modelRolesViewLoaded: true, currentWorkspaceReadOnly: true,
      searchProviderCatalogLoaded: true, providerOnlySearchRouting: true, fallbackProviderLabel: true,
      registeredSearchProviders: ['deepseek-official', 'github-copilot-hosted'], realSearch: false });
    n.usageAcceptance[`${phase}Sha256`] = put(`${phase}-usage-readonly.json`, { capability, signedOut });
    const graph = get(`${phase}-packaged-graph.json`); graph.runtimeSha256 = identity.runtimeSha256;
    n.ancestorIsolation[`${phase}GraphSha256`] = put(`${phase}-packaged-graph.json`, graph);
    for (const suffix of ['desktop-plugin-receipts', 'desktop-plugin-provisioning-state', 'package']) {
      if (phase === 'restart') cpSync(join(directory, `initial-${suffix}.json`), join(directory, `${phase}-${suffix}.json`));
    }
    for (const step of ['launch', 'version-menu', 'application', 'account', 'usage-readonly', 'settings-readonly', 'packaged-graph', 'closed']) event(`${phase}:${step}`);
  }
  put('functional-results.json', f); unlinkSync(join(directory, 'acceptance.json'));
  const failure = { schemaVersion: 2, scope: 'packaged-acceptance-failure', ...identity,
    error: 'Error: packaged observer cleanup canary 11111111-2222-3333-4444-555555555555',
    cleanupCompleted: true, cleanupVerified: true, cleanupErrors: [], diagnosticErrors: [],
    timeline: [...f.timeline, { event: 'failure', milliseconds }] };
  put('failure.json', failure);
  const observer = { schemaVersion: 3, scope: 'unexpected-observer-failure-cleanup', ...identity,
    observerInvokedOnce: true, errorPropagationVerified: true, ordinaryAcceptanceWithheld: true, cleanupVerified: true,
    ownedHomeRemoved: true, ownedProfileRemoved: true, ownedLegacySdkRemoved: true, normalAcceptanceCompleted: false,
    functionalSha256: digest('functional-results.json'), failureSha256: digest('failure.json') };
  put('observer-cleanup.json', observer);
  put('packaged-suite.json', { schemaVersion: 1, scope: 'packaged-functional-with-unexpected-observer-failure', ...identity,
    functionalAssertionsCompleted: true, errorPropagationVerified: true, cleanupVerified: true, normalAcceptanceCompleted: false, receipts: {} });
  const inputs = { plan: c.build.planSha256, 'candidate.manifest': c.manifestRawSha256, 'candidate.receipt': c.buildReceipt.sha256,
    'candidate.installer': d.artifact.sha256, 'candidate.provisioning': n.plan.sha256 };
  const fileMap = { 'packaged.runtime': 'desktop-runtime.json', 'packaged.provisioning': 'provisioning-plan.json', 'packaged.capability': 'capability.json',
    'packaged.executable': 'executable.json', 'packaged.helper': 'helper-acceptance.json', 'packaged.functional': 'functional-results.json',
    'packaged.failure': 'failure.json', 'packaged.observer': 'observer-cleanup.json', 'packaged.suite': 'packaged-suite.json' };
  for (const phase of ['initial', 'restart']) for (const [label, suffix] of [['settings', 'settings-readonly'], ['menu', 'version-menu'], ['usage', 'usage-readonly'],
    ['graph', 'packaged-graph'], ['receipts', 'desktop-plugin-receipts'], ['provisioning', 'desktop-plugin-provisioning-state'], ['profile', 'package']]) fileMap[`packaged.${phase}.${label}`] = `${phase}-${suffix}.json`;
  for (const name of ['baselinePin', 'baseline.manifest', 'baseline.receipt', 'baseline.installer', 'baseline.acquisition', 'upgrade.owner', 'upgrade.validated',
    'upgrade.result', 'upgrade.retained', 'upgrade.baseline', 'upgrade.candidate', 'upgrade.candidate-restart', 'upgrade.cleanup', 'upgrade.packages']) inputs[name] = sha256(`INERT CI-attested ${name}`);
  const archived = (label, file, value) => {
    const path = `core-qualification/installed/${file}`; put(path, value); fileMap[label] = path;
  };
  const baselineSource = 'b'.repeat(40), baselineVersion = '0.1.6-alpha.1.cloga.2';
  archived('baseline.acquisition', 'acquisition.json', { schemaVersion: 1, releaseId: 999, immutable: true,
    tag: `dsh-desktop-v${baselineVersion}`, sourceCommit: baselineSource, manifestSha256: inputs['baseline.manifest'],
    installerSha256: inputs['baseline.installer'], receiptSha256: inputs['baseline.receipt'], installerExecuted: false });
  archived('upgrade.result', 'installer-upgrade.json', { schemaVersion: 1, sourceCommit: d.source.commit,
    succeeded: true, installerUpgradeVerified: true, runningApplicationRefusalVerified: true, sameCustomPathVerified: true,
    actualInstalledHostAndClientVerified: true, candidateRestartVerified: true, retainedHomeFileVerified: true,
    separateSameVersionPackagedPluginAcceptanceVerified: true, pluginUserChoicesVerified: false, draftAttachmentRefusalVerified: false,
    promotionFailureRollbackVerified: false, managedHandoffVerified: false, postSuccessDowngradeVerified: false,
    installationRoot: `C:\\inert\\Installed App\\${c.identity.packageName}`,
    baselineProcessBinding: { pathAvailable: true, providerNormalized: true, directParentMatches: true, basenameMatches: true, hashMatches: true },
    cleanupErrors: [], secondaryErrors: [], failure: null });
  for (const phase of ['baseline', 'candidate', 'candidate-restart']) {
    const baseline = phase === 'baseline';
    const settings = { modelRolesViewLoaded: true, searchProviderCatalogLoaded: true,
      registeredSearchProviders: ['deepseek-official', 'github-copilot-hosted'], realSearch: false };
    if (!baseline) Object.assign(settings, { currentWorkspaceReadOnly: true, providerOnlySearchRouting: true, fallbackProviderLabel: true });
    archived(`upgrade.${phase}`, `${phase}.json`, { sourceCommit: baseline ? baselineSource : d.source.commit,
      version: baseline ? baselineVersion : d.version, executableSha256: baseline ? sha256('inert previous EXE') : d.installedExecutable.sha256,
      runtimeSha256: baseline ? sha256('inert previous runtime') : d.installedRuntimeDescriptor.sha256,
      actualInstalledApplication: true, sameRetainedHome: true, isolatedUserData: true, pluginUserChoicesVerified: false,
      draftAttachmentRefusalVerified: false, realOAuth: false, realModelRound: false, managedHandoffVerified: false,
      actualHostSettingsViews: settings, retainedEnvSha256: sha256('inert retained home') });
  }
  archived('upgrade.cleanup', 'profile-cleanup.json', { ownedHomeRemoved: true, ownedElectronDataRemoved: true, isolatedPackageAcceptanceDataRemoved: true });
  archived('upgrade.packages', 'package-acceptance.json', { schemaVersion: 1, sourceCommit: d.source.commit,
    scope: 'candidate-installed-desktop-same-version-isolated-home', succeeded: true, preparedGraphVerified: true,
    declinePreservedGraphVerified: true, discardPreservedGraphVerified: true, liveDraftAttachmentVetoVerified: true,
    attachmentOnlyVetoVerified: true, draftOnlyVetoVerified: true, consentGraphPromotionVerified: true, newHostGenerationVerified: true,
    installedDisabledAfterConsentVerified: true, enabledFixtureRunningAfterSeparateRestartVerified: true,
    copilotDisabledChoiceAcrossRestartVerified: true, copilotRemovalChoiceAcrossRestartVerified: true, zeroModelRequestsVerified: true, cleanupVerified: true,
    newlyInstalledTargetHealthyAtFirstConsent: false, verifiedGithubReleaseReceiptForFixture: false, choicesAcrossInstallerUpgradeVerified: false,
    draftPersistedAcrossQuitVerified: false, promotionFailureRollbackVerified: false, managedHandoffVerified: false,
    checkpoints: ['inert'], shellIncarnations: [{ pid: 11, launcherPid: 12, launchId: '11111111-2222-3333-4444-555555555555',
      launchReturned: true, bound: true, exited: true, launcherExited: true }], pageErrors: [], cleanupErrors: [], secondaryErrors: [] });
  const summary = { schemaVersion: 1, scope: 'ci-only-fork-qualification', sourceCommit: d.source.commit, sourceTree: d.source.tree,
    runId: '123', runAttempt: '2', version: d.version, sequence: c.sequence, inputs,
    packagedFunctionalVerified: true, unexpectedObserverFailureCleanupVerified: true, actualInstalledUpgradeVerified: true,
    sameVersionPackageAcceptanceVerified: true, normalPackagedAcceptanceCompleted: false,
    limits: { helperTransport: 'synthetic fetch only; receipt and installer requests forbidden', liveHandoff: false,
      menuObservation: 'intercepted-model-and-dispatch-not-native-popup-or-modal', realOAuth: false, realModelRound: false, realSearch: false, liveAccountQuota: false,
      choicesAcrossInstallerUpgradeVerified: false, promotionFailureRollbackVerified: false, managedHandoffVerified: false, postSuccessDowngradeVerified: false } };
  put('core-qualification/qualification.json', summary);
  const run = { id: 123, run_attempt: 2, head_sha: d.source.commit, repository: { full_name: 'cloga/deepseek-harness' },
    path: '.github/workflows/desktop-fork-release.yml', event: 'workflow_dispatch', status: 'completed', conclusion: 'success', html_url: c.build.runUrl };
  const job = { id: 789, run_id: 123, run_attempt: 2, head_sha: d.source.commit, name: 'Build unsigned fork installer', status: 'completed', conclusion: 'success',
    steps: ['Verify packaged Copilot account and restart', 'Verify real installed Desktop upgrade', 'Verify complete release qualification'].map((name, i) => ({ name, number: i + 1, status: 'completed', conclusion: 'success' })) };
  put('core-qualification/workflow-run.json', run); put('core-qualification/workflow-job.json', job);
  n.packagedAcceptance = { schemaVersion: 1, format: 'combined-suite-v1', runId: '123', runAttempt: '2' };
  const seal = () => {
    const observer = get('observer-cleanup.json'); observer.functionalSha256 = digest('functional-results.json'); observer.failureSha256 = digest('failure.json'); put('observer-cleanup.json', observer);
    const suite = get('packaged-suite.json'); suite.receipts = Object.fromEntries(['functional', 'failure', 'observer'].map(key => [key, { file: fileMap[`packaged.${key}`], sha256: digest(fileMap[`packaged.${key}`]) }]));
    n.packagedAcceptance.suiteSha256 = put('packaged-suite.json', suite);
    const summary = get('core-qualification/qualification.json'); for (const [label, file] of Object.entries(fileMap)) summary.inputs[label] = digest(file);
    n.packagedAcceptance.qualificationSha256 = put('core-qualification/qualification.json', summary);
    n.packagedAcceptance.workflowRunSha256 = digest('core-qualification/workflow-run.json'); n.packagedAcceptance.workflowJobSha256 = digest('core-qualification/workflow-job.json');
  };
  seal();
  const ordinary = () => {
    const provisional = get('functional-results.json'); provisional.runId = '456'; provisional.runAttempt = '3'; put('functional-results.json', provisional);
    put('acceptance.json', { ...provisional, scope: 'packaged-acceptance', normalAcceptanceCompleted: true, cleanupVerified: true });
    for (const file of ['failure.json', 'observer-cleanup.json', 'packaged-suite.json']) unlinkSync(join(directory, file));
    return { runId: '456', runAttempt: '3' };
  };
  return { lock, directory, get, put, digest, seal, ordinary };
}

// These are reviewed metadata leaves inside INERT proof records, not fabricated Client/package bytes.
// Passing a parser test never establishes original alpha.33 artifact parity or renderer execution.
export function packagedV2Fixture(t) {
  const f = packagedFixture(t); const { lock, get, put, digest } = f;
  const d = lock.components.desktop, c = d.releaseChannel, n = c.nativeProvisioning;
  const source = {
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
  const plugin = lock.components.copilotIntegration;
  plugin.source.commit = source.targetCommit; plugin.package.version = source.version;
  Object.assign(plugin.package.artifact, { releaseId: 392690464, assetId: source.assetId, sha256: source.sha256,
    size: source.size, integrity: source.integrity, name: source.asset, releaseTag: source.tag, releaseCommit: source.targetCommit });
  const plan = { schemaVersion: 1, mode: 'exact', plugins: [{ required: true, source }] };
  n.plan.sha256 = put('desktop-provisioning.json', plan); put('provisioning-plan.json', plan);
  n.plan.planSha256 = sha256(JSON.stringify(plan));
  c.managedCapability.provisioning.planSha256 = n.plan.planSha256;
  n.capabilitySha256 = put('capability.json', c.managedCapability);
  n.buildReceiptCompatibility.provisioning = structuredClone(c.managedCapability.provisioning);
  for (const phase of ['initial', 'restart']) {
    const store = get(`${phase}-desktop-plugin-receipts.json`); const receipt = store.receipts[source.packageName];
    Object.assign(receipt, { source, releaseId: 392690464, assetId: source.assetId, version: source.version, artifactSha256: source.sha256 });
    put(`${phase}-desktop-plugin-receipts.json`, store);
    const state = get(`${phase}-desktop-plugin-provisioning-state.json`); state.planSha256 = n.plan.planSha256;
    state.plugins = [{ name: source.packageName, version: source.version, required: true, status: 'active', source, receipt }];
    put(`${phase}-desktop-plugin-provisioning-state.json`, state);
    const profile = get(`${phase}-package.json`); profile.dependencies[source.packageName] = `file:.desktop-plugin-artifacts/${source.sha256}.tgz`;
    put(`${phase}-package.json`, profile);
  }
  const receipt = get('build-receipt.json'); receipt.pluginCompatibility = n.buildReceiptCompatibility;
  Object.assign(receipt.artifacts, { capabilitySha256: n.capabilitySha256,
    provisioning: { file: 'desktop-provisioning.json', sha256: n.plan.sha256, planSha256: n.plan.planSha256 } });
  delete receipt.receiptSha256; receipt.receiptSha256 = sha256(canonical(receipt));
  c.buildReceipt.receiptSha256 = receipt.receiptSha256; c.buildReceipt.sha256 = put('build-receipt.json', receipt);
  const manifest = get('release.json'); manifest.buildReceipt = { file: 'build-receipt.json', sha256: c.buildReceipt.sha256, receiptSha256: c.buildReceipt.receiptSha256 };
  delete manifest.manifestSha256; manifest.manifestSha256 = sha256(canonical(manifest));
  c.manifestSha256 = manifest.manifestSha256; c.manifestRawSha256 = put('release.json', manifest);
  const cases = ['github-copilot', 'github-copilot-preview'].map(provider => ({
    scope: 'packaged-renderer-released-client-synthetic-session-and-quota', provider, usageText: '7 used13 left', quotaReads: 4,
    sessionSubscribed: true, removedSessionHidesUsage: true, otherProviderHidesUsage: true, clientDisposalRemovesUsage: true,
    selectorErrors: 0, forbiddenRemoteCalls: 0, hostTransport: 'not-provided-to-isolated-fixture',
    applicationMountPreserved: true, syntheticSiblingPreserved: true, inheritedSessionScopeVerified: true,
    explicitUndefinedSessionScopeAbsent: true, removedSessionRestoresUsage: true, closedSessionHidesUsage: true,
    closedSessionRestoresUsage: true, restoredProviderShowsUsage: true, subscriptionsReleased: true, syntheticContextDisposed: true,
  }));
  const functional = get('functional-results.json');
  Object.assign(functional, { schemaVersion: 2, plugin: source, positiveCopilotUsage: cases,
    positiveUsageHostTransport: 'not-provided-to-isolated-fixture', restartReceiptSha256: digest('initial-desktop-plugin-receipts.json') });
  const closed = functional.timeline.findIndex(row => row.event === 'restart:closed');
  functional.timeline.splice(closed, 0, { event: 'restart:positive-usage', milliseconds: 0 });
  functional.timeline.forEach((row, index) => { row.milliseconds = index; });
  put('functional-results.json', functional);
  for (const file of ['functional-results.json', 'failure.json', 'observer-cleanup.json', 'packaged-suite.json']) {
    const value = get(file); value.provisioningSha256 = n.plan.sha256; value.capabilitySha256 = n.capabilitySha256;
    if (file === 'failure.json') value.timeline = [...functional.timeline, { event: 'failure', milliseconds: functional.timeline.length }];
    put(file, value);
  }
  put('positive-usage.json', { runtimeSha256: d.installedRuntimeDescriptor.sha256,
    installedClientSha256: '6d6a7df36c377b7485b31d45511a8b582f5b745a1030a7f6e4c35a181ad52435',
    pluginSource: source, cases, originalSignedOutApplicationRestored: true, hostTransport: 'not-provided-to-isolated-fixture' });
  n.packagedAcceptance.format = 'combined-suite-v2';
  const summary = get('core-qualification/qualification.json');
  Object.assign(summary.inputs, { 'candidate.manifest': c.manifestRawSha256, 'candidate.receipt': c.buildReceipt.sha256, 'candidate.provisioning': n.plan.sha256 });
  put('core-qualification/qualification.json', summary);
  const seal = () => {
    f.seal();
    const summary = get('core-qualification/qualification.json'); summary.inputs['packaged.positiveUsage'] = digest('positive-usage.json');
    n.packagedAcceptance.qualificationSha256 = put('core-qualification/qualification.json', summary);
  };
  seal(); return { ...f, seal };
}
