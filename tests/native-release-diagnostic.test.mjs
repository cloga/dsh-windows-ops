// Synthetic file/error data only; never launch a Desktop or load package code.
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, readFileSync, rmSync, symlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';
import { classifySourceError, sourceFailureDiagnostic, diagnosticStages, diagnosticPhases, diagnosticCodes } from '../tools/native-release-diagnostic.mjs';
const secret = 'DO_NOT_PUBLISH_private_path_token_visibleText';
function temporary(t) { const root = mkdtempSync(join(tmpdir(), 'ops-diagnostic-unit-')); t.after(() => rmSync(root, { recursive: true, force: true })); return root; }
function fixed(value) {
  assert.deepEqual(Object.keys(value).sort(), ['code','sourceFailure','sourcePhase','stage']);
  assert(diagnosticStages.includes(value.stage)); assert(diagnosticCodes.includes(value.code));
  assert(diagnosticPhases.includes(value.sourcePhase)); assert(['absent','present','unreadable'].includes(value.sourceFailure));
  assert(!JSON.stringify(value).includes(secret));
}
for (const [message, code] of [
  ['Packaged Desktop startup failed: '+secret, 'desktop-startup'],
  ['locator.waitFor: Timeout 30000ms exceeded '+secret, 'locator-timeout'],
  ['electron.launch: '+secret,'electron-launch'],
  ['ERR_MODULE_NOT_FOUND '+secret,'module-not-found'],
  ['ERR_DLOPEN_FAILED '+secret,'native-addon'],
  ['No usable native binding found '+secret,'native-addon'],
  ['Packaged Desktop startup failed: No usable native binding found '+secret,'native-addon'],
  ['ERR_PACKAGE_PATH_NOT_EXPORTED '+secret,'package-export'],
  ['EACCES '+secret,'access-denied'],['ENOENT '+secret,'missing-file'],
  ['AssertionError [ERR_ASSERTION]: '+secret,'assertion'],['Command failed: '+secret,'child-command'],
  [secret,'unknown'], [null,'unknown'], [{message:secret},'unknown'],
]) test(`error classifier returns only fixed code ${code}`, () => assert.equal(classifySourceError(message), code));

test('source import failure has no fixture diagnostic and leaks no original message', t => {
  const result = sourceFailureDiagnostic(join(temporary(t),'absent'), 'source-import', new Error('Cannot find module '+secret));
  assert.deepEqual(result,{stage:'source-import',code:'module-not-found',sourceFailure:'absent',sourcePhase:'none'}); fixed(result);
});
test('reads only allowlisted last completed phase, never raw diagnostic fields', t => {
  const root = temporary(t); writeFileSync(join(root,'failure.json'),JSON.stringify({error:'locator.waitFor: Timeout '+secret,
    visibleText:secret,stderrTail:secret,profileFilesPresent:{[secret]:true},timeline:[
      {event:'package-identity',milliseconds:1},{event:'initial:account',milliseconds:2},
      {event:secret,milliseconds:3},{event:'failure',milliseconds:4}],extra:secret}));
  const result = sourceFailureDiagnostic(root,'source-fixture',new Error(secret));
  assert.deepEqual(result,{stage:'source-fixture',code:'locator-timeout',sourceFailure:'present',sourcePhase:'initial:account'}); fixed(result);
});
for(const [mode,body] of [['malformed','{'+secret],['array','[]'],['null','null'],['missing-timeline',JSON.stringify({error:secret})],
  ['oversize', ' '.repeat(131073)],['too-many-events',JSON.stringify({timeline:Array(65).fill({event:secret})})]]) {
  test(`${mode} source failure is unreadable without weakening primary failure`, t=>{
    const root=temporary(t);writeFileSync(join(root,'failure.json'),body);
    const result=sourceFailureDiagnostic(root,'observer',new Error(secret));
    assert.equal(result.sourceFailure,'unreadable');assert.equal(result.sourcePhase,'none');fixed(result);
  });
}
test('diagnostic input exactly at byte bound remains bounded and reads fixed leaves',t=>{
  const root=temporary(t),raw=JSON.stringify({error:secret,timeline:[{event:'restart:closed'}]});
  writeFileSync(join(root,'failure.json'),raw+' '.repeat(131072-Buffer.byteLength(raw)));
  const result=sourceFailureDiagnostic(root,'post-acceptance',new Error(secret));
  assert.equal(result.sourceFailure,'present');assert.equal(result.sourcePhase,'restart:closed');fixed(result);
});
test('unsafe stage and arbitrary source timeline values never become output',t=>{
  const root=temporary(t);writeFileSync(join(root,'failure.json'),JSON.stringify({error:secret,timeline:[null,{},secret,{event:secret},{event:{toString:secret}}]}));
  const result=sourceFailureDiagnostic(root,secret,new Error(secret));assert.equal(result.stage,'source-fixture');assert.equal(result.sourcePhase,'none');fixed(result);
});
test('directory instead of failure file is unreadable',t=>{
  const root=temporary(t);mkdirSync(join(root,'failure.json'));
  const result=sourceFailureDiagnostic(root,'source-fixture',new Error(secret));assert.equal(result.sourceFailure,'unreadable');fixed(result);
});
test('reparse diagnostic ancestor is rejected before reading target content',t=>{
  const root=temporary(t),target=join(root,'target'),link=join(root,'link');mkdirSync(target);
  writeFileSync(join(target,'failure.json'),JSON.stringify({error:secret,timeline:[{event:'initial:account'}]}));
  symlinkSync(target,link,process.platform==='win32'?'junction':'dir');
  const result=sourceFailureDiagnostic(link,'source-fixture',new Error(secret));assert.equal(result.sourceFailure,'unreadable');assert.equal(result.sourcePhase,'none');fixed(result);
});
test('workflow failure artifact validates exact fixed diagnostic keys and vocabularies',()=>{
  const workflow=readFileSync(new URL('../.github/workflows/native-asar-release.yml',import.meta.url),'utf8');
  assert(workflow.includes("'code,sourceFailure,sourcePhase,stage'"));
  for(const item of [...diagnosticStages,...diagnosticCodes])assert(workflow.includes(`'${item}'`));
  assert(workflow.includes("$diagnostic.sourceFailure -cnotin @('absent','present','unreadable')"));
  assert(workflow.includes("'diagnostic,modelResponseVerified,observerCalls,profileRemoved,qualification,reason,schemaVersion,valid'"));
  assert(workflow.includes("Remove private source, fixture payloads and raw diagnostics"));
  assert(!workflow.includes('path: ${{ steps.private.outputs.root }}/output/source-evidence'));
});
