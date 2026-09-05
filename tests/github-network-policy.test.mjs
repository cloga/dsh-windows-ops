import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const guide = fs.readFileSync(new URL('../docs/github-network.md', import.meta.url), 'utf8');

test('ordinary Git is the default and wrapper adoption is optional', () => {
  assert.match(guide, /Ordinary Git over official HTTPS is the default/);
  assert.match(guide, /wrapper is OPTIONAL/);
  assert.doesNotMatch(guide, /Use this tool for GitHub HTTPS reads\/fetches\/feature pushes from all repositories/);
});

test('optional wrapper policy retains credential and uncertain-write safeguards', () => {
  for (const phrase of ['GIT_CONFIG_COUNT', 'never a token in argv', 'Keep TLS enabled',
    'read the exact remote ref', 'matching SHA means delivered', 'stop as uncertain',
    'PR review', 'checks nonempty bytes against the supplied SHA-256', 'from a trusted release manifest']) {
    assert.ok(guide.includes(phrase), `Missing policy safeguard: ${phrase}`);
  }
});

test('documented limitations do not claim network repair or implemented timeout changes', () => {
  assert.match(guide, /not a connectivity repair service/);
  assert.match(guide, /90-second deadline/);
  assert.match(guide, /http.lowSpeedTime=20/);
  assert.match(guide, /not changed by this policy update/);
  assert.match(guide, /they validate safety logic, not Internet uptime/);
});
