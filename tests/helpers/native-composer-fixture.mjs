// INERT temporary data copies only. Never package/release bytes or runtime qualification.
import { cpSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { sha256 } from '../../tools/native-runtime-integrity.mjs';

const root = fileURLToPath(new URL('../../', import.meta.url));
export function settingsV3Fixture(t) {
  const lock = JSON.parse(readFileSync(join(root, 'deployments/windows-copilot.lock.json')));
  const native = lock.components.desktop.releaseChannel.nativeProvisioning;
  const directory = mkdtempSync(join(tmpdir(), 'ops-inert-composer-'));
  t.after(() => rmSync(directory, { recursive: true, force: true }));
  cpSync(join(root, native.fixtureRoot.replaceAll('\\', '/')), directory, { recursive: true });
  const get = name => JSON.parse(readFileSync(join(directory, name)));
  const put = (name, value) => { const bytes = JSON.stringify(value); writeFileSync(join(directory, name), bytes); return sha256(bytes); };
  const accepted = get('acceptance.json');
  delete accepted.modelRolesViewLoaded; delete accepted.currentWorkspaceReadOnly;
  const settings = ['initial', 'restart'].map(() => ({ schemaVersion: 3, accountViewLoaded: true,
    retiredModelRolesAbsent: true, searchProviderCatalogLoaded: true, providerOnlySearchRouting: true,
    fallbackProviderLabel: true, registeredSearchProviders: ['deepseek-official', 'github-copilot-hosted'], realSearch: false }));
  const menus = ['initial', 'restart'].map(phase => get(`${phase}-version-menu.json`));
  accepted.settingsAcceptance = settings; accepted.versionMenus = menus;
  native.settingsAcceptance.schemaVersion = 3;
  const save = () => {
    for (const [index, phase] of ['initial', 'restart'].entries()) {
      native.settingsAcceptance[`${phase}Sha256`] = put(`${phase}-settings-readonly.json`, settings[index]);
      native.settingsAcceptance[`${phase}VersionMenuSha256`] = put(`${phase}-version-menu.json`, menus[index]);
    }
    native.ancestorIsolation.acceptanceSha256 = put('acceptance.json', accepted);
  };
  save(); return { lock, native, directory, accepted, settings, menus, get, put, save };
}

export function nativeComposerFixture(t) {
  const f = settingsV3Fixture(t); const d = f.lock.components.desktop;
  const style = { fontSize: '13px', lineHeight: '20px', color: 'rgb(100, 100, 100)' };
  const geometry = [
    { viewportWidth: 1280, dock: { x: 200, y: 600, width: 800, height: 26 },
      time: { x: 300, y: 604, width: 100, height: 22 }, usage: { x: 412, y: 604, width: 180, height: 22 },
      copilot: { x: 604, y: 604, width: 150, height: 22 }, nativeStyle: { ...style }, copilotStyle: { ...style } },
    { viewportWidth: 400, dock: { x: 24, y: 600, width: 352, height: 100 },
      time: { x: 100, y: 604, width: 100, height: 22 }, usage: { x: 100, y: 638, width: 180, height: 22 },
      copilot: { x: 100, y: 672, width: 150, height: 22 }, nativeStyle: { ...style }, copilotStyle: { ...style } },
  ];
  const value = { schemaVersion: 1, scope: 'actual-packaged-native-composer-and-released-client',
    sourceCommit: d.source.commit, sessionHistory: 'synthetic-persisted-in-isolated-home',
    quota: 'signed-out-host-response-no-credentials', runtimeSha256: d.installedRuntimeDescriptor.sha256,
    pluginSource: structuredClone(f.accepted.plugin), installedClientSha256: f.native.usagePositiveAcceptance.installedClientSha256,
    geometry, nativeDialogs: {
      time: { opened: true, closedOnEscape: true, focusReturned: true },
      usage: { opened: true, closedOnEscape: true, focusReturned: true },
    }, copilotDialog: { signedOutObserved: true, sessionCreditsCount: 0, resetCount: 0, epochTextCount: 0, focusReturned: true },
    rendererErrors: [], realModelRound: false, realOAuth: false };
  f.accepted.nativeComposer = value;
  f.accepted.timeline.push({ event: 'native-composer:seeded' }, { event: 'native-composer:closed' });
  f.native.nativeComposerAcceptance = { schemaVersion: 1, installedClientSha256: value.installedClientSha256 };
  const save = (repinGeometry = true) => {
    const hash = f.put('native-composer-geometry.json', value);
    if (repinGeometry) f.native.nativeComposerAcceptance.sha256 = hash;
    f.save();
  };
  save(); return { ...f, value, save };
}

export const composerNegatives = [
  ['missing source', f => { delete f.value.sourceCommit; }],
  ['different source', f => { f.value.sourceCommit = '0'.repeat(40); }],
  ['runtime mismatch', f => { f.value.runtimeSha256 = '0'.repeat(64); }],
  ['Client mismatch', f => { f.value.installedClientSha256 = '0'.repeat(64); }],
  ['plugin mismatch', f => { f.value.pluginSource.version = 'inert-wrong'; }],
  ['main mismatch', f => { f.accepted.nativeComposer = {}; }],
  ['wrong session scope', f => { f.value.sessionHistory = 'live-session'; }],
  ['wrong quota scope', f => { f.value.quota = 'live-account'; }],
  ['renderer error', f => { f.value.rendererErrors = ['synthetic error']; }],
  ['string renderer errors', f => { f.value.rendererErrors = '[]'; }],
  ['real model claim', f => { f.value.realModelRound = true; }],
  ['real OAuth string', f => { f.value.realOAuth = 'false'; }],
  ['extra viewport', f => { f.value.geometry.push(f.value.geometry[0]); }],
  ['missing narrow viewport', f => { f.value.geometry.pop(); }],
  ['reversed viewports', f => { f.value.geometry.reverse(); }],
  ['string viewport', f => { f.value.geometry[0].viewportWidth = '1280'; }],
  ['old stacked layout', f => { f.value.geometry[0].copilot.y += 40; }],
  ['reversed native order', f => { f.value.geometry[0].copilot.x = 200; f.value.geometry[0].copilot.width = 90; }],
  ['wide overlap', f => { f.value.geometry[0].copilot.x = 500; }],
  ['narrow overlap', f => { f.value.geometry[1].copilot.y = 638; }],
  ['dock overflow', f => { f.value.geometry[0].copilot.x = 950; }],
  ['viewport overflow', f => { f.value.geometry[1].dock.width = 1000; f.value.geometry[1].copilot.x = 390; }],
  ['missing control', f => { f.value.geometry[0].copilot.width = 0; }],
  ['negative height', f => { f.value.geometry[1].time.height = -1; }],
  ['null coordinate', f => { f.value.geometry[0].time.x = null; }],
  ['string coordinate', f => { f.value.geometry[1].usage.y = '638'; }],
  ['non-finite coordinate', f => { f.value.geometry[1].dock.y = Infinity; }],
  ['non-finite summed bounds', f => { f.value.geometry[0].dock.x = Number.MAX_VALUE; f.value.geometry[0].dock.width = Number.MAX_VALUE; }],
  ...['fontSize', 'lineHeight', 'color'].map(key => [`mismatched ${key}`, f => { f.value.geometry[0].copilotStyle[key] = 'different'; }]),
  ['non-pixel font', f => { for (const style of ['nativeStyle', 'copilotStyle']) f.value.geometry[1][style].fontSize = 'small'; }],
  ['zero line height', f => { for (const style of ['nativeStyle', 'copilotStyle']) f.value.geometry[0][style].lineHeight = '0px'; }],
  ['empty color', f => { for (const style of ['nativeStyle', 'copilotStyle']) f.value.geometry[1][style].color = ''; }],
  ...['time', 'usage'].flatMap(name => ['opened', 'closedOnEscape', 'focusReturned'].flatMap(key =>
    [false, 'true'].map(value => [`${name}.${key}=${JSON.stringify(value)}`, f => { f.value.nativeDialogs[name][key] = value; }]))),
  ...['signedOutObserved', 'focusReturned'].flatMap(key => [false, 'true'].map(value =>
    [`copilot.${key}=${JSON.stringify(value)}`, f => { f.value.copilotDialog[key] = value; }])),
  ...['sessionCreditsCount', 'resetCount', 'epochTextCount'].flatMap(key => [1, '0'].map(value =>
    [`copilot.${key}=${JSON.stringify(value)}`, f => { f.value.copilotDialog[key] = value; }])),
  ['missing native dialogs', f => { delete f.value.nativeDialogs; }],
  ['missing epoch count', f => { delete f.value.copilotDialog.epochTextCount; }],
  ['seed before restart closes', f => { const event = f.accepted.timeline.splice(-2, 1)[0]; f.accepted.timeline.unshift(event); }],
  ['no native close', f => { f.accepted.timeline.pop(); }],
  ['duplicate seed', f => { f.accepted.timeline.push({ event: 'native-composer:seeded' }); }],
];

export const settingsV3Negatives = [
  ...['accountViewLoaded', 'retiredModelRolesAbsent', 'searchProviderCatalogLoaded', 'providerOnlySearchRouting', 'fallbackProviderLabel']
    .flatMap(key => [false, 'true', 1, null].map(value => [`${key}=${JSON.stringify(value)}`, f => { f.settings[1][key] = value; }])),
  ['missing retirement leaf', f => { delete f.settings[0].retiredModelRolesAbsent; }],
  ['legacy roles flag', f => { f.settings[0].modelRolesViewLoaded = true; }],
  ['legacy workspace flag', f => { f.settings[1].currentWorkspaceReadOnly = true; }],
  ['legacy main roles claim', f => { f.accepted.modelRolesViewLoaded = true; }],
  ['legacy main workspace claim', f => { f.accepted.currentWorkspaceReadOnly = true; }],
  ['wrong settings schema', f => { f.settings[0].schemaVersion = '3'; }],
  ['different deterministic phases', f => { f.settings[1].registeredSearchProviders.push('synthetic-third-provider'); }],
  ['missing hosted provider', f => { f.settings[0].registeredSearchProviders = ['deepseek-official']; }],
  ['duplicate provider', f => { f.settings[1].registeredSearchProviders.push('github-copilot-hosted'); }],
  ['wrong main settings array', f => { f.accepted.settingsAcceptance = []; }],
  ['real search claim', f => { f.settings[1].realSearch = true; }],
  ['main fallback string', f => { f.accepted.fallbackProviderLabel = 'true'; }],
  ['wrong version menu', f => { f.menus[1].desktopVersion = 'synthetic-wrong'; }],
  ['version modal string', f => { f.menus[0].nativeModalOpened = 'false'; }],
];
