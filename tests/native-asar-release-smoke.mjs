// Explicit real-release automation. Importing this module never acquires or boots anything.
// Source-owned UI/restart fixture is imported ONLY after reviewed release/source/file checks.
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { createRequire } from 'node:module';
import { closeSync, lstatSync, openSync, readFileSync, readSync, readdirSync, unlinkSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { isDeepStrictEqual, parseArgs } from 'node:util';
import { nativeLayout, preflightAsar, probeEnvironment, boundedHeader, headerRuntimeInventory } from '../tools/native-asar-runtime.mjs';
import { hashFile, hashValid, inside, object, physical, relativeName, safeReason, sha256 } from '../tools/native-runtime-integrity.mjs';
import { verifyNativeReleaseEvidence, verifyPositiveUsageEvidence } from '../tools/verify-native-desktop.mjs';
import { sourceFailureDiagnostic } from '../tools/native-release-diagnostic.mjs';
import { verifyFreshOrdinaryPackagedEvidence, verifyPackagedPhaseEvidence } from '../tools/native-packaged-evidence.mjs';
import { captureOpsCaller, expectedCoreSource, invokeCoreFixture } from '../tools/native-core-fixture-caller.mjs';

const opsRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const sourceFixture = 'apps/desktop/tests/fixtures/copilot-release-smoke.ts';
const sourcePlan = 'apps/desktop/release/cloga-windows-x64.json';
const asarReader = createRequire(import.meta.url)('../tools/vendor/asar-reader/reader.cjs');
const fail = code => { throw new Error(`native-release-smoke-${code}`); };
const need = (ok, code) => { if (!ok) fail(code); };
const commit = value => typeof value === 'string' && /^[a-f0-9]{40}$/u.test(value);
const version = value => typeof value === 'string' && /^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$/u.test(value);
function readJson(path, maximum = 1024 * 1024) {
  physical(path, 'file'); need(lstatSync(path).size <= maximum, 'input-limit');
  return JSON.parse(readFileSync(path, 'utf8').replace(/^\uFEFF/u, ''));
}
function leaf(name) { relativeName(name); need(!name.includes('/'), 'asset-name-invalid'); return name; }
const entryExists = path => lstatSync(path, { throwIfNoEntry: false }) !== undefined;
function sha512File(path) {
  const fd = openSync(path, 'r');
  try {
    const hash = createHash('sha512'); const buffer = Buffer.allocUnsafe(1024 * 1024);
    for (let count; (count = readSync(fd, buffer, 0, buffer.length, null)) > 0;) hash.update(buffer.subarray(0, count));
    return hash.digest('base64');
  } finally { closeSync(fd); }
}

/** Pure pre-acquisition gate. No side effects, executable lookup, or source imports. */
export function releasePlan(lock, confirmation) {
  need(nativeLayout(lock) === 'asar-runtime', 'asar-lock-required');
  const d = lock.components.desktop; const c = d.releaseChannel; const a = d.artifact; const s = d.source;
  need(typeof confirmation === 'string' && confirmation === d.version && version(d.version) && version(c.upstreamVersion) &&
    /^0\.1\.6(?:-|$)/u.test(d.version), 'version-confirmation');
  need(s.repository === 'https://github.com/cloga/deepseek-harness' && c.owner === 'cloga/deepseek-harness' &&
    commit(s.commit) && commit(s.tree) && s.releaseTag === `dsh-desktop-v${d.version}` &&
    isDeepStrictEqual(c.source, { repository: 'cloga/deepseek-harness', commit: s.commit, tree: s.tree, tag: s.releaseTag }) &&
    c.version === d.version && a.releaseImmutable === true && Number.isSafeInteger(a.releaseId) && a.releaseId > 0,
  'locked-source-invalid');
  leaf(a.name); leaf(d.installedExecutable.relativePath);
  need(/\.exe$/iu.test(a.name) && /\.exe$/iu.test(d.installedExecutable.relativePath) &&
    a.url === `https://github.com/cloga/deepseek-harness/releases/download/${s.releaseTag}/${a.name}` &&
    c.manifestAsset === 'release.json' && c.buildReceipt.file === 'build-receipt.json' &&
    c.nativeProvisioning.plan.name === 'desktop-provisioning.json' &&
    c.sha256Sums.name === 'SHA256SUMS' && c.sha512Sums.name === 'SHA512SUMS' &&
    c.manifestUrl === `https://github.com/cloga/deepseek-harness/releases/download/${s.releaseTag}/release.json`, 'locked-artifact-invalid');
  need(typeof c.build.nodeVersion === 'string' && /^v?\d+\.\d+\.\d+$/u.test(c.build.nodeVersion) &&
    version(c.build.pnpmVersion) && hashValid(c.build.lockfileSha256) && hashValid(c.build.planSha256) &&
    hashValid(d.installedExecutable.sha256) && hashValid(d.installedRuntimeDescriptor.sha256), 'locked-toolchain-invalid');
  let registry; try { registry = new URL(c.build.packageRegistry); } catch { fail('locked-registry-invalid'); }
  need(registry.protocol === 'https:' && registry.username === '' && registry.password === '' && registry.search === '' &&
    registry.hash === '' && registry.href === c.build.packageRegistry, 'locked-registry-invalid');
  const assets = [
    { name: a.name, id: a.assetId, bytes: a.size, sha256: a.sha256 },
    { name: c.manifestAsset, id: c.manifestAssetId, sha256: c.manifestRawSha256 },
    { name: c.buildReceipt.file, id: c.buildReceipt.assetId, sha256: c.buildReceipt.sha256 },
    { name: c.sha256Sums.name, id: c.sha256Sums.assetId, bytes: c.sha256Sums.size, sha256: c.sha256Sums.sha256 },
    { name: c.sha512Sums.name, id: c.sha512Sums.assetId, bytes: c.sha512Sums.size, sha256: c.sha512Sums.sha256 },
    { name: c.nativeProvisioning.plan.name, id: c.nativeProvisioning.plan.assetId,
      bytes: c.nativeProvisioning.plan.size, sha256: c.nativeProvisioning.plan.sha256 },
  ];
  for (const item of assets) need(Number.isSafeInteger(item.id) && item.id > 0 && hashValid(item.sha256) &&
    (item.bytes === undefined || (Number.isSafeInteger(item.bytes) && item.bytes > 0 && item.bytes <= 4 * 1024 ** 3)), 'locked-asset-invalid');
  need(new Set(assets.map(x => x.id)).size === assets.length && typeof a.sha512 === 'string' &&
    /^[A-Za-z0-9+/]{86}==$/u.test(a.sha512), 'locked-asset-invalid');
  return { schemaVersion: 1, version: d.version, upstreamVersion: c.upstreamVersion,
    sourceRepository: c.owner, sourceCommit: s.commit, sourceTree: s.tree, sourceTag: s.releaseTag,
    installerName: a.name, nodeVersion: c.build.nodeVersion.replace(/^v/u, ''), pnpmVersion: c.build.pnpmVersion,
    packageRegistry: c.build.packageRegistry, assets };
}

/** Validate untrusted API responses before downloading any executable artifact. */
export function validateReleaseMetadata(lock, confirmation, release, chain) {
  const plan = releasePlan(lock, confirmation);
  need(object(release) && release.id === lock.components.desktop.artifact.releaseId && release.tag_name === plan.sourceTag &&
    release.immutable === true && release.draft === false && typeof release.prerelease === 'boolean' && Array.isArray(release.assets), 'release-metadata-invalid');
  need(object(chain) && chain.ref?.ref === `refs/tags/${plan.sourceTag}` && object(chain.ref.object) &&
    Array.isArray(chain.tags) && chain.tags.length <= 4, 'tag-evidence-invalid');
  let selected = chain.ref.object;
  for (const tag of chain.tags) {
    need(selected.type === 'tag' && commit(selected.sha) && tag.sha === selected.sha && object(tag.object), 'tag-evidence-invalid');
    selected = tag.object;
  }
  need(selected.type === 'commit' && selected.sha === plan.sourceCommit && chain.commit?.sha === plan.sourceCommit &&
    chain.commit?.tree?.sha === plan.sourceTree, 'tag-source-mismatch');
  for (const expected of plan.assets) {
    const matches = release.assets.filter(a => a.id === expected.id || a.name === expected.name);
    need(matches.length === 1, 'asset-metadata-invalid');
    const actual = matches[0];
    need(actual.id === expected.id && actual.name === expected.name && actual.state === 'uploaded' &&
      Number.isSafeInteger(actual.size) && actual.size > 0 && actual.size <= (expected.name === plan.installerName ? 4 * 1024 ** 3 : 1024 * 1024) &&
      (expected.bytes === undefined || actual.size === expected.bytes) &&
      actual.browser_download_url === `https://github.com/${plan.sourceRepository}/releases/download/${plan.sourceTag}/${expected.name}` &&
      actual.digest === `sha256:${expected.sha256}`, 'asset-metadata-invalid');
  }
  return plan;
}

export function verifyAcquisition(lock, confirmation, evidenceRoot, metadataOnly = false) {
  physical(evidenceRoot, 'directory');
  const release = readJson(join(evidenceRoot, 'github-release.json'), 4 * 1024 * 1024);
  const chain = readJson(join(evidenceRoot, 'github-tag-chain.json'));
  const plan = validateReleaseMetadata(lock, confirmation, release, chain);
  if (metadataOnly) return plan;
  for (const item of plan.assets) {
    const path = physical(join(evidenceRoot, item.name), 'file');
    const size = release.assets.find(a => a.id === item.id).size;
    need(lstatSync(path).size === size && hashFile(path) === item.sha256, 'download-hash-mismatch');
  }
  const installer = join(evidenceRoot, plan.installerName);
  // Installer is data only; bounded size was checked above. Never execute it.
  need(sha512File(installer) === lock.components.desktop.artifact.sha512,
    'download-hash-mismatch');
  const fixture = relativeName(lock.components.desktop.releaseChannel.nativeProvisioning.fixtureRoot.replaceAll('\\', '/'));
  need(fixture.startsWith('tests/fixtures/desktop-native-verified-release/'), 'formal-evidence-path-invalid');
  const fixtureRoot = physical(join(opsRoot, fixture), 'directory');
  // Full reviewed release evidence, including self-hashes, receipts, capabilities,
  // helper and ancestor acceptance. Labels such as fixtureKind establish no origin.
  verifyNativeReleaseEvidence(lock, fixtureRoot);
  need(isDeepStrictEqual(readJson(join(evidenceRoot, 'release.json')).identity,
    lock.components.desktop.releaseChannel.identity), 'application-release-identity-mismatch');
  for (const name of ['release.json', 'build-receipt.json', 'desktop-provisioning.json']) {
    need(hashFile(join(evidenceRoot, name)) === hashFile(join(fixtureRoot, name)), 'formal-evidence-mismatch');
  }
  return plan;
}

// Exact immutable source emits deterministic read-only settings leaves. This
// gate binds freshly executed phases to formal proof, never real search success.
export function verifyFreshSettingsEvidence(lock, accepted, sourceOutput) {
  // Do not let the historical settings early-return bypass explicit positive proof.
  verifyFreshPositiveUsageEvidence(lock, accepted, sourceOutput);
  const channel = lock.components.desktop.releaseChannel;
  if (channel.upstreamVersion === '0.1.6-alpha.2') return verifyPackagedPhaseEvidence(lock, accepted, sourceOutput);
  const proof = channel.nativeProvisioning.settingsAcceptance;
  if (proof === undefined && channel.upstreamVersion !== '0.1.6-alpha.2' &&
    !(channel.upstreamVersion === '0.1.6-alpha.1' && channel.sequence >= 12)) return;
  need(proof && (proof.schemaVersion === undefined || proof.schemaVersion === 2) &&
    accepted.modelRolesViewLoaded === true && accepted.searchProviderCatalogLoaded === true &&
    accepted.realSearch === false, 'source-settings-acceptance-incomplete');
  if (proof.schemaVersion === 2) {
    need(accepted.manageCompatibilityDisclosureAbsent === true && accepted.providerOnlySearchRouting === true &&
      accepted.realOAuth === false && accepted.verificationNavigationExercised === false &&
      accepted.manualVerificationAddressObserved === false && accepted.realModelRound === false &&
      accepted.realSearch === false, 'source-settings-acceptance-incomplete');
  }
  let providers; const versionMenus = [];
  const phases = [['initial', proof.initialSha256, proof.initialVersionMenuSha256],
    ['restart', proof.restartSha256, proof.restartVersionMenuSha256]];
  for (const [phase, digest, versionDigest] of phases) {
    const path = physical(join(sourceOutput, `${phase}-settings-readonly.json`), 'file');
    need(hashFile(path) === digest, 'source-settings-acceptance-incomplete');
    if (proof.schemaVersion === 2) {
      const settings = readJson(path); const ids = settings.registeredSearchProviders;
      need(settings.modelRolesViewLoaded === true && settings.currentWorkspaceReadOnly === true &&
        settings.searchProviderCatalogLoaded === true && settings.providerOnlySearchRouting === true &&
        settings.fallbackProviderLabel === true && settings.realSearch === false &&
        Array.isArray(ids) && ids.every(id => typeof id === 'string' && id.length > 0) &&
        new Set(ids).size === ids.length && ids.includes('github-copilot-hosted') &&
        (providers === undefined || isDeepStrictEqual(providers, ids)),
      'source-settings-acceptance-incomplete');
      providers = ids;
      const versionPath = physical(join(sourceOutput, `${phase}-version-menu.json`), 'file');
      need(hashFile(versionPath) === versionDigest, 'source-settings-acceptance-incomplete');
      const versionMenu = readJson(versionPath);
      need(versionMenu.applicationMenuLabel === 'Application' &&
        versionMenu.aboutMenuLabel === `About Desktop ${channel.version}…` &&
        versionMenu.desktopVersion === channel.version && versionMenu.aboutDispatchCount === 1 &&
        versionMenu.nativeModalOpened === false &&
        (versionMenus.length === 0 || isDeepStrictEqual(versionMenus[0], versionMenu)),
      'source-settings-acceptance-incomplete');
      versionMenus.push(versionMenu);
    }
  }
  if (proof.schemaVersion === 2) need(isDeepStrictEqual(accepted.versionMenus, versionMenus), 'source-settings-acceptance-incomplete');
  const usageProof = channel.nativeProvisioning.usageAcceptance;
  if (usageProof !== undefined) {
    const capability = accepted.copilotUsageCapability;
    need(usageProof.schemaVersion === 1 && object(capability) &&
      capability.id === 'account-quota-composer-usage' && capability.required === true &&
      capability.evidenceScope === 'synthetic-quota-and-public-remote-ui-contracts-not-live-account-access' &&
      capability.signedOutNetworkRegressionDeclared === true && capability.lifecycleRegressionDeclared === true &&
      accepted.hostQuotaNoNetworkEvidence === 'immutable-plugin-ci-regression-only' &&
      accepted.liveAccountQuota === false && Array.isArray(accepted.signedOutCopilotUsage) &&
      accepted.signedOutCopilotUsage.length === 2 && Array.isArray(accepted.timeline),
    'source-usage-acceptance-incomplete');
    const observations = [];
    for (const [phase, digest] of [['initial', usageProof.initialSha256], ['restart', usageProof.restartSha256]]) {
      const path = physical(join(sourceOutput, `${phase}-usage-readonly.json`), 'file');
      need(hashFile(path) === digest, 'source-usage-acceptance-incomplete');
      const usage = readJson(path);
      need(isDeepStrictEqual(usage.capability, capability) && usage.signedOut?.usageTriggerCount === 0 &&
        usage.signedOut?.accountUsageTextCount === 0 && usage.signedOut?.usageSurfaceAbsent === true &&
        usage.signedOut?.hostQuotaRequestInstrumentation === 'not-available-in-packaged-smoke',
      'source-usage-acceptance-incomplete');
      observations.push(usage.signedOut);
      const events = accepted.timeline.map(entry => entry?.event);
      need(events.indexOf(`${phase}:account`) >= 0 &&
        events.indexOf(`${phase}:usage-readonly`) > events.indexOf(`${phase}:account`),
      'source-usage-acceptance-incomplete');
    }
    need(isDeepStrictEqual(accepted.signedOutCopilotUsage, observations) &&
      isDeepStrictEqual(observations[0], observations[1]), 'source-usage-acceptance-incomplete');
  }
}

export function verifyFreshPositiveUsageEvidence(lock, accepted, sourceOutput) {
  verifyPositiveUsageEvidence(lock, accepted, (name, digest) => {
    const path = physical(join(sourceOutput, name), 'file');
    need(hashFile(path) === digest, 'source-positive-usage-acceptance-incomplete');
    return readJson(path);
  });
}

export function verifyFreshPositiveUsageClient(lock, profile) {
  const proof = lock.components.desktop.releaseChannel.nativeProvisioning.usagePositiveAcceptance;
  if (proof === undefined) return;
  need(object(proof) && hashValid(proof.installedClientSha256) &&
    hashFile(physical(join(profile, 'node_modules/dsh-github-copilot/lib/client.js'), 'file')) ===
      proof.installedClientSha256, 'source-positive-usage-client-mismatch');
}

export function validateSourceIdentity(lock, confirmation, identity) {
  const plan = releasePlan(lock, confirmation); const build = lock.components.desktop.releaseChannel.build;
  need(identity.head === plan.sourceCommit && identity.tree === plan.sourceTree && identity.dirty === '', 'checkout-mismatch');
  need(identity.lockfileSha256 === build.lockfileSha256 && identity.planSha256 === build.planSha256 &&
    identity.packageManager === `pnpm@${plan.pnpmVersion}` && identity.rootVersion === plan.upstreamVersion &&
    identity.desktopVersion === plan.upstreamVersion && identity.nodeVersion === `v${plan.nodeVersion}`, 'source-build-input-mismatch');
  return plan;
}
function localGit(sourceRoot, args) {
  const env = {};
  for (const key of ['PATH', 'Path', 'SystemRoot', 'WINDIR', 'TEMP', 'TMP']) if (process.env[key]) env[key] = process.env[key];
  Object.assign(env, { GIT_CONFIG_NOSYSTEM: '1', GIT_CONFIG_GLOBAL: process.platform === 'win32' ? 'NUL' : '/dev/null',
    GIT_TERMINAL_PROMPT: '0', GIT_OPTIONAL_LOCKS: '0' });
  const result = spawnSync('git', ['-c', 'core.fsmonitor=false', '-C', sourceRoot, ...args], {
    env, shell: false, windowsHide: true, encoding: 'utf8', timeout: 30000, maxBuffer: 1024 * 1024 });
  need(!result.error && result.status === 0 && !result.signal, 'git-inspection-failed');
  return result.stdout.trim();
}
export function verifySource(lock, confirmation, sourceRoot) {
  releasePlan(lock, confirmation); physical(sourceRoot, 'directory'); physical(join(sourceRoot, '.git'), 'directory');
  need(!entryExists(join(sourceRoot, '.env')), 'source-env-forbidden');
  physical(join(sourceRoot, sourceFixture), 'file');
  const root = readJson(join(sourceRoot, 'package.json'));
  const desktop = readJson(join(sourceRoot, 'apps/desktop/package.json'));
  return validateSourceIdentity(lock, confirmation, {
    head: localGit(sourceRoot, ['rev-parse', 'HEAD']), tree: localGit(sourceRoot, ['rev-parse', 'HEAD^{tree}']),
    dirty: localGit(sourceRoot, ['status', '--porcelain', '--untracked-files=all']),
    lockfileSha256: hashFile(physical(join(sourceRoot, 'pnpm-lock.yaml'), 'file')),
    planSha256: hashFile(physical(join(sourceRoot, sourcePlan), 'file')),
    packageManager: root.packageManager, rootVersion: root.version, desktopVersion: desktop.version, nodeVersion: process.version,
  });
}

/** Read package identity as DATA. PE ProductVersion alone omits the release suffix. */
export function validateApplicationPackageMetadata(bytes, lock) {
  need(Buffer.isBuffer(bytes) && bytes.length > 0 && bytes.length <= 1024 * 1024, 'application-package-invalid');
  let value; try { value = JSON.parse(bytes.toString('utf8')); } catch { fail('application-package-invalid'); }
  const expectedName = lock.components.desktop.releaseChannel.identity.packageName;
  const expectedVersion = lock.components.desktop.version;
  need(object(value) && typeof expectedName === 'string' && expectedName !== '' &&
    value.name === expectedName && value.version === expectedVersion, 'application-package-identity-mismatch');
  return { applicationPackageName: value.name, applicationPackageVersion: value.version, applicationPackageSha256: sha256(bytes) };
}

export function readApplicationPackageIdentity(lock, snapshot) {
  const archive = physical(snapshot.archive, 'file');
  need(hashFile(archive) === snapshot.archiveSha256, 'application-archive-changed');
  const raw = boundedHeader(archive);
  // Reuse maintained header-driven bounds/path checks before allocating any file.
  headerRuntimeInventory(raw, lstatSync(archive).size);
  const entry = raw.header.files['package.json'];
  need(object(entry) && !Object.hasOwn(entry, 'files') && !Object.hasOwn(entry, 'link') && entry.unpacked !== true &&
    Number.isSafeInteger(entry.size) && entry.size > 0 && entry.size <= 1024 * 1024, 'application-package-invalid');
  let bytes;
  try { bytes = asarReader.extractFile(archive, 'package.json', false); }
  finally { asarReader.uncache(archive); }
  need(bytes.length === entry.size && hashFile(archive) === snapshot.archiveSha256, 'application-archive-changed');
  return validateApplicationPackageMetadata(bytes, lock);
}

export function discoverApplication(lock, confirmation, extractRoot) {
  releasePlan(lock, confirmation); physical(extractRoot, 'directory');
  const candidates = []; let count = 0;
  const name = lock.components.desktop.installedExecutable.relativePath;
  const visit = (directory, depth) => {
    need(depth < 20 && ++count <= 200000, 'extraction-inventory-limit');
    for (const entry of readdirSync(directory, { withFileTypes: true })) {
      const path = join(directory, entry.name);
      need(!entry.isSymbolicLink(), 'extraction-reparse');
      if (entry.isDirectory()) { physical(path, 'directory'); visit(path, depth + 1); }
      else {
        need(++count <= 200000, 'extraction-inventory-limit');
        physical(path, 'file');
        if (entry.name.toLowerCase() === name.toLowerCase()) {
          need(entry.name === name, 'executable-name-mismatch'); candidates.push(path);
        }
      }
    }
  };
  visit(extractRoot, 0); need(candidates.length === 1, 'application-inventory-mismatch');
  const application = candidates[0]; const snapshot = preflightAsar(lock, dirname(application));
  return { application, ...readApplicationPackageIdentity(lock, snapshot) };
}

function inspectObserverPaths(paths, sourceRoot, application, output) {
  need(object(paths) && Object.isFrozen(paths) && Object.keys(paths).sort().join(',') === 'application,home,output,profile,runtimeRoot' &&
    paths.application === application && paths.runtimeRoot === join(dirname(application), 'resources/app.asar/dsh') &&
    paths.output === output && paths.profile === join(paths.home, 'profiles/desktop') &&
    inside(join(sourceRoot, '.desktop-smoke'), paths.home) && dirname(paths.home) === join(sourceRoot, '.desktop-smoke'), 'observer-paths-invalid');
  physical(paths.home, 'directory'); physical(paths.profile, 'directory');
}
function inspectionInput(lock, paths, diagnosticRoot) {
  return { fixtureKind: 'external-real-runtime', lock, installRoot: dirname(paths.application), dshHome: paths.home, diagnosticRoot };
}
function integration(input, output, label) {
  const inputPath = join(output, `${label}-request.json`);
  writeFileSync(inputPath, JSON.stringify(input), { flag: 'wx' });
  try {
    // Never forward process.execArgv: the source runner's tsx/esm loader must
    // not influence the independent Ops CHECK or its packaged Electron child.
    const result = spawnSync(process.execPath, [join(opsRoot, 'tests/native-asar-integration.mjs'), inputPath], {
      shell: false, windowsHide: true, cwd: output, env: probeEnvironment(output), encoding: 'utf8',
      timeout: 180000, maxBuffer: 65536, killSignal: 'SIGKILL' });
    need(!result.error && !result.signal && [0, 1].includes(result.status) && result.stderr === '', 'integration-process-failed');
    let data; try { data = JSON.parse(result.stdout); } catch { fail('integration-output-invalid'); }
    need(object(data) && data.modelResponseVerified === false && data.formalReleaseAcceptance === false &&
      ((result.status === 0 && data.valid === true) || (result.status === 1 && data.valid === false)), 'integration-output-invalid');
    if (data.valid === false) need(data.qualification === 'not-ready' && typeof data.reason === 'string' &&
      /^native-[a-z-]{1,120}$/u.test(data.reason), 'integration-output-invalid');
    return data;
  } finally { unlinkSync(inputPath); }
}

/** Executes real source UI only after every preflight. Never use on a live installation. */
export async function runReleaseSmoke({ lock, confirmation, sourceRoot, application, output, evidenceRoot }) {
  const plan = releasePlan(lock, confirmation); // current .5 fails with zero side effects
  need(process.platform === 'win32', 'windows-required');
  // Accidental-use boundary, not authentication: actual UI qualification belongs
  // only to the manual CI job's private temporary tree, never a live installation.
  need(process.env.GITHUB_ACTIONS === 'true' && typeof process.env.RUNNER_TEMP === 'string', 'ci-run-required');
  const runnerTemp = physical(resolve(process.env.RUNNER_TEMP), 'directory'); probeEnvironment(runnerTemp);
  need(dirname(runnerTemp) !== runnerTemp, 'private-run-path-required');
  for (const path of [sourceRoot, application, output, evidenceRoot, opsRoot]) {
    need(typeof path === 'string' && resolve(path) !== runnerTemp && inside(runnerTemp, resolve(path)), 'private-run-path-required');
  }
  verifyAcquisition(lock, confirmation, evidenceRoot);
  const verifiedSource = verifySource(lock, confirmation, sourceRoot);
  physical(application, 'file'); physical(output, 'directory'); probeEnvironment(output);
  need(process.cwd() === sourceRoot && !inside(sourceRoot, output) && !inside(dirname(application), output) &&
    !inside(opsRoot, output) && !entryExists(join(output, 'qualification.json')), 'output-or-cwd-invalid');
  need(application === join(dirname(application), lock.components.desktop.installedExecutable.relativePath), 'application-path-invalid');
  const before = preflightAsar(lock, dirname(application));
  const applicationIdentity = readApplicationPackageIdentity(lock, before);
  const sourceOutput = join(output, 'source-evidence');
  need(!entryExists(sourceOutput), 'output-not-empty');
  let calls = 0; let observedHome; let positive; let completed = false;
  let diagnosticStage = 'source-import';
  const invalidRequests = {};
  // Ops source is a workflow-created git archive, not a checkout. Bind genuine caller leaves, not invented tree evidence.
  const caller = plan.upstreamVersion === '0.1.6-alpha.2' ? captureOpsCaller() : undefined;
  const summaryIdentity = caller === undefined ? { schemaVersion: 1 } : { schemaVersion: 2, caller };
  try {
    // No token, source .env, or arbitrary DSH/Node loader overrides enter the fixture.
    for (const [key, value] of Object.entries(process.env)) {
      if (value && /(?:TOKEN|SECRET|PASSWORD|CREDENTIAL|API_KEY|AUTHORIZATION)|^NODE_OPTIONS$|^NODE_PATH$|^DSH_/iu.test(key)) {
        need(key === 'DSH_TELEMETRY_DISABLED' && value === '1', 'sensitive-environment');
      }
    }
    const invokeCore = async expected => {
    const { runPackagedCopilotAcceptance } = await import(pathToFileURL(join(sourceRoot, sourceFixture)).href);
    need(typeof runPackagedCopilotAcceptance === 'function', 'observer-api-unavailable');
    diagnosticStage = 'source-fixture';
    return await runPackagedCopilotAcceptance({ application, output: sourceOutput,
      ...(expected === undefined ? {} : { expectedCoreSource: expected }), inspectProfile: async paths => {
      diagnosticStage = 'observer';
      need(++calls === 1, 'observer-count-invalid');
      inspectObserverPaths(paths, sourceRoot, application, sourceOutput); observedHome = paths.home;
      const metadataPaths = ['package.json', 'desktop-plugin-receipts.json', 'desktop-plugin-provisioning-state.json'];
      const metadataBefore = metadataPaths.map(name => hashFile(physical(join(paths.profile, name), 'file')));
      verifyFreshPositiveUsageClient(lock, paths.profile);
      const input = inspectionInput(lock, paths, output);
      positive = integration(input, output, 'positive');
      if (positive.valid === false) throw new Error(positive.reason); // already bounded, owned error code only
      need(positive.valid === true && positive.qualification === 'external-real-runtime-files-and-resolution' &&
        positive.runtime?.mode === 'asar-runtime' && positive.runtime?.sharedPeerResolution === 'metadata-cjs-esm' &&
        positive.runtime?.executableSha256 === lock.components.desktop.installedExecutable.sha256, 'positive-qualification-failed');
      // Deliberately invalid REQUEST COPIES, never edits to the real profile/runtime.
      const badDigest = structuredClone(input); badDigest.lock.components.desktop.installedRuntimeDescriptor.sha256 = '0'.repeat(64);
      const badVersion = structuredClone(input); badVersion.lock.components.desktop.releaseChannel.upstreamVersion = '0.1.6-deliberately-invalid-request';
      const badHome = structuredClone(input); badHome.dshHome = join(paths.home, 'absent-deliberately-invalid-request');
      need(!entryExists(badHome.dshHome), 'negative-home-not-absent');
      for (const [name, request, reason] of [
        ['descriptorDigest', badDigest, 'native-runtime-descriptor-mismatch'],
        ['version', badVersion, 'native-runtime-descriptor-invalid'],
        ['home', badHome, 'native-evidence-missing'],
      ]) {
        const result = integration(request, output, name);
        need(result.valid === false && result.reason === reason, 'invalid-request-not-rejected'); invalidRequests[name] = 'rejected';
      }
      need(isDeepStrictEqual(metadataPaths.map(name => hashFile(join(paths.profile, name))), metadataBefore), 'observer-metadata-mutated');
      need(preflightAsar(lock, dirname(application)).archiveSha256 === before.archiveSha256, 'runtime-mutated');
      diagnosticStage = 'source-fixture';
    } });
    };
    // Historical alpha.1 has no explicit API. Alpha.2 receives verified Core facts, never a rewritten Ops SHA.
    if (caller === undefined) await invokeCore();
    else await invokeCoreFixture(caller, expectedCoreSource(lock, verifiedSource), invokeCore);
    diagnosticStage = 'post-acceptance';
    need(calls === 1 && observedHome && !entryExists(observedHome), 'observer-cleanup-incomplete');
    const accepted = caller === undefined ? readJson(join(sourceOutput, 'acceptance.json')) :
      verifyFreshOrdinaryPackagedEvidence(lock, sourceOutput, caller);
    need(accepted.sourceCommit === plan.sourceCommit && accepted.desktopVersion === plan.version &&
      accepted.runtimeVersion === plan.upstreamVersion && accepted.actualGraphVerified === true &&
      accepted.accountEntryVisible === true && accepted.ancestorSdkJunction === true && accepted.ancestorSdkLoaded === false &&
      accepted.realOAuth === false && accepted.realModelRound === false && accepted.installerUpgradeVerified === false,
    'source-acceptance-incomplete');
    verifyFreshSettingsEvidence(lock, accepted, sourceOutput);
    diagnosticStage = 'final-runtime';
    verifySource(lock, confirmation, sourceRoot);
    const after = preflightAsar(lock, dirname(application));
    need(after.archiveSha256 === before.archiveSha256 &&
      isDeepStrictEqual(readApplicationPackageIdentity(lock, after), applicationIdentity), 'runtime-mutated');
    completed = true;
    const summary = { ...summaryIdentity, valid: true, qualification: 'locked-release-ops-observer',
      version: plan.version, sourceCommit: plan.sourceCommit, sourceTree: plan.sourceTree,
      installerSha256: lock.components.desktop.artifact.sha256, executableSha256: before.executableSha256,
      descriptorSha256: before.descriptorSha256, runtimeFileCount: positive.runtime.fileCount,
      ...applicationIdentity,
      publicResolver: 'metadata-cjs-esm', observerCalls: calls, profileRemoved: true, invalidRequests,
      wholeCarrierAttested: false, modelResponseVerified: false, installerUpgradeVerified: false };
    writeFileSync(join(output, 'qualification.json'), JSON.stringify(summary, null, 2) + '\n', { flag: 'wx' });
    return summary;
  } catch (error) {
    const summary = { ...summaryIdentity, valid: false, qualification: 'not-ready', reason: safeReason(error),
      observerCalls: calls, profileRemoved: observedHome ? !entryExists(observedHome) : null, modelResponseVerified: false,
      diagnostic: sourceFailureDiagnostic(sourceOutput, diagnosticStage, error) };
    writeFileSync(join(output, 'qualification.json'), JSON.stringify(summary, null, 2) + '\n', { flag: 'wx' });
    throw new Error(summary.reason);
  } finally {
    // Source owns cleanup even when our observer rejects; never keep/copy/delete
    // its profile ourselves or call a replacement fixture on failure.
    if (!completed && observedHome && entryExists(observedHome)) process.exitCode = 1;
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  try {
    const { values } = parseArgs({ options: {
      plan: { type: 'boolean' }, 'verify-metadata': { type: 'boolean' }, 'verify-acquisition': { type: 'boolean' },
      'verify-source': { type: 'boolean' }, 'discover-application': { type: 'boolean' }, run: { type: 'boolean' },
      lock: { type: 'string' }, 'confirm-version': { type: 'string' }, 'source-root': { type: 'string' },
      'evidence-root': { type: 'string' }, 'extract-root': { type: 'string' }, application: { type: 'string' }, output: { type: 'string' },
    }, allowPositionals: false });
    const modes = ['plan', 'verify-metadata', 'verify-acquisition', 'verify-source', 'discover-application', 'run'].filter(k => values[k]);
    need(modes.length === 1 && values.lock && values['confirm-version'], 'arguments-required');
    const lock = readJson(resolve(values.lock)); const confirmation = values['confirm-version'];
    releasePlan(lock, confirmation);
    const absolute = key => { need(typeof values[key] === 'string', 'arguments-required'); return resolve(values[key]); };
    let result;
    if (values.plan) result = releasePlan(lock, confirmation);
    else if (values['verify-metadata'] || values['verify-acquisition']) result = verifyAcquisition(lock, confirmation, absolute('evidence-root'), !!values['verify-metadata']);
    else if (values['verify-source']) result = verifySource(lock, confirmation, absolute('source-root'));
    else if (values['discover-application']) result = discoverApplication(lock, confirmation, absolute('extract-root'));
    else result = await runReleaseSmoke({ lock, confirmation, sourceRoot: absolute('source-root'), application: absolute('application'),
      evidenceRoot: absolute('evidence-root'), output: absolute('output') });
    process.stdout.write(JSON.stringify(result) + '\n');
  } catch (error) {
    process.stdout.write(JSON.stringify({ valid: false, qualification: 'not-ready', reason: safeReason(error), modelResponseVerified: false }) + '\n');
    process.exitCode = 1;
  }
}
