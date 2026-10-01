import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync } from 'node:child_process';

const root = new URL('../', import.meta.url);
const read = name => fs.readFileSync(new URL(name, root), 'utf8');
const guide = read('docs/git-delivery-playbook.md');

test('both README entrypoints and the network policy link the durable playbook', () => {
  for (const name of ['README.md', 'README.en.md', 'docs/github-network.md']) {
    assert.match(read(name), /\]\((?:docs\/)?git-delivery-playbook\.md\)/);
  }
});

test('records a bounded native profile without machine paths or changed wrapper defaults', () => {
  for (const text of ['2.53.0-4', 'HTTP/1.1', 'http.sslVerify=true', 'http.followRedirects=false', '45000', '120000', 'windowsHide:true']) {
    assert.ok(guide.includes(text), text);
  }
  assert.match(guide, /This update adds no wrapper options or changed defaults/);
  assert.doesNotMatch(guide, /C:[\\/]Users[\\/]/);
  assert.doesNotMatch(guide, /(?:ghp_|github_pat_)[A-Za-z0-9_]{20,}/);
});

test('the documented child-process fragment parses without running Git or loading credentials', () => {
  const snippet = guide.match(/```js\n([\s\S]*?)\n```/u)?.[1];
  assert.ok(snippet);
  assert.match(snippet, /\['http\.sslVerify', 'true'\]/);
  assert.match(snippet, /\['http\.followRedirects', 'false'\]/);
  assert.match(snippet, /\['ls-remote', '--heads', remoteUrl, exactRef\]/);
  assert.match(snippet, /Review unsafe TLS overrides/);
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'git-playbook-syntax-'));
  try {
    const file = path.join(dir, 'profile.mjs');
    fs.writeFileSync(file, snippet);
    execFileSync(process.execPath, ['--check', file], { stdio: 'pipe' });
  } finally { fs.rmSync(dir, { recursive: true, force: true }); }
});

test('keeps retry, original-commit, hook and one-off fallback boundaries explicit', () => {
  for (const text of [
    'Switching executable, HTTP option, wrapper or Session does not reset it',
    'read the exact remote ref first',
    'explicit one-off approval',
    'invoke the actual pre-push hook',
    'REST-created commits are not a Git fallback',
    'a one-task pre-commit exception is not standing cross-session permission',
  ]) assert.ok(guide.includes(text), text);
});

test('separates historical delivery evidence from publication and installation claims', () => {
  assert.match(guide, /cloga\/deepseek-harness\/pull\/75/);
  assert.match(guide, /not an uptime guarantee or a single-variable causal diagnosis/);
  assert.match(guide, /PR delivery did not establish green CI or a new release/);
  assert.match(guide, /Keep Desktop, Core and plugin versions distinct/);
  assert.match(guide, /authorizes no installation, restart or changes to other worktrees/);
});
