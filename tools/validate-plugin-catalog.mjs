#!/usr/bin/env node
'use strict';

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const args = process.argv.slice(2);
function option(name, fallback) {
  const prefix = `--${name}=`;
  const value = args.find((entry) => entry.startsWith(prefix));
  return path.resolve(root, value === undefined ? fallback : value.slice(prefix.length));
}
const catalogPath = option('catalog', 'catalog/plugins.json');
const schemaPath = option('schema', 'catalog/schema/plugin-catalog.schema.json');
const lockPath = option('lock', 'deployments/windows-copilot.lock.json');
const today = new Date().toISOString().slice(0, 10);
const errors = [];

function readJson(file) {
  try {
    return JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch (error) {
    errors.push(`${path.relative(root, file)}: invalid JSON: ${error.message}`);
    return null;
  }
}

function fail(location, message) {
  errors.push(`${location}: ${message}`);
}

function isObject(value) {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function nonempty(value) {
  return typeof value === 'string' && value.length > 0;
}

function schemaTypesMatch(value, declared) {
  const types = Array.isArray(declared) ? declared : [declared];
  return types.some((type) => {
    if (type === 'null') return value === null;
    if (type === 'array') return Array.isArray(value);
    if (type === 'object') return isObject(value);
    if (type === 'integer') return Number.isInteger(value);
    if (type === 'number') return typeof value === 'number' && Number.isFinite(value);
    return typeof value === type;
  });
}

function resolveSchemaRef(document, reference) {
  if (!reference.startsWith('#/')) throw new Error(`unsupported schema reference ${reference}`);
  return reference.slice(2).split('/').reduce((value, segment) => value?.[segment.replaceAll('~1', '/').replaceAll('~0', '~')], document);
}

function validateSchemaValue(value, rule, location, document) {
  if (rule.$ref !== undefined) {
    const resolved = resolveSchemaRef(document, rule.$ref);
    if (!resolved) { fail(location, `unresolved schema reference ${rule.$ref}`); return; }
    validateSchemaValue(value, resolved, location, document);
    return;
  }
  if (rule.const !== undefined && value !== rule.const) fail(location, `must equal ${JSON.stringify(rule.const)}`);
  if (rule.enum !== undefined && !rule.enum.some(entry => Object.is(entry, value))) fail(location, 'is not an allowed value');
  if (rule.type !== undefined && !schemaTypesMatch(value, rule.type)) { fail(location, `must match type ${JSON.stringify(rule.type)}`); return; }
  if (typeof value === 'string') {
    if (rule.minLength !== undefined && value.length < rule.minLength) fail(location, `must have length >= ${rule.minLength}`);
    if (rule.pattern !== undefined && !(new RegExp(rule.pattern)).test(value)) fail(location, `does not match ${rule.pattern}`);
  }
  if (typeof value === 'number' && rule.minimum !== undefined && value < rule.minimum) fail(location, `must be >= ${rule.minimum}`);
  if (Array.isArray(value)) {
    if (rule.minItems !== undefined && value.length < rule.minItems) fail(location, `must contain at least ${rule.minItems} items`);
    if (rule.uniqueItems === true && new Set(value.map(entry => JSON.stringify(entry))).size !== value.length) fail(location, 'must contain unique items');
    if (rule.items !== undefined) value.forEach((entry, index) => validateSchemaValue(entry, rule.items, `${location}[${index}]`, document));
  }
  if (isObject(value)) {
    for (const required of rule.required ?? []) if (!Object.hasOwn(value, required)) fail(`${location}.${required}`, 'is required by schema');
    const properties = rule.properties ?? {};
    if (rule.additionalProperties === false) {
      for (const key of Object.keys(value)) if (!Object.hasOwn(properties, key)) fail(`${location}.${key}`, 'is not allowed by schema');
    }
    for (const [key, childRule] of Object.entries(properties)) {
      if (Object.hasOwn(value, key)) validateSchemaValue(value[key], childRule, `${location}.${key}`, document);
    }
  }
}

const catalog = readJson(catalogPath);
const schema = readJson(schemaPath);
const deployment = readJson(lockPath);

if (catalog && schema && deployment) {
  const requiredLevels = ['L0', 'L1', 'L2', 'L3', 'L4', 'L5', 'baseline'];
  const recommendations = new Set(['recommended', 'conditional', 'experimental', 'historical', 'rejected', 'unreviewed']);
  const integrations = new Set(['cordis', 'mcp', 'browser-extension', 'external-service', 'mixed']);
  const evidenceKinds = new Set(['discovery', 'source-review', 'compat-check', 'import-probe', 'composition-mount', 'functional-smoke', 'deployment-lock', 'upstream-change']);
  const levelRank = new Map(requiredLevels.map((level, index) => [level, index]));

  validateSchemaValue(catalog, schema, 'catalog', schema);
  if (catalog.schemaVersion !== 1) fail('catalog', 'schemaVersion must be 1');
  if (!/^\d{4}-\d{2}-\d{2}$/.test(catalog.updatedAt ?? '')) fail('catalog.updatedAt', 'must use YYYY-MM-DD');
  else if (catalog.updatedAt > today) fail('catalog.updatedAt', `future date ${catalog.updatedAt}`);

  const levels = Array.isArray(catalog.validationLevels) ? catalog.validationLevels : [];
  const levelIds = levels.map((entry) => entry?.id);
  if (new Set(levelIds).size !== levelIds.length) fail('catalog.validationLevels', 'contains duplicate ids');
  for (const level of requiredLevels) if (!levelIds.includes(level)) fail('catalog.validationLevels', `missing ${level}`);

  if (!Array.isArray(catalog.plugins)) fail('catalog.plugins', 'must be an array');
  const baselinePlugins = (catalog.plugins ?? []).filter(plugin => plugin?.validation?.level === 'baseline');
  if (baselinePlugins.length !== 1 || baselinePlugins[0]?.id !== 'dsh-github-copilot') {
    fail('catalog.plugins', 'must contain exactly one locked baseline entry for dsh-github-copilot');
  }
  const ids = new Set();
  for (const [index, plugin] of (catalog.plugins ?? []).entries()) {
    const at = `catalog.plugins[${index}]`;
    if (!isObject(plugin)) { fail(at, 'must be an object'); continue; }
    if (!/^[a-z0-9][a-z0-9._-]*$/.test(plugin.id ?? '')) fail(`${at}.id`, 'must be a stable lowercase id');
    else if (ids.has(plugin.id)) fail(`${at}.id`, `duplicate id ${plugin.id}`);
    else ids.add(plugin.id);
    if (!nonempty(plugin.displayName)) fail(`${at}.displayName`, 'is required');
    if (!Array.isArray(plugin.categories) || plugin.categories.length === 0) fail(`${at}.categories`, 'must be nonempty');
    if (!integrations.has(plugin.integration)) fail(`${at}.integration`, 'is invalid');
    if (!Array.isArray(plugin.platforms) || plugin.platforms.length === 0) fail(`${at}.platforms`, 'must be nonempty');
    if (!recommendations.has(plugin.recommendation)) fail(`${at}.recommendation`, 'is invalid');
    if (!isObject(plugin.source) || !/^https:\/\/github\.com\//.test(plugin.source.repository ?? '')) fail(`${at}.source.repository`, 'must be a GitHub HTTPS URL');
    if (plugin.source?.commit !== undefined && !/^[0-9a-f]{7,40}$/.test(plugin.source.commit)) fail(`${at}.source.commit`, 'must be a hexadecimal commit id');
    if (plugin.source?.mergeCommit !== undefined && !/^[0-9a-f]{7,40}$/.test(plugin.source.mergeCommit)) fail(`${at}.source.mergeCommit`, 'must be a hexadecimal commit id');
    if (plugin.source?.pullRequest !== undefined && (!Number.isInteger(plugin.source.pullRequest) || plugin.source.pullRequest < 1)) fail(`${at}.source.pullRequest`, 'must be a positive integer');
    if (plugin.artifact !== undefined && (!isObject(plugin.artifact) || !nonempty(plugin.artifact.name) || !/^https:\/\/github\.com\//.test(plugin.artifact.url ?? '') || !/^[0-9a-f]{64}$/.test(plugin.artifact.sha256 ?? ''))) fail(`${at}.artifact`, 'requires name, GitHub HTTPS URL, and lowercase SHA-256');
    if (plugin.artifact?.releaseTag !== undefined && !/^v\d+\.\d+\.\d+(?:-[0-9A-Za-z]+(?:\.[0-9A-Za-z]+)*)?$/.test(plugin.artifact.releaseTag)) fail(`${at}.artifact.releaseTag`, 'must be a version tag');
    if (plugin.artifact?.releaseImmutable !== undefined && typeof plugin.artifact.releaseImmutable !== 'boolean') fail(`${at}.artifact.releaseImmutable`, 'must be boolean');
    if (plugin.artifact?.checksumManifestUrl !== undefined && !/^https:\/\/github\.com\//.test(plugin.artifact.checksumManifestUrl)) fail(`${at}.artifact.checksumManifestUrl`, 'must be a GitHub HTTPS URL');
    if (!nonempty(plugin.summary)) fail(`${at}.summary`, 'is required');

    const validation = plugin.validation;
    if (!isObject(validation) || !levelRank.has(validation.level)) { fail(`${at}.validation`, 'has an invalid level'); continue; }
    if (validation.verifiedAt !== null && !/^\d{4}-\d{2}-\d{2}$/.test(validation.verifiedAt ?? '')) fail(`${at}.validation.verifiedAt`, 'must be null or YYYY-MM-DD');
    else if (validation.verifiedAt !== null && validation.verifiedAt > today) fail(`${at}.validation.verifiedAt`, `future date ${validation.verifiedAt}`);
    if (!Array.isArray(validation.evidence)) fail(`${at}.validation.evidence`, 'must be an array');

    const kinds = new Set();
    for (const [evidenceIndex, evidence] of (validation.evidence ?? []).entries()) {
      const evidenceAt = `${at}.validation.evidence[${evidenceIndex}]`;
      if (!evidenceKinds.has(evidence?.kind)) fail(`${evidenceAt}.kind`, 'is invalid');
      else kinds.add(evidence.kind);
      if (!nonempty(evidence?.description)) fail(`${evidenceAt}.description`, 'is required');
      const hasPath = nonempty(evidence?.path);
      const hasUrl = nonempty(evidence?.url);
      if (hasPath === hasUrl) fail(evidenceAt, 'must contain exactly one of path or url');
      if (hasPath) {
        const resolved = path.resolve(root, evidence.path);
        if (resolved !== root && !resolved.startsWith(root + path.sep)) fail(`${evidenceAt}.path`, 'escapes the repository');
        else if (!fs.existsSync(resolved)) fail(`${evidenceAt}.path`, `does not exist: ${evidence.path}`);
      }
      if (hasUrl && !/^https:\/\//.test(evidence.url)) fail(`${evidenceAt}.url`, 'must use HTTPS');
    }

    const rank = levelRank.get(validation.level);
    if (rank >= levelRank.get('L1') && !kinds.has('source-review') && !kinds.has('deployment-lock')) fail(`${at}.validation.evidence`, `${validation.level} requires source-review or deployment-lock evidence`);
    if (rank >= levelRank.get('L2') && !kinds.has('import-probe')) fail(`${at}.validation.evidence`, `${validation.level} requires successful import-probe evidence`);
    if (rank >= levelRank.get('L3') && !kinds.has('composition-mount')) fail(`${at}.validation.evidence`, `${validation.level} requires composition-mount evidence`);
    if (rank >= levelRank.get('L4') && !kinds.has('functional-smoke')) fail(`${at}.validation.evidence`, `${validation.level} requires functional-smoke evidence`);
    if ((validation.level === 'L5' || validation.level === 'baseline') && !plugin.source?.commit) fail(`${at}.source.commit`, `${validation.level} requires an exact commit`);
    if ((validation.level === 'L5' || validation.level === 'baseline') && !plugin.artifact) fail(`${at}.artifact`, `${validation.level} requires an immutable artifact`);
    if (validation.level === 'baseline' && !kinds.has('deployment-lock')) fail(`${at}.validation.evidence`, 'baseline requires deployment-lock evidence');
    if (plugin.recommendation === 'recommended' && rank < levelRank.get('L4')) fail(`${at}.recommendation`, 'recommended requires at least L4');

    const security = plugin.security;
    if (!isObject(security)) fail(`${at}.security`, 'is required');
    else {
      for (const field of ['controlsDesktop', 'capturesScreen', 'usesExistingBrowserProfile', 'sendsDataExternally', 'approvalGate']) {
        if (![true, false, null].includes(security[field])) fail(`${at}.security.${field}`, 'must be true, false, or null');
      }
      if (!Array.isArray(security.notes)) fail(`${at}.security.notes`, 'must be an array');
      if (plugin.recommendation === 'recommended' && [security.controlsDesktop, security.capturesScreen, security.usesExistingBrowserProfile, security.sendsDataExternally, security.approvalGate].includes(null)) fail(`${at}.security`, 'recommended plugins cannot have unknown high-impact security fields');
    }

    if (validation.level === 'baseline') {
      if (plugin.id !== 'dsh-github-copilot') fail(at, 'optional integration falsely claims the current locked baseline');
      const locked = deployment.components?.copilotIntegration;
      if (plugin.source.repository !== locked?.source?.repository) fail(`${at}.source.repository`, 'does not match deployment lock');
      if (plugin.source.commit !== locked?.source?.commit) fail(`${at}.source.commit`, 'does not match deployment lock');
      if (plugin.package !== locked?.package?.name) fail(`${at}.package`, 'does not match deployment lock');
      if (plugin.source.release !== locked?.package?.version) fail(`${at}.source.release`, 'does not match deployment lock version');
      if (plugin.artifact?.name !== locked?.package?.artifact?.name) fail(`${at}.artifact.name`, 'does not match deployment lock');
      if (plugin.artifact?.url !== locked?.package?.artifact?.url) fail(`${at}.artifact.url`, 'does not match deployment lock');
      if (plugin.artifact?.sha256 !== locked?.package?.artifact?.sha256) fail(`${at}.artifact.sha256`, 'does not match deployment lock');
      if (plugin.artifact?.releaseTag !== locked?.package?.artifact?.releaseTag) fail(`${at}.artifact.releaseTag`, 'does not match deployment lock');
      if (plugin.artifact?.releaseImmutable !== true || locked?.package?.artifact?.releaseImmutable !== true) fail(`${at}.artifact.releaseImmutable`, 'locked baseline release must be immutable');
      if (plugin.artifact?.checksumManifestUrl !== locked?.package?.artifact?.checksumManifest?.url) fail(`${at}.artifact.checksumManifestUrl`, 'does not match deployment lock');
    }
  }
}

if (errors.length > 0) {
  console.error(`Plugin catalog validation failed (${errors.length}):`);
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log(`Plugin catalog valid: ${catalog.plugins.length} entries, updated ${catalog.updatedAt}.`);
console.log(`Schema enforced: ${path.relative(root, schemaPath)}; baseline matched: ${deployment.deploymentId}.`);

// This validator intentionally has no dependencies. Its local Draft 2020-12 subset
// enforces every keyword used by the published schema; manual checks add repository
// paths, cumulative evidence, dates, and deployment-lock parity.
void deployment;
