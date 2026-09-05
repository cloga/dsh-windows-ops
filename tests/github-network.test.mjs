import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import crypto from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { NetworkError, classify, childEnv, tokenFromFile, githubRepo, checkedDownloadUrl, retry, gitOperation, download, request, verifyIdentity, main } from '../tools/github-network.mjs';
const sha = 'a'.repeat(40), otherSha = 'b'.repeat(40), url = 'https://github.com/example/repo.git';
const options = { attempts: 3, wait: async () => {} };
const ok = text => ({ code: 0, text: text ?? '' });
function mockGit(special = () => undefined) {
  const calls = [];
  const runner = async (cmd, args, opts) => {
    calls.push({ cmd, args, opts });
    const custom = await special(args, calls);
    if (custom) return custom;
    if (args[0] === 'config') return { code: 1, text: '' };
    if (args[0] === 'remote') return ok(url);
    if (args[0] === 'check-ref-format') return ok();
    if (args[0] === 'rev-parse') return ok(sha);
    if (args.includes('--symref')) return ok(`ref: refs/heads/master\tHEAD\n${otherSha}\tHEAD\n`);
    return ok(`${otherSha}\trefs/heads/feature/test\n`);
  };
  return { runner, calls };
}
function gitInput(runner, operation = 'push') { return { repoPath: '.', operation, branch: 'feature/test', token: 'synthetic_test_token', runner, retryOptions: options }; }
function temp() { return fs.mkdtempSync(path.join(os.tmpdir(), 'github-network-test-')); }
const digest = value => crypto.createHash('sha256').update(value).digest('hex');

test('classifies failures without treating rejected auth or conflicts as network', () => {
  for (const s of ['ECONNRESET', 'Failed to connect to github.com', 'Connection timed out', 'Recv failure', 'TLS handshake failed']) assert.equal(classify(s), 'network');
  assert.equal(classify('Authentication failed'), 'auth-or-permission');
  assert.equal(classify('Permission denied (publickey)'), 'auth-or-permission');
  assert.equal(classify('certificate verify failed'), 'tls-trust');
  assert.equal(classify('non-fast-forward'), 'rejected');
  assert.equal(classify('Repository not found'), 'not-found');
  assert.equal(classify('', 429), 'rate-limit');
  assert.equal(classify('', 403), 'auth-or-permission');
  assert.equal(classify('', 503), 'network');
});
test('dotenv is explicit, supports quotes and BOM, rejects ambiguous token assignments', () => {
  const dir = temp(), file = path.join(dir, '.env');
  try {
    fs.writeFileSync(file, '\uFEFFGH_TOKEN="synthetic_test_token"\n'); assert.equal(tokenFromFile(file), 'synthetic_test_token');
    fs.writeFileSync(file, 'GH_TOKEN=x\nGH_TOKEN=y'); assert.throws(() => tokenFromFile(file), /exactly one/);
    fs.writeFileSync(file, 'GH_TOKEN="has space"'); assert.throws(() => tokenFromFile(file), /malformed/);
    assert.throws(() => tokenFromFile(), /designated/);
    assert.throws(() => tokenFromFile(path.join(dir, 'missing')), /unavailable/);
  } finally { fs.rmSync(dir, { recursive: true }); }
});
test('only credential-free canonical HTTPS GitHub repositories accepted', () => {
  assert.equal(githubRepo('https://github.com/example/repo'), url);
  assert.equal(githubRepo(url), url);
  for (const bad of ['http://github.com/a/b','https://evil.test/github.com/a/b','https://token@github.com/a/b','https://github.com/a/b?token=x','git@github.com:a/b','https://github.com/a/..','https://github.com/a/b/c']) assert.throws(() => githubRepo(bad));
});
test('token stays in process-scoped scoped header, not parent environment', () => {
  const before = process.env.GIT_CONFIG_COUNT;
  const e = childEnv('synthetic_test_token');
  assert.equal(process.env.GIT_CONFIG_COUNT, before);
  const entries = Array.from({length:Number(e.GIT_CONFIG_COUNT)}, (_,i) => [e[`GIT_CONFIG_KEY_${i}`],e[`GIT_CONFIG_VALUE_${i}`]]);
  assert.ok(entries.some(([k,v]) => k === 'http.followRedirects' && v === 'false'));
  assert.ok(entries.some(([k,v]) => k === 'http.sslVerify' && v === 'true'));
  assert.ok(entries.some(([k,v]) => k === 'http.https://github.com/.extraHeader' && v.startsWith('Authorization: Basic ')));
  assert.equal(e.GH_TOKEN, undefined);
});
test('bounded retry only retries network; VPN is attempted once', async () => {
  let calls = 0, vpns = 0;
  const result = await retry(async () => { if (++calls < 3) throw new NetworkError('network', 'test'); return true; }, { ...options, vpn:'MSFTVPN', onNetwork:async()=>{vpns++;} });
  assert.equal(result, true); assert.equal(calls,3); assert.equal(vpns,1);
  calls=0;
  await assert.rejects(retry(async()=>{calls++;throw new NetworkError('auth-or-permission','no');},options));
  assert.equal(calls,1);
  calls=0;
  await assert.rejects(retry(async()=>{calls++;throw new NetworkError('network','no');},options));
  assert.equal(calls,3);
});
test('rejects URL rewrite rules before using remote credentials', async () => {
  const m=mockGit(a=>a[0]==='config'?ok('url.https://mirror/.insteadof https://github.com/'):undefined);
  await assert.rejects(gitOperation(gitInput(m.runner)), /rewrite/);
  assert.equal(m.calls.length,1);
});
test('push refuses differing destination and default branch', async () => {
  const m=mockGit(a=>a.includes('--push')?ok('https://github.com/other/repo.git'):undefined);
  await assert.rejects(gitOperation(gitInput(m.runner)), /differs/);
  const n=mockGit(); await assert.rejects(gitOperation({...gitInput(n.runner),branch:'master'}), /Direct push/);
  assert.ok(!n.calls.some(c=>c.args[0]==='push'));
});
test('push freezes HEAD and reconciles lost success without pushing twice', async () => {
  let pushes=0;
  const m=mockGit(a=>{if(a[0]==='push'){pushes++;return{code:1,text:'Connection reset'};} if(a[0]==='ls-remote'&&!a.includes('--symref'))return ok(`${sha}\trefs/heads/feature/test\n`);});
  const r=await gitOperation(gitInput(m.runner)); assert.equal(r.reconciled,true); assert.equal(pushes,1);
  const args=m.calls.find(c=>c.args[0]==='push').args;
  assert.ok(args.includes(`${sha}:refs/heads/feature/test`));
  assert.ok(!args.includes('--force')); assert.ok(!args.includes('--no-verify'));
  assert.ok(!JSON.stringify(args).includes('synthetic_test_token'));
});
test('unknown remote state after lost push response stops, never blindly retries', async () => {
  let pushes=0;
  const m=mockGit(a=>{if(a[0]==='push'){pushes++;return{code:1,text:'timed out'};} if(a[0]==='ls-remote'&&!a.includes('--symref'))return{code:1,text:'timed out'};});
  await assert.rejects(gitOperation(gitInput(m.runner)), e=>e.category==='uncertain-push'); assert.equal(pushes,1);
});
test('network failure with verified different remote permits bounded non-force retry', async () => {
  let pushes=0;
  const m=mockGit(a=>a[0]==='push'?(++pushes===1?{code:1,text:'Connection reset'}:ok()):undefined);
  const r=await gitOperation(gitInput(m.runner)); assert.equal(r.ok,true); assert.equal(pushes,2);
});
test('auth errors suppress raw output containing secrets', async () => {
  const m=mockGit(a=>a[0]==='push'?{code:1,text:'Authentication failed synthetic_test_token'}:undefined);
  await assert.rejects(gitOperation(gitInput(m.runner)), e=>e.category==='auth-or-permission'&&!e.message.includes('synthetic_test_token'));
  assert.equal(m.calls.filter(c=>c.args[0]==='push').length,1);
});
test('ambient follow-tags and submodule push settings cannot widen argv', async () => {
  const m=mockGit(); await gitOperation(gitInput(m.runner));
  const args=m.calls.find(c=>c.args[0]==='push').args;
  assert.ok(args.includes('--no-follow-tags')); assert.ok(args.includes('--recurse-submodules=no'));
});
test('effective URL-scoped Git config is detected and refused offline', async () => {
  const dir=temp();
  try {
    const clean={...process.env,GIT_CONFIG_NOSYSTEM:'1',GIT_CONFIG_GLOBAL:path.join(dir,'empty')};
    execFileSync('git',['init',dir],{env:clean,stdio:'ignore'});
    execFileSync('git',['-C',dir,'config','http.https://github.com/example/.sslVerify','false'],{env:clean,stdio:'ignore'});
    const overrideEnv={...childEnv(),GIT_CONFIG_NOSYSTEM:'1',GIT_CONFIG_GLOBAL:path.join(dir,'empty')};
    const effective=execFileSync('git',['-C',dir,'config','--get-urlmatch','http.sslVerify',url],{env:overrideEnv,encoding:'utf8'}).trim();
    assert.equal(effective,'false'); // demonstrates why a generic forced value alone is insufficient
    const m=mockGit(a=>{
      if(a[0]==='config'&&a[2]?.startsWith('^http'))return ok(execFileSync('git',['-C',dir,...a],{env:overrideEnv,encoding:'utf8'}));
    });
    await assert.rejects(gitOperation(gitInput(m.runner)), /scoped Git HTTP/);
    assert.ok(!m.calls.some(c=>['push','fetch','ls-remote'].includes(c.args[0])));
    execFileSync('git',['-C',dir,'config','http.https://github.com/example/.sslVerify',''],{env:clean,stdio:'ignore'});
    assert.equal(execFileSync('git',['-C',dir,'config','--type=bool','--get-urlmatch','http.sslVerify',url],{env:overrideEnv,encoding:'utf8'}).trim(),'false');
    await assert.rejects(gitOperation(gitInput(m.runner)), /scoped Git HTTP/);
    for(const line of ['http.https://github.com/a/.followredirects true','http.https://github.com/a/.extraheader Authorization: Bearer synthetic']){
      const n=mockGit(a=>a[0]==='config'&&a[2]?.startsWith('^http')?ok(line):undefined);
      await assert.rejects(gitOperation(gitInput(n.runner)), /scoped Git HTTP/);
    }
  } finally {fs.rmSync(dir,{recursive:true,force:true});}
});
test('Node disabled TLS validation refuses even injected fetch before network', async () => {
  const old=process.env.NODE_TLS_REJECT_UNAUTHORIZED;process.env.NODE_TLS_REJECT_UNAUTHORIZED='0';let called=0;
  try {
    const fetchImpl=async()=>{called++;return Response.json({login:'expected'});};
    await assert.rejects(verifyIdentity('synthetic','expected',{fetchImpl}),e=>e.category==='tls-trust');
    await assert.rejects(download({url:'https://github.com/a/b',output:'unused',sha256:'0'.repeat(64),fetchImpl}),e=>e.category==='tls-trust');
    assert.equal(called,0);
  } finally {if(old===undefined)delete process.env.NODE_TLS_REJECT_UNAUTHORIZED;else process.env.NODE_TLS_REJECT_UNAUTHORIZED=old;}
});
test('identity response body reset retries but malformed JSON does not', async () => {
  let n=0;const fetchImpl=async()=>({ok:true,status:200,json:async()=>{if(++n===1)throw new TypeError('body reset',{cause:{code:'ECONNRESET'}});return{login:'expected'};}});
  assert.equal(await retry(()=>verifyIdentity('synthetic','expected',{fetchImpl}),options),'expected');assert.equal(n,2);
  await assert.rejects(verifyIdentity('synthetic','expected',{fetchImpl:async()=>new Response('not json')}),e=>e.category==='other');
});
test('unknown/custom default, multiple URLs and invalid refs fail before push', async () => {
  for(const reply of ['',`ref: refs/heads/feature/test\tHEAD\n`]){
    const m=mockGit(a=>a.includes('--symref')?ok(reply):undefined);
    await assert.rejects(gitOperation(gitInput(m.runner)));assert.ok(!m.calls.some(c=>c.args[0]==='push'));
  }
  const m=mockGit(a=>a[0]==='remote'?ok(url+'\nhttps://github.com/another/repo.git'):undefined);
  await assert.rejects(gitOperation(gitInput(m.runner)),/one fetch URL/);
  const n=mockGit(a=>a[0]==='check-ref-format'?{code:1,text:''}:undefined);
  await assert.rejects(gitOperation({...gitInput(n.runner),branch:'invalid..ref'}),/Invalid branch/);
});
test('fetch updates selected remote tracking refs without pruning or worktree writes', async () => {
  const m=mockGit(); await gitOperation(gitInput(m.runner,'fetch'));
  assert.deepEqual(m.calls.at(-1).args,['fetch','--no-recurse-submodules','--no-prune','--no-prune-tags','--no-tags',url,'refs/heads/*:refs/remotes/origin/*']);
});
test('API credentials are host-restricted; redirects and identity mismatch fail closed', async () => {
  await assert.rejects(request('https://evil.test',{token:'test'}),/restricted/);
  await assert.rejects(request('https://api.github.com/user',{token:'test',fetchImpl:async()=>new Response('',{status:302,headers:{location:'https://evil.test'}})}), /redirect/);
  await assert.rejects(verifyIdentity('test','expected',{fetchImpl:async()=>Response.json({login:'other'})}),/differs/);
});
test('CLI accepts sha256 option and rejects malformed/duplicate/unknown options', async () => {
  const dir=temp(), output=path.join(dir,'cached');fs.writeFileSync(output,'cached');
  try {
    const r=await main(['download','--url','https://github.com/a/b','--output',output,'--sha256',digest('cached')]);assert.equal(r.cached,true);
    for(const args of [['check','--account'],['check','--account','x','--account','y'],['check','--unknown','x']])await assert.rejects(main(args),e=>e.category==='configuration');
  } finally {fs.rmSync(dir,{recursive:true});}
});
test('public download validates every redirect and never sends Authorization', async () => {
  const dir=temp(), output=path.join(dir,'artifact'), bytes=Buffer.from('verified artifact'); let calls=0;
  try {
    const fetchImpl=async(u,o)=>{assert.equal(o.headers.Authorization,undefined); if(++calls===1)return new Response(null,{status:302,headers:{location:'https://release-assets.githubusercontent.com/file'}});return new Response(bytes);};
    const r=await download({url:'https://github.com/example/repo/releases/download/v1/file',output,sha256:digest(bytes),fetchImpl,retryOptions:options});
    assert.equal(r.ok,true);assert.equal(calls,2);assert.deepEqual(fs.readFileSync(output),bytes);
    const cached=await download({url:'https://github.com/example/repo/releases/download/v1/file',output,sha256:digest(bytes),fetchImpl});assert.equal(cached.cached,true);assert.equal(calls,2);
  } finally {fs.rmSync(dir,{recursive:true});}
});
test('download rejects redirects to mirrors and mismatched bytes without publishing', async () => {
  const dir=temp(), output=path.join(dir,'artifact');
  try {
    await assert.rejects(download({url:'https://github.com/a/b',output,sha256:'0'.repeat(64),fetchImpl:async()=>new Response(null,{status:302,headers:{location:'https://mirror.test/file'}})}),/official/);
    await assert.rejects(download({url:'https://github.com/a/b',output,sha256:'0'.repeat(64),fetchImpl:async()=>new Response('wrong')}),/trusted SHA/);
    assert.deepEqual(fs.readdirSync(dir),[]);
    fs.writeFileSync(output,'keep');await assert.rejects(download({url:'https://github.com/a/b',output,sha256:'0'.repeat(64)}),/overwrite/);assert.equal(fs.readFileSync(output,'utf8'),'keep');
    for(const u of ['http://github.com/a','https://token@github.com/a','https://github.com.evil.test/a','https://github.com:444/a'])assert.throws(()=>checkedDownloadUrl(u));
  } finally {fs.rmSync(dir,{recursive:true});}
});
