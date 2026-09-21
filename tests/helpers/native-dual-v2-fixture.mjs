// INERT GENERATED DATA ONLY. Core 9ca7cc3 contract preparation, not runtime or release evidence.
// Keep the historical factories/files unchanged; all writes belong to test-owned temp roots.
import { cpSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { dualPackagedFixture } from './native-packaged-fixture.mjs';
import { reviewedCopilot35, reviewedClient35 } from '../../tools/native-dual-v2-evidence.mjs';
import { sha256 } from '../../tools/native-runtime-integrity.mjs';

const phases = ['initial', 'restart'];
const identityKeys = ['evidenceId', 'sourceCommit', 'sourceTree', 'runId', 'runAttempt', 'planSha256',
  'runtimeSha256', 'executableSha256', 'provisioningSha256', 'capabilitySha256'];
const nativeEvents = ['seeded', 'launch', 'application', 'observed', 'closed'];
const canonical = value => Array.isArray(value) ? `[${value.map(canonical).join(',')}]` :
  value !== null && typeof value === 'object' ? `{${Object.keys(value).sort().map(key => `${JSON.stringify(key)}:${canonical(value[key])}`).join(',')}}` : JSON.stringify(value);
const clone = value => structuredClone(value);
const primaryAndCanary = ['', 'canary/'];

function settings(providers) {
  return { schemaVersion: 3, accountViewLoaded: true, retiredModelRolesAbsent: true,
    searchProviderCatalogLoaded: true, providerOnlySearchRouting: true, fallbackProviderLabel: true,
    registeredSearchProviders: [...providers], realSearch: false };
}
function seed() {
  return { sessionId: 'desktop-inline-composer-synthetic',
    scope: 'test-owned-persisted-session-with-synthetic-history-and-token-counts',
    workspaceRegistered: true, provider: 'github-copilot', seederModelCalls: 0, liveAccountQuota: false };
}
function geometry(offset) {
  const style = { fontSize: '13px', lineHeight: '20px', color: 'rgb(120, 120, 120)' };
  return [1280, 400].map(width => ({ viewportWidth: width,
    dock: { x: 10 + offset, y: 100 + offset, width: width - 40, height: width === 1280 ? 30 : 70 },
    time: { x: 20 + offset, y: 105 + offset, width: 60, height: 20 },
    usage: { x: 90 + offset, y: 105 + offset, width: 100, height: 20 },
    // Narrow layout deliberately wraps; do not require cross-run or wide/narrow equality.
    copilot: { x: (width === 1280 ? 200 : 20) + offset, y: (width === 1280 ? 105 : 140) + offset, width: 130, height: 20 },
    nativeStyle: clone(style), copilotStyle: clone(style) }));
}
function nativeProof(functional, seedSha256, offset) {
  return { schemaVersion: 2, scope: 'actual-packaged-native-composer-and-released-client',
    ...Object.fromEntries(identityKeys.map(key => [key, functional[key]])), seedSha256,
    sessionHistory: 'synthetic-persisted-in-isolated-home', quota: 'signed-out-host-response-no-credentials',
    pluginSource: clone(functional.plugin), installedClientSha256: reviewedClient35, geometry: geometry(offset),
    nativeDialogs: Object.fromEntries(['time', 'usage'].map(key => [key, { opened: true, closedOnEscape: true, focusReturned: true }])),
    copilotDialog: { signedOutObserved: true, sessionCreditsCount: 0, resetCount: 0, epochTextCount: 0, focusReturned: true },
    rendererErrors: [], realModelRound: false, realOAuth: false };
}
function io(directory) {
  const digest = file => sha256(readFileSync(join(directory, file)));
  const get = file => JSON.parse(readFileSync(join(directory, file), 'utf8'));
  const put = (file, value) => {
    const path = join(directory, file); mkdirSync(dirname(path), { recursive: true });
    writeFileSync(path, JSON.stringify(value)); return digest(file);
  };
  return { directory, get, put, digest };
}

// Repair only raw-byte/embedding edges, NEVER semantic identity/source/schema/value fields.
// Set embed=false to preserve an intentional embedded-vs-file mismatch. More selective
// embedSettings/embedNative/embedPositive options override that default individually.
// Set seedEdge=false for a stale seed edge attack; failureTimeline=false preserves an
// independently mutated failure timeline. With all options false this is hash-only sealing.
function sealFamily(f, prefix, options) {
  const { get, put, digest } = f;
  const embed = options.embed ?? true;
  const native = get(`${prefix}native-composer-geometry.json`);
  if (options.seedEdge ?? true) {
    native.seedSha256 = digest(`${prefix}native-composer-seed.json`);
    put(`${prefix}native-composer-geometry.json`, native);
  }
  const positive = get(`${prefix}positive-usage.json`);
  for (const name of ['functional-results.json', ...(prefix ? [] : ['acceptance.json'])]) {
    const value = get(prefix + name);
    if (options.embedSettings ?? embed) value.settingsAcceptance = phases.map(phase => get(`${prefix}${phase}-settings-readonly.json`));
    if (options.embedNative ?? embed) value.nativeComposer = clone(native);
    if (options.embedPositive ?? embed) {
      value.positiveCopilotUsage = clone(positive.cases);
      value.positiveUsageHostTransport = positive.hostTransport;
    }
    if (options.receiptEdge ?? true) value.restartReceiptSha256 = digest(`${prefix}initial-desktop-plugin-receipts.json`);
    put(prefix + name, value);
  }
  if (prefix && (options.failureTimeline ?? true)) {
    const failure = get(`${prefix}failure.json`);
    const functional = get(`${prefix}functional-results.json`);
    // Preserve the failure tail (including attacks on its event/time), replace only its prefix.
    failure.timeline = [...functional.timeline, failure.timeline.at(-1)];
    put(`${prefix}failure.json`, failure);
  }
}

/** Close v2 owned raw/embedded/hash edges without correcting a caller's semantic mutations. */
export function resealDualV2Fixture(f, options = {}) {
  for (const prefix of primaryAndCanary) sealFamily(f, prefix, options);
  const { lock, get, put, digest } = f;
  const channel = lock.components.desktop.releaseChannel, native = channel.nativeProvisioning;
  if (options.phasePins ?? true) {
    for (const phase of phases) {
      native.settingsAcceptance[`${phase}Sha256`] = digest(`${phase}-settings-readonly.json`);
      native.settingsAcceptance[`${phase}VersionMenuSha256`] = digest(`${phase}-version-menu.json`);
      native.usageAcceptance[`${phase}Sha256`] = digest(`${phase}-usage-readonly.json`);
      native.ancestorIsolation[`${phase}GraphSha256`] = digest(`${phase}-packaged-graph.json`);
    }
  }
  // Historical seal covers all original 45 summary labels, observer/suite raw hashes,
  // ordinary/ancestor pins and authenticated-API metadata pins; it preserves semantics.
  f.sealDualV1Hashes();
  const summary = get('core-qualification/qualification.json');
  for (const [label, file] of [
    ['ordinary.initial.settings', 'initial-settings-readonly.json'],
    ['ordinary.restart.settings', 'restart-settings-readonly.json'],
    ['ordinary.nativeComposer', 'native-composer-geometry.json'],
    ['ordinary.nativeComposerSeed', 'native-composer-seed.json'],
    ['packaged.nativeComposer', 'canary/native-composer-geometry.json'],
    ['packaged.nativeComposerSeed', 'canary/native-composer-seed.json'],
  ]) summary.inputs[label] = digest(file);
  // Public files can be deliberately mutated by tests; hash their actual bytes, not
  // recreated canonical payloads. Self hashes and semantic fields remain the caller's responsibility.
  summary.inputs['candidate.manifest'] = channel.manifestRawSha256 = digest('release.json');
  summary.inputs['candidate.receipt'] = channel.buildReceipt.sha256 = digest('build-receipt.json');
  summary.inputs['candidate.provisioning'] = native.plan.sha256 = digest('desktop-provisioning.json');
  native.packagedAcceptance.qualificationSha256 = put('core-qualification/qualification.json', summary);
  return f;
}

/** New explicit v2 family layered on the unchanged inert dual-v1 factory. */
export function createDualV2Fixture(t) {
  const base = dualPackagedFixture(t);
  const f = { ...base, sealDualV1Hashes: base.seal };
  const { lock, get, put, digest } = f;
  const desktop = lock.components.desktop, channel = desktop.releaseChannel, native = channel.nativeProvisioning;
  const source = clone(reviewedCopilot35);
  const plugin = lock.components.copilotIntegration;
  plugin.source.commit = source.targetCommit;
  plugin.package.version = source.version;
  Object.assign(plugin.package.artifact, { releaseId: 392975357, releaseImmutable: true, assetId: source.assetId,
    name: source.asset, version: source.version, size: source.size, sha256: source.sha256, integrity: source.integrity,
    releaseTag: source.tag, releaseCommit: source.targetCommit,
    url: `https://github.com/${source.owner}/${source.repo}/releases/download/${source.tag}/${source.asset}`,
    checksumManifest: clone(source.checksumManifest) });
  // No production lock/version claim: only this existing factory's temp-owned clone changes.
  const plan = { schemaVersion: 1, mode: 'exact', plugins: [{ required: true, source }] };
  native.plan.sha256 = put('desktop-provisioning.json', plan);
  native.plan.planSha256 = sha256(JSON.stringify(plan));
  channel.managedCapability.provisioning.planSha256 = native.plan.planSha256;
  native.capabilitySha256 = put('capability.json', channel.managedCapability);
  native.buildReceiptCompatibility.provisioning = clone(channel.managedCapability.provisioning);
  native.settingsAcceptance.schemaVersion = 3;
  native.packagedAcceptance.format = 'dual-ordinary-canary-v2';
  delete native.usagePositiveAcceptance;

  for (const [family, prefix] of primaryAndCanary.entries()) {
    put(`${prefix}provisioning-plan.json`, plan);
    put(`${prefix}capability.json`, channel.managedCapability);
    const providers = ['deepseek-official', 'github-copilot-hosted', family ? 'inert-canary-provider' : 'inert-primary-provider'];
    for (const phase of phases) {
      put(`${prefix}${phase}-settings-readonly.json`, settings(providers));
      const store = get(`${prefix}${phase}-desktop-plugin-receipts.json`);
      const receipt = store.receipts[source.packageName];
      Object.assign(receipt, { source: clone(source), releaseId: 392975357, assetId: source.assetId,
        version: source.version, artifactSha256: source.sha256 });
      put(`${prefix}${phase}-desktop-plugin-receipts.json`, store);
      const state = get(`${prefix}${phase}-desktop-plugin-provisioning-state.json`);
      state.planSha256 = native.plan.planSha256;
      state.plugins = [{ name: source.packageName, version: source.version, required: true, status: 'active', source: clone(source), receipt }];
      put(`${prefix}${phase}-desktop-plugin-provisioning-state.json`, state);
      const profile = get(`${prefix}${phase}-package.json`);
      profile.dependencies[source.packageName] = `file:.desktop-plugin-artifacts/${source.sha256}.tgz`;
      put(`${prefix}${phase}-package.json`, profile);
    }
    const functional = get(`${prefix}functional-results.json`);
    Object.assign(functional, { schemaVersion: 3, plugin: clone(source), provisioningSha256: native.plan.sha256,
      capabilitySha256: native.capabilitySha256 });
    delete functional.modelRolesViewLoaded;
    delete functional.currentWorkspaceReadOnly;
    if (family) functional.evidenceId = 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee';
    for (const event of nativeEvents) functional.timeline.push({ event: `native-composer:${event}`, milliseconds: 0 });
    functional.timeline.forEach((row, index) => { row.milliseconds = index * (family ? 3 : 2); });
    put(`${prefix}functional-results.json`, functional);
    const positive = get(`${prefix}positive-usage.json`);
    positive.pluginSource = clone(source); positive.installedClientSha256 = reviewedClient35;
    for (const observation of positive.cases) observation.usageText = 'Credits · 7 used · 13 left';
    put(`${prefix}positive-usage.json`, positive);
    const seedHash = put(`${prefix}native-composer-seed.json`, seed());
    put(`${prefix}native-composer-geometry.json`, nativeProof(functional, seedHash, family * 4));
    if (!family) put('acceptance.json', { ...functional, scope: 'packaged-acceptance', normalAcceptanceCompleted: true, cleanupVerified: true });
    else {
      for (const name of ['failure.json', 'observer-cleanup.json', 'packaged-suite.json']) {
        const value = get(prefix + name);
        for (const key of identityKeys) value[key] = functional[key];
        if (name === 'failure.json') value.timeline = [...functional.timeline, { event: 'failure', milliseconds: functional.timeline.at(-1).milliseconds + 1 }];
        put(prefix + name, value);
      }
    }
  }
  const receipt = get('build-receipt.json');
  receipt.pluginCompatibility = native.buildReceiptCompatibility;
  Object.assign(receipt.artifacts, { capabilitySha256: native.capabilitySha256,
    provisioning: { file: 'desktop-provisioning.json', sha256: native.plan.sha256, planSha256: native.plan.planSha256 } });
  delete receipt.receiptSha256; receipt.receiptSha256 = sha256(canonical(receipt));
  channel.buildReceipt.receiptSha256 = receipt.receiptSha256;
  channel.buildReceipt.sha256 = put('build-receipt.json', receipt);
  const manifest = get('release.json');
  manifest.buildReceipt = { file: channel.buildReceipt.file, sha256: channel.buildReceipt.sha256, receiptSha256: receipt.receiptSha256 };
  delete manifest.manifestSha256; manifest.manifestSha256 = sha256(canonical(manifest));
  channel.manifestSha256 = manifest.manifestSha256;
  channel.manifestRawSha256 = put('release.json', manifest);
  const summary = get('core-qualification/qualification.json'); summary.schemaVersion = 2;
  put('core-qualification/qualification.json', summary);
  // Historical baseline stays byte-for-byte as inherited; only candidate phases retire roles.
  for (const phase of ['candidate', 'candidate-restart']) {
    const file = `core-qualification/installed/${phase}.json`, value = get(file);
    value.actualHostSettingsViews = settings(['deepseek-official', 'github-copilot-hosted', 'inert-installed-provider']);
    put(file, value);
  }
  f.seal = options => resealDualV2Fixture(f, options);
  f.fresh = () => {
    const directory = mkdtempSync(join(tmpdir(), 'ops-inert-dual-v2-fresh-'));
    t.after(() => rmSync(directory, { recursive: true, force: true }));
    const files = ['desktop-runtime.json', 'provisioning-plan.json', 'capability.json', 'executable.json',
      'positive-usage.json', 'functional-results.json', 'acceptance.json', 'native-composer-geometry.json', 'native-composer-seed.json',
      ...phases.flatMap(phase => ['settings-readonly', 'version-menu', 'usage-readonly', 'packaged-graph',
        'desktop-plugin-receipts', 'desktop-plugin-provisioning-state', 'package'].map(suffix => `${phase}-${suffix}.json`))];
    for (const file of files) cpSync(join(f.directory, file), join(directory, file));
    const fresh = { ...io(directory), run: { runId: '456', runAttempt: '3' } };
    const functional = fresh.get('functional-results.json');
    Object.assign(functional, { ...fresh.run, evidenceId: '22222222-3333-4444-8555-666666666666' });
    functional.timeline.forEach((row, index) => { row.milliseconds = index * 5; });
    for (const [index, phase] of phases.entries()) {
      const menu = fresh.get(`${phase}-version-menu.json`); menu.windowId = 200 + index;
      functional.versionMenus[index] = menu; fresh.put(`${phase}-version-menu.json`, menu);
      fresh.put(`${phase}-settings-readonly.json`, settings(['deepseek-official', 'github-copilot-hosted', 'inert-fresh-provider']));
      const graph = fresh.get(`${phase}-packaged-graph.json`);
      graph.profile = 'C:\\inert-fresh-v2\\profiles\\desktop'; graph.cwd = graph.profile;
      fresh.put(`${phase}-packaged-graph.json`, graph);
    }
    fresh.put('functional-results.json', functional);
    fresh.put('acceptance.json', { ...functional, scope: 'packaged-acceptance', normalAcceptanceCompleted: true, cleanupVerified: true });
    fresh.put('native-composer-geometry.json', nativeProof(functional, fresh.digest('native-composer-seed.json'), 8));
    fresh.seal = (options = {}) => { sealFamily(fresh, '', options); return fresh; };
    fresh.seal(); return fresh;
  };
  return f.seal();
}
