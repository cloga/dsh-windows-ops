// Synthetic file/error data only; never launch a Desktop or load package code.
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, readFileSync, rmSync, symlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';
import { execFileSync } from 'node:child_process';
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

const startup = text => `Error: Packaged Desktop startup failed: ${text}`;
const githubHttp = status => `desktop plugin source: GitHub request failed with ${status}`;
for (const [status, code] of [[401,'plugin-github-http-401'],[403,'plugin-github-http-403'],
  [404,'plugin-github-http-404'],[429,'plugin-github-http-429'],[500,'plugin-github-http-5xx'],
  [503,'plugin-github-http-5xx'],[599,'plugin-github-http-5xx'],[400,'plugin-github-http-other'],
  [304,'plugin-github-http-other']]) {
  test(`owned startup HTTP message exposes only fixed category for ${status}`, () => {
    assert.equal(classifySourceError(startup(githubHttp(status))), code);
    assert.equal(classifySourceError(`Packaged Desktop startup failed: ${githubHttp(status)}`), code);
    assert.equal(classifySourceError(startup(`desktop project: transaction failed and its audit could not be recorded\n${githubHttp(status)}`)), code);
  });
}
for (const [message, code] of [
  ['desktop plugin source: GitHub redirect limit exceeded','plugin-github-redirect'],
  ['desktop plugin source: GitHub redirect omitted its location','plugin-github-redirect'],
  ['desktop plugin source: GitHub request must use credential-free HTTPS','plugin-github-policy'],
  ['fetch failed','startup-fetch-failed'],
]) test(`exact fixed startup message maps to ${code} without cause inference`, () => {
  assert.equal(classifySourceError(startup(message)), code);
});
for (const [index,message] of [githubHttp(200),githubHttp(301),githubHttp('0403'),githubHttp('4030'),
  `${githubHttp(403)} ${secret}`,`${githubHttp(403)}\r`,`${githubHttp(403)}\u2028`,
  `${secret}${githubHttp(403)}`,`https://example.invalid/${githubHttp(403)}`,
  `\"${githubHttp(403)}\"`,`${githubHttp(403)}?token=${secret}`,`fetch failed ${secret}`,
  'desktop plugin source: rejected redirect host private.example',
  `${githubHttp(403)}\n${githubHttp(404)}`].entries()) {
  test(`startup near-miss ${index} remains generic`, () => {
    assert.equal(classifySourceError(startup(message)), 'desktop-startup');
  });
}
for (const [status, detail, code] of [[403,`ERR_MODULE_NOT_FOUND ${secret}`,'module-not-found'],
  [403,`EPERM ${secret}`,'access-denied'],[429,`locator.waitFor: Timeout ${secret}`,'locator-timeout']]) {
  test(`retains prior ${code} priority over a new HTTP category`, () => {
    assert.equal(classifySourceError(startup(`${githubHttp(status)}\n${detail}`)),code);
  });
}
test('new startup categories require the exact wrapper and do not classify truncated lines', () => {
  assert.equal(classifySourceError(githubHttp(403)), 'unknown');
  assert.equal(classifySourceError(`prefix ${startup(githubHttp(403))}`), 'desktop-startup');
  const clipped = startup('x\n'.repeat(65536) + githubHttp(403));
  assert.equal(classifySourceError(clipped), 'desktop-startup');
});
for (const [phase,event] of [['initial','version-menu'],['restart','version-menu'],
  ['initial','usage-readonly'],['restart','usage-readonly'],['restart','positive-usage']]) {
  test(`source timeline retains recorded ${phase}:${event} without promoting a failed run`, t => {
    const root=temporary(t);writeFileSync(join(root,'failure.json'),JSON.stringify({
      error:startup(githubHttp(403)),visibleText:secret,stderrTail:secret,
      timeline:[{event:`${phase}:launch`},{event:`${phase}:${event}`},{event:'failure'}],raw:secret}));
    const result=sourceFailureDiagnostic(root,'source-fixture',new Error(secret));
    assert.deepEqual(result,{stage:'source-fixture',code:'plugin-github-http-403',sourceFailure:'present',sourcePhase:`${phase}:${event}`});fixed(result);
  });
}

test('source import failure has no fixture diagnostic and leaks no original message', t => {
  const result = sourceFailureDiagnostic(join(temporary(t),'absent'), 'source-import', new Error('Cannot find module '+secret));
  assert.deepEqual(result,{stage:'source-import',code:'module-not-found',sourceFailure:'absent',sourcePhase:'none'}); fixed(result);
});
test('reads only the last recorded allowlisted phase, never raw diagnostic fields', t => {
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
test('actual PowerShell artifact guard accepts new fixed categories and refuses untrusted fields', {skip:process.platform !== 'win32'},()=>{
  const workflow=readFileSync(new URL('../.github/workflows/native-asar-release.yml',import.meta.url),'utf8');
  const begin=workflow.indexOf('$diagnostic = $summary.diagnostic');
  const end=workflow.indexOf('\n          }\n          if ($alpha2)',begin);
  assert(begin>0 && end>begin);
  const guard=workflow.slice(begin,end);
  const good={stage:'source-fixture',code:'plugin-github-http-403',sourceFailure:'present',sourcePhase:'initial:version-menu'};
  const samples=[good,{...good,sourcePhase:'restart:usage-readonly'},{...good,sourcePhase:'restart:positive-usage'},
    {...good,code:secret},{...good,code:403},{...good,sourcePhase:secret},{...good,stage:secret},
    {...good,sourceFailure:'true'},{...good,raw:secret},null,[],{...good,sourcePhase:false},
    {...good,sourcePhase:'initial:positive-usage'}];
  const encoded=Buffer.from(JSON.stringify(samples),'utf8').toString('base64');
  const script=`$ErrorActionPreference='Stop'\n$samples=([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('${encoded}')) | ConvertFrom-Json -AsHashtable)\n$results=@(foreach($sample in $samples){$summary=@{diagnostic=$sample};try{\n${guard}\n$true}catch{$false}})\nConvertTo-Json -Compress -InputObject $results`;
  const output=execFileSync('pwsh',['-NoProfile','-NonInteractive','-EncodedCommand',Buffer.from(script,'utf16le').toString('base64')],
    {encoding:'utf8',windowsHide:true,timeout:30000});
  assert(!output.includes(secret));
  assert.deepEqual(JSON.parse(output),[true,true,true,false,false,false,false,false,false,false,false,false,false]);
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
