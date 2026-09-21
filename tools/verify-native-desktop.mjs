import { createHash } from 'node:crypto';
import { lstatSync, readFileSync, readdirSync, realpathSync } from 'node:fs';
import { createRequire } from 'node:module';
import { dirname, isAbsolute, join, relative, resolve, sep, win32 } from 'node:path';
import { pathToFileURL } from 'node:url';
import { isDeepStrictEqual } from 'node:util';
import { nativeLayout, preflightAsar, runAsarProbe } from './native-asar-runtime.mjs';
import { hashFile, physical } from './native-runtime-integrity.mjs';
import { readNativeProfileMetadata } from './native-profile-metadata.mjs';
import { usesCombinedPackagedEvidence, readCombinedPackagedEvidence } from './native-packaged-evidence.mjs';

const fail = (code) => { throw new Error(code); };
const requireValue = (condition, code) => { if (!condition) fail(code); };
const sha256 = (bytes) => createHash('sha256').update(bytes).digest('hex');
const json = (path) => JSON.parse(readFileSync(path, 'utf8'));
const object = (value) => value !== null && typeof value === 'object' && !Array.isArray(value);
const sourceKeys = ['schemaVersion', 'type', 'owner', 'repo', 'tag', 'asset', 'assetId',
  'packageName', 'version', 'size', 'sha256', 'integrity', 'targetCommit', 'dependencyRegistry', 'checksumManifest'];
const checksumKeys = ['format', 'asset', 'assetId', 'url', 'size', 'sha256', 'integrity'];
const receiptCapability = { id: 'desktopNativeVerifiedRelease', schemaVersion: 1, sourceSchemaVersion: 1, receiptSchemaVersion: 1 };
const provisioningCapability = { id: 'desktopNativePluginProvisioning', schemaVersion: 1,
  planSchemaVersion: 1, stateSchemaVersion: 1, pluginCapability: receiptCapability };

function noLinks(path) {
  let current = resolve(path);
  for (;;) {
    requireValue(!lstatSync(current).isSymbolicLink(), 'native-reparse-path');
    const parent = dirname(current);
    if (parent === current) break;
    current = parent;
  }
  return path;
}

function child(root, path) {
  requireValue(typeof path === 'string' && path !== '' && !isAbsolute(path) && !/[\\:]/u.test(path) &&
    !path.split('/').some((part) => ['', '.', '..'].includes(part)), 'native-invalid-relative-path');
  return noLinks(join(root, ...path.split('/')));
}

function ordered(value, keys) {
  requireValue(object(value) && Object.keys(value).every((key) => keys.includes(key)), 'native-invalid-source-shape');
  return Object.fromEntries(keys.filter((key) => Object.hasOwn(value, key)).map((key) => [key, value[key]]));
}

function canonicalPlan(value) {
  requireValue(object(value) && Object.keys(value).sort().join(',') === 'mode,plugins,schemaVersion' &&
    value.schemaVersion === 1 && value.mode === 'exact' && Array.isArray(value.plugins), 'native-invalid-plan');
  return { schemaVersion: 1, mode: 'exact', plugins: value.plugins.map((entry) => {
    requireValue(object(entry) && Object.keys(entry).sort().join(',') === 'required,source' &&
      typeof entry.required === 'boolean', 'native-invalid-plan-entry');
    const source = ordered(entry.source, sourceKeys);
    source.checksumManifest = ordered(source.checksumManifest, checksumKeys);
    return { required: entry.required, source };
  }) };
}

function canonical(value) {
  if (Array.isArray(value)) return `[${value.map(canonical).join(',')}]`;
  if (object(value)) return `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${canonical(value[key])}`).join(',')}}`;
  return JSON.stringify(value);
}

export function verifyNativeReleaseEvidence(lock, directory) {
  const desktop = lock.components.desktop;
  const channel = desktop.releaseChannel;
  const native = channel.nativeProvisioning;
  const combined = usesCombinedPackagedEvidence(lock);
  const read = (name, hash) => {
    const bytes = readFileSync(join(directory, name));
    requireValue(sha256(bytes) === hash, 'native-release-file-hash-mismatch');
    return JSON.parse(bytes);
  };
  const manifest = read('release.json', channel.manifestRawSha256);
  const receipt = read('build-receipt.json', channel.buildReceipt.sha256);
  const capability = read('capability.json', native.capabilitySha256);
  const helper = json(join(directory, 'helper-acceptance.json'));
  requireValue(receipt.artifacts.helperSha256 === native.helperSha256 &&
    helper.helperSha256 === native.helperSha256 &&
    isDeepStrictEqual(helper, native.helperAcceptance) &&
    helper.isolatedBootstrap === 'passed' && helper.validSyntheticHandoffAcknowledged === true &&
    helper.cancellationCompleted === true && helper.nodePath === null && helper.nodeOptions === null &&
    helper.liveHandoff === false && helper.installerStarted === false,
  'native-release-helper-mismatch');
  const plan = canonicalPlan(read('desktop-provisioning.json', native.plan.sha256));
  for (const [value, key] of [[manifest, 'manifestSha256'], [receipt, 'receiptSha256']]) {
    const { [key]: hash, ...payload } = value;
    requireValue(sha256(canonical(payload)) === hash, 'native-release-self-hash-mismatch');
  }
  requireValue(manifest.manifestSha256 === channel.manifestSha256 &&
    receipt.receiptSha256 === channel.buildReceipt.receiptSha256 &&
    isDeepStrictEqual(manifest.buildReceipt, { file: channel.buildReceipt.file, sha256: channel.buildReceipt.sha256,
      receiptSha256: channel.buildReceipt.receiptSha256 }) &&
    isDeepStrictEqual(manifest.source, channel.source) &&
    receipt.source.commit === desktop.source.commit && receipt.source.tree === desktop.source.tree &&
    receipt.source.tag === desktop.source.releaseTag && receipt.source.version === desktop.version &&
    manifest.version === desktop.version && manifest.sequence === channel.sequence,
  'native-release-source-mismatch');
  requireValue(manifest.installer.file === desktop.artifact.name &&
    manifest.installer.bytes === desktop.artifact.size && manifest.installer.sha256 === desktop.artifact.sha256 &&
    manifest.installer.sha512 === desktop.artifact.sha512 &&
    isDeepStrictEqual(manifest.installer, receipt.artifacts.installer) &&
    manifest.installedEvidence.executableSha256 === desktop.installedExecutable.sha256 &&
    manifest.installedEvidence.runtimeSha256 === desktop.installedRuntimeDescriptor.sha256 &&
    receipt.artifacts.executableSha256 === desktop.installedExecutable.sha256 &&
    receipt.artifacts.runtimeSha256 === desktop.installedRuntimeDescriptor.sha256,
  'native-release-installed-identity-mismatch');
  // The old update client requires false here; startup provisioning belongs to the receipt/capability.
  requireValue(manifest.pluginCompatibility.automaticProvisioning === false &&
    isDeepStrictEqual(manifest.pluginCompatibility, channel.pluginCompatibility) &&
    isDeepStrictEqual(manifest.pluginCompatibility.capability, receiptCapability) &&
    receipt.pluginCompatibility.automaticProvisioning === true &&
    isDeepStrictEqual(receipt.pluginCompatibility, native.buildReceiptCompatibility) &&
    isDeepStrictEqual(receipt.pluginCompatibility.capability, receiptCapability) &&
    isDeepStrictEqual(capability, channel.managedCapability) &&
    isDeepStrictEqual(receipt.pluginCompatibility.provisioning, capability.provisioning) &&
    isDeepStrictEqual(capability.provisioning.capability, provisioningCapability),
  'native-release-capability-mismatch');
  const planSha256 = sha256(JSON.stringify(plan));
  requireValue(planSha256 === native.plan.planSha256 && planSha256 === capability.provisioning.planSha256 &&
    receipt.artifacts.provisioning.planSha256 === planSha256 &&
    receipt.artifacts.provisioning.file === native.plan.name &&
    receipt.artifacts.provisioning.sha256 === native.plan.sha256 &&
    receipt.artifacts.capabilitySha256 === native.capabilitySha256,
  'native-release-plan-mismatch');
  const plugin = lock.components.copilotIntegration;
  const isolation = native.ancestorIsolation;
  const acceptance = combined ? readCombinedPackagedEvidence(lock, directory) : read('acceptance.json', isolation.acceptanceSha256);
  requireValue(acceptance.sourceCommit === desktop.source.commit &&
    acceptance.desktopVersion === desktop.version && acceptance.runtimeVersion === channel.upstreamVersion &&
    acceptance.ancestorSdkJunction === true && acceptance.ancestorSdkLoaded === false &&
    acceptance.actualGraphVerified === true && acceptance.accountEntryVisible === true &&
    acceptance.realOAuth === false && acceptance.realModelRound === false &&
    acceptance.installerUpgradeVerified === false &&
    isDeepStrictEqual(acceptance.plugin, plan.plugins[0].source),
  'native-release-ancestor-isolation-mismatch');
  // New paired releases carry exact read-only settings proof. Legacy fixtures
  // remain historical; exact alpha.2 requires this gate regardless of sequence.
  // The combined adapter already validates alpha.2's full settings/menu/usage graph.
  if (!combined && (native.settingsAcceptance !== undefined ||
    (channel.upstreamVersion === '0.1.6-alpha.1' && channel.sequence >= 12))) {
    const settingsProof = native.settingsAcceptance;
    requireValue(object(settingsProof) && (settingsProof.schemaVersion === undefined || settingsProof.schemaVersion === 2) &&
      acceptance.modelRolesViewLoaded === true && acceptance.searchProviderCatalogLoaded === true &&
      acceptance.realSearch === false, 'native-release-settings-mismatch');
    const providerNavigation = settingsProof.schemaVersion === 2;
    if (providerNavigation) {
      requireValue(acceptance.manageCompatibilityDisclosureAbsent === true &&
        acceptance.providerOnlySearchRouting === true && acceptance.realOAuth === false &&
        acceptance.verificationNavigationExercised === false &&
        acceptance.manualVerificationAddressObserved === false &&
        acceptance.realModelRound === false && acceptance.realSearch === false,
      'native-release-settings-mismatch');
    }
    const phases = [['initial', settingsProof.initialSha256, settingsProof.initialVersionMenuSha256],
      ['restart', settingsProof.restartSha256, settingsProof.restartVersionMenuSha256]];
    let providers; const versionMenus = [];
    for (const [phase, digest, versionDigest] of phases) {
      const settings = read(`${phase}-settings-readonly.json`, digest);
      const ids = settings.registeredSearchProviders;
      requireValue(settings.modelRolesViewLoaded === true && settings.searchProviderCatalogLoaded === true &&
        settings.realSearch === false && Array.isArray(ids) && ids.every(id => typeof id === 'string' && id.length > 0) &&
        new Set(ids).size === ids.length && ids.includes('github-copilot-hosted') &&
        (providers === undefined || isDeepStrictEqual(providers, ids)) &&
        (!providerNavigation || (settings.currentWorkspaceReadOnly === true &&
          settings.providerOnlySearchRouting === true && settings.fallbackProviderLabel === true)),
      'native-release-settings-mismatch');
      providers = ids;
      if (providerNavigation) {
        const versionMenu = read(`${phase}-version-menu.json`, versionDigest);
        requireValue(versionMenu.applicationMenuLabel === 'Application' &&
          versionMenu.aboutMenuLabel === `About Desktop ${desktop.version}…` &&
          versionMenu.desktopVersion === desktop.version && versionMenu.aboutDispatchCount === 1 &&
          versionMenu.nativeModalOpened === false &&
          (versionMenus.length === 0 || isDeepStrictEqual(versionMenus[0], versionMenu)),
        'native-release-settings-mismatch');
        versionMenus.push(versionMenu);
      }
    }
    if (providerNavigation) requireValue(isDeepStrictEqual(acceptance.versionMenus, versionMenus), 'native-release-settings-mismatch');
  }
  if (!combined && native.usageAcceptance !== undefined) {
    const proof = native.usageAcceptance;
    const capability = acceptance.copilotUsageCapability;
    requireValue(object(proof) && proof.schemaVersion === 1 && object(capability) &&
      capability.id === 'account-quota-composer-usage' && capability.required === true &&
      capability.evidenceScope === 'synthetic-quota-and-public-remote-ui-contracts-not-live-account-access' &&
      capability.signedOutNetworkRegressionDeclared === true && capability.lifecycleRegressionDeclared === true &&
      acceptance.hostQuotaNoNetworkEvidence === 'immutable-plugin-ci-regression-only' &&
      acceptance.liveAccountQuota === false && Array.isArray(acceptance.signedOutCopilotUsage) &&
      acceptance.signedOutCopilotUsage.length === 2 && Array.isArray(acceptance.timeline),
    'native-release-usage-mismatch');
    const observations = [];
    for (const [phase, digest] of [['initial', proof.initialSha256], ['restart', proof.restartSha256]]) {
      const usage = read(`${phase}-usage-readonly.json`, digest);
      requireValue(isDeepStrictEqual(usage.capability, capability) && object(usage.signedOut) &&
        usage.signedOut.usageTriggerCount === 0 && usage.signedOut.accountUsageTextCount === 0 &&
        usage.signedOut.usageSurfaceAbsent === true &&
        usage.signedOut.hostQuotaRequestInstrumentation === 'not-available-in-packaged-smoke',
      'native-release-usage-mismatch');
      observations.push(usage.signedOut);
      const events = acceptance.timeline.map(entry => entry?.event);
      requireValue(events.indexOf(`${phase}:account`) >= 0 &&
        events.indexOf(`${phase}:usage-readonly`) > events.indexOf(`${phase}:account`),
      'native-release-usage-mismatch');
    }
    requireValue(isDeepStrictEqual(acceptance.signedOutCopilotUsage, observations), 'native-release-usage-mismatch');
  }
  for (const [file, hash] of [['initial-packaged-graph.json', isolation.initialGraphSha256],
    ['restart-packaged-graph.json', isolation.restartGraphSha256]]) {
    const graph = read(file, hash);
    requireValue(graph.valid === true && graph.runtimeSha256 === desktop.installedRuntimeDescriptor.sha256 &&
      graph.nodePath === null && graph.nodeOptionsPresent === false, 'native-release-ancestor-graph-mismatch');
    if (nativeLayout(lock) === 'asar-runtime') {
      // Actual .6 source fixture records packaged graph inventory/Node-mode facts;
      // it no longer emits the legacy google/sdk lookup object. Host/UI ancestor
      // acceptance above and the separate genuine Ops resolver proof own that evidence.
      requireValue(graph.resolutionMode === 'runtime' && graph.runAsNode === '1' && graph.electronNoAsarPresent === false &&
        typeof graph.nodeVersion === 'string' && /^\d+\.\d+\.\d+$/u.test(graph.nodeVersion) &&
        typeof graph.electronVersion === 'string' && /^\d+\.\d+\.\d+$/u.test(graph.electronVersion) &&
        typeof graph.executable === 'string' && win32.isAbsolute(graph.executable) &&
        win32.basename(graph.executable) === desktop.installedExecutable.relativePath &&
        typeof graph.runtimeRoot === 'string' && win32.normalize(graph.runtimeRoot) === win32.join(win32.dirname(graph.executable), 'resources', 'app.asar', 'dsh') &&
        typeof graph.profile === 'string' && win32.isAbsolute(graph.profile) && graph.cwd === graph.profile &&
        /[\\/]profiles[\\/]desktop$/u.test(graph.profile), 'native-release-ancestor-graph-mismatch');
    } else {
      requireValue(graph.google.sdkPeerOptional === true && typeof graph.sdk.target === 'string' &&
        !graph.sdk.target.toLowerCase().startsWith(`${graph.profile.toLowerCase()}\\`), 'native-release-ancestor-graph-mismatch');
    }
  }
  requireValue(plan.plugins.length === 1 && plan.plugins[0].required === true &&
    plan.plugins[0].source.sha256 === plugin.package.artifact.sha256 &&
    plan.plugins[0].source.targetCommit === plugin.source.commit &&
    plan.plugins[0].source.version === plugin.package.version &&
    plan.plugins[0].source.assetId === plugin.package.artifact.assetId,
  'native-release-plugin-mismatch');
  return { valid: true, planSha256, automaticStartupProvisioning: true,
    legacyUpdateManifestAutomaticProvisioning: false, modelResponseVerified: false };
}

function verifyRuntime(lock, root) {
  const expected = lock.components.desktop.installedRuntimeDescriptor;
  const descriptorPath = child(root, expected.relativePath.replaceAll('\\', '/'));
  requireValue(sha256(readFileSync(descriptorPath)) === expected.sha256, 'native-runtime-descriptor-mismatch');
  const descriptor = json(descriptorPath);
  requireValue(descriptor.schemaVersion === 1 && descriptor.platform === 'win32' && descriptor.arch === 'x64' &&
    Array.isArray(descriptor.files) && descriptor.files.length > 0 && Array.isArray(descriptor.sharedPackages),
  'native-runtime-descriptor-invalid');
  const runtimeRoot = dirname(descriptorPath);
  const files = [];
  const visit = (directory) => {
    for (const entry of readdirSync(directory, { withFileTypes: true })) {
      const path = join(directory, entry.name);
      if (path === descriptorPath) continue;
      requireValue(!entry.isSymbolicLink(), 'native-runtime-reparse-entry');
      if (entry.isDirectory()) visit(path);
      else {
        requireValue(entry.isFile(), 'native-runtime-special-entry');
        const bytes = readFileSync(path);
        files.push({ path: relative(runtimeRoot, path).split(sep).join('/'), bytes: bytes.length, sha256: sha256(bytes) });
      }
    }
  };
  visit(runtimeRoot);
  files.sort((a, b) => a.path < b.path ? -1 : a.path > b.path ? 1 : 0);
  requireValue(isDeepStrictEqual(files, descriptor.files.map(({ path, bytes, sha256: hash }) => ({ path, bytes, sha256: hash }))),
    'native-runtime-tree-mismatch');
  for (const shared of descriptor.sharedPackages) {
    const metadata = json(child(runtimeRoot, `${shared.path}/package.json`));
    requireValue(metadata.name === shared.name && metadata.version === shared.version, 'native-shared-package-mismatch');
  }
  const policyPath = 'node_modules/@deepseek-ai/dsh-desktop-host/register-module-resolution-policy.mjs';
  return { valid: true, status: 'runtime-tree-verified', fileCount: files.length,
    moduleResolutionPolicyUrl: files.some(({ path }) => path === policyPath)
      ? pathToFileURL(child(runtimeRoot, policyPath)).href : null };
}

function verifyProvisioning(lock, root, home, runtimeMode = false) {
  const lockedCapability = lock.components.desktop.releaseChannel.managedCapability;
  requireValue(object(lockedCapability.provisioning), 'native-provisioning-capability-not-locked');
  const capability = json(child(root, 'resources/managed-update/capability.json'));
  requireValue(isDeepStrictEqual(capability, lockedCapability), 'native-managed-capability-mismatch');
  requireValue(sha256(readFileSync(child(root, 'resources/managed-update/helper.mjs'))) ===
    lock.components.desktop.releaseChannel.nativeProvisioning.helperSha256, 'native-helper-hash-mismatch');
  const plan = canonicalPlan(json(child(root, 'resources/desktop-provisioning/plan.json')));
  const planSha256 = sha256(JSON.stringify(plan));
  requireValue(planSha256 === capability.provisioning.planSha256 &&
    planSha256 === lock.components.desktop.releaseChannel.nativeProvisioning.plan.planSha256 &&
    isDeepStrictEqual(capability.provisioning.capability, provisioningCapability), 'native-plan-hash-mismatch');
  // The current Windows baseline has one required immutable plugin, not Web overlays.
  requireValue(plan.plugins.length === 1 && plan.plugins[0].required === true, 'native-plan-inventory-mismatch');
  const source = plan.plugins[0].source;
  // The locked plan digest attests the exact registry; receipts must preserve this source below.
  requireValue(typeof source.dependencyRegistry === 'string' && source.dependencyRegistry.length > 0,
    'native-plan-source-mismatch');
  const plugin = lock.components.copilotIntegration;
  const artifact = plugin.package.artifact;
  const checksum = artifact.checksumManifest;
  const expected = { schemaVersion: 1, type: 'githubRelease', owner: 'cloga', repo: 'dsh-github-copilot',
    tag: artifact.releaseTag, asset: artifact.name, assetId: artifact.assetId, packageName: plugin.package.name,
    version: plugin.package.version, size: artifact.size, sha256: artifact.sha256, integrity: artifact.integrity,
    targetCommit: plugin.source.commit };
  requireValue(Object.entries(expected).every(([key, value]) => source[key] === value), 'native-plan-source-mismatch');
  requireValue(source.checksumManifest.format === 'sha256sums' && source.checksumManifest.asset === checksum.name &&
    source.checksumManifest.assetId === checksum.assetId && source.checksumManifest.url === checksum.url &&
    source.checksumManifest.size === checksum.size && source.checksumManifest.sha256 === checksum.sha256,
  'native-plan-checksum-mismatch');
  const profile = noLinks(join(home, 'profiles', 'desktop'));
  // .6 permits user-owned additions, but never promotes them into the locked
  // release inventory. The legacy physical/link branch keeps its old contract.
  const profileMetadata = runtimeMode ? readNativeProfileMetadata(profile, plan) : undefined;
  const state = profileMetadata?.state ?? json(child(profile, 'desktop-plugin-provisioning-state.json'));
  const store = profileMetadata?.store ?? json(child(profile, 'desktop-plugin-receipts.json'));
  const manifest = profileMetadata?.manifest ?? json(child(profile, 'package.json'));
  requireValue(state.schemaVersion === 1 && isDeepStrictEqual(state.capability, provisioningCapability) &&
    state.planSha256 === planSha256 && state.composition === 'active' && state.rolledBack === false &&
    state.verified === true && Array.isArray(state.plugins) && state.plugins.length === 1 &&
    Array.isArray(state.removed) && state.removed.every((name) => typeof name === 'string'), 'native-provisioning-state-invalid');
  requireValue(store.schemaVersion === 1 && object(store.receipts) &&
    (runtimeMode ? Object.hasOwn(store.receipts, source.packageName) :
      isDeepStrictEqual(Object.keys(store.receipts), [source.packageName])), 'native-receipt-inventory-mismatch');
  const result = state.plugins[0];
  const receipt = store.receipts[source.packageName];
  requireValue(result.name === source.packageName && result.version === source.version && result.required === true &&
    result.status === 'active' && isDeepStrictEqual(result.source, source) &&
    isDeepStrictEqual(result.receipt, receipt), 'native-state-receipt-mismatch');
  requireValue(receipt.schemaVersion === 1 && isDeepStrictEqual(receipt.capability, receiptCapability) &&
    isDeepStrictEqual(receipt.source, source) && receipt.releaseId === artifact.releaseId &&
    receipt.assetId === artifact.assetId && receipt.packageName === source.packageName &&
    receipt.version === source.version && receipt.artifactSha256 === artifact.sha256 &&
    isDeepStrictEqual(receipt.states, { staged: true, health: 'passed', activated: true, rolledBack: false, verified: true }),
  'native-receipt-invalid');
  const bundles = manifest.dsh?.profile?.bundles;
  requireValue(manifest.name === '@deepseek-ai/dsh-desktop-runtime' && manifest.private === true &&
    typeof manifest.version === 'string' && Array.isArray(bundles) &&
    (runtimeMode ? profileMetadata !== undefined :
      isDeepStrictEqual(bundles, ['@deepseek-ai/dsh-base', '@deepseek-ai/dsh-web-app', source.packageName])) &&
    manifest.dependencies?.[source.packageName] === `file:.desktop-plugin-artifacts/${artifact.sha256}.tgz`,
  'native-profile-composition-mismatch');
  const artifactPath = child(profile, `.desktop-plugin-artifacts/${artifact.sha256}.tgz`);
  const bytes = readFileSync(artifactPath);
  requireValue(bytes.length === artifact.size && sha256(bytes) === artifact.sha256 &&
    `sha512-${createHash('sha512').update(bytes).digest('base64')}` === artifact.integrity,
  'native-local-artifact-mismatch');
  const metadata = json(child(profile, `node_modules/${source.packageName}/package.json`));
  requireValue(metadata.name === source.packageName && metadata.version === source.version, 'native-installed-package-mismatch');
  if (runtimeMode) {
    const packageRoot = physical(join(profile, 'node_modules', source.packageName), 'directory');
    return { valid: true, status: 'native-metadata-verified', planSha256, artifactPath,
      packageRoot, profileRoot: profile, packageName: source.packageName, packageVersion: source.version,
      profileManifestSha256: hashFile(join(profile, 'package.json')),
      pluginManifestSha256: hashFile(join(packageRoot, 'package.json')),
      profileMetadataSha256: profileMetadata.snapshotSha256,
      ownershipSource: profileMetadata.ownershipSource, requiredPluginOwner: profileMetadata.requiredPluginOwner,
      userExtras: profileMetadata.userExtras, sharedPeerResolution: 'pending' };
  }
  const pluginRequire = createRequire(join(profile, 'node_modules', source.packageName, 'package.json'));
  const hostRequire = createRequire(child(root, 'resources/dsh/node_modules/@deepseek-ai/dsh-desktop-host/package.json'));
  for (const peer of ['@deepseek-ai/dsh-authorization', '@deepseek-ai/schemastery']) {
    const peerRoot = realpathSync(child(root, `resources/dsh/node_modules/${peer}`));
    const hostEntry = realpathSync(hostRequire.resolve(peer));
    const pluginEntry = realpathSync(pluginRequire.resolve(peer));
    requireValue(pluginEntry === hostEntry && hostEntry.startsWith(`${peerRoot}${sep}`),
      'native-shared-peer-resolution-mismatch');
  }
  return { valid: true, status: 'native-inventory-verified', planSha256, artifactPath,
    packageRoot: join(profile, 'node_modules', source.packageName), profileRoot: profile,
    sharedPeerResolution: 'host-owned' };
}

function check(read) {
  try { return read(); }
  catch (error) {
    // File contents, raw parser errors and provider data never enter diagnostics.
    const reason = /^native-[a-z-]+$/u.test(error.message) ? error.message :
      error.code === 'ENOENT' ? 'native-evidence-missing' : 'native-evidence-unreadable';
    return { valid: false, status: 'not-ready', reason };
  }
}

export function verifyNativeDesktopFiles({ lock, installRoot, dshHome, diagnosticRoot }) {
  const layout = check(() => ({ valid: true, mode: nativeLayout(lock) }));
  let runtime; let provisioning;
  if (!layout.valid) { runtime = layout; provisioning = { valid: false, status: 'not-ready', reason: 'native-runtime-prerequisite-failed' }; }
  else if (layout.mode === 'physical-links') {
    // Preserve the legacy .5 physical/link contract. Never fall back from ASAR.
    runtime = check(() => verifyRuntime(lock, resolve(installRoot)));
    provisioning = check(() => verifyProvisioning(lock, resolve(installRoot), resolve(dshHome)));
  } else {
    let snapshot;
    runtime = check(() => {
      physical(installRoot, 'directory'); physical(dshHome, 'directory');
      snapshot = preflightAsar(lock, installRoot);
      return { valid: true, status: 'asar-preflight-verified' };
    });
    provisioning = runtime.valid ? check(() => verifyProvisioning(lock, installRoot, dshHome, true)) :
      { valid: false, status: 'not-ready', reason: 'native-runtime-prerequisite-failed' };
    if (runtime.valid && provisioning.valid) {
      runtime = check(() => {
        const result = runAsarProbe(snapshot, provisioning, dshHome, diagnosticRoot);
        // No installer mutation is allowed during CHECK; detect ordinary concurrent
        // replacements. This is not an OS-enforced anti-TOCTOU/carrier-DLL boundary.
        const after = preflightAsar(lock, installRoot);
        requireValue(after.archiveSha256 === snapshot.archiveSha256 &&
          isDeepStrictEqual(verifyProvisioning(lock, installRoot, dshHome, true), provisioning), 'native-inconsistent-snapshot');
        return { valid: true, status: 'runtime-tree-verified', mode: 'asar-runtime', fileCount: result.fileCount,
          version: snapshot.descriptor.release.version, descriptorSha256: snapshot.descriptorSha256,
          unpackedCount: snapshot.unpackedCount, runtimeRoot: snapshot.runtimeRoot, hostEntry: snapshot.hostEntry,
          carrierExecutable: snapshot.executable, executableSha256: snapshot.executableSha256,
          moduleResolutionPolicyUrl: snapshot.moduleResolutionPolicyUrl, sharedPeerResolution: result.mode };
      });
      provisioning = runtime.valid ? { ...provisioning, status: 'native-inventory-verified', sharedPeerResolution: 'host-owned' } :
        { valid: false, status: 'not-ready', reason: 'native-runtime-prerequisite-failed' };
    } else if (runtime.valid) runtime = { valid: false, status: 'not-ready', reason: 'native-provisioning-prerequisite-failed' };
  }
  return { runtime, provisioning, valid: runtime.valid && provisioning.valid, mutated: false,
    functional: { valid: false, status: 'manual-verification-required', reason: 'native-host-remote-unavailable',
      modelResponseVerified: false } };
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  let stage = 'stdin';
  try {
    // Windows native pipes may not be ready for synchronous fd reads.
    const chunks = [];
    for await (const chunk of process.stdin) chunks.push(chunk);
    stage = 'json';
    const input = JSON.parse(Buffer.concat(chunks).toString('utf8').replace(/^\uFEFF/u, ''));
    stage = 'verification';
    console.log(JSON.stringify(verifyNativeDesktopFiles(input)));
  } catch {
    console.error(`native-check-input-invalid:${stage}`);
    process.exitCode = 2;
  }
}
