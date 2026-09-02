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

const catalog = readJson(catalogPath);
const schema = readJson(schemaPath);
const deployment = readJson(lockPath);

if (catalog && schema && deployment) {
  const requiredLevels = ['L0', 'L1', 'L2', 'L3', 'L4', 'L5', 'baseline'];
  const recommendations = new Set(['recommended', 'conditional', 'experimental', 'historical', 'rejected', 'unreviewed']);
  const integrations = new Set(['cordis', 'mcp', 'browser-extension', 'external-service', 'mixed']);
  const evidenceKinds = new Set(['discovery', 'source-review', 'compat-check', 'import-probe', 'composition-mount', 'functional-smoke', 'deployment-lock', 'upstream-change']);
  const levelRank = new Map(requiredLevels.map((level, index) => [level, index]));

  if (catalog.schemaVersion !== 1) fail('catalog', 'schemaVersion must be 1');
  if (!/^\d{4}-\d{2}-\d{2}$/.test(catalog.updatedAt ?? '')) fail('catalog.updatedAt', 'must use YYYY-MM-DD');
  else if (catalog.updatedAt > today) fail('catalog.updatedAt', `future date ${catalog.updatedAt}`);

  const levels = Array.isArray(catalog.validationLevels) ? catalog.validationLevels : [];
  const levelIds = levels.map((entry) => entry?.id);
  if (new Set(levelIds).size !== levelIds.length) fail('catalog.validationLevels', 'contains duplicate ids');
  for (const level of requiredLevels) if (!levelIds.includes(level)) fail('catalog.validationLevels', `missing ${level}`);

  if (!Array.isArray(catalog.plugins)) fail('catalog.plugins', 'must be an array');
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
    if (plugin.artifact !== undefined && (!isObject(plugin.artifact) || !nonempty(plugin.artifact.name) || !/^https:\/\/github\.com\//.test(plugin.artifact.url ?? '') || !/^[0-9a-f]{64}$/.test(plugin.artifact.sha256 ?? ''))) fail(`${at}.artifact`, 'requires name, GitHub HTTPS URL, and lowercase SHA-256');
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
    }
  }
}

if (errors.length > 0) {
  console.error(`Plugin catalog validation failed (${errors.length}):`);
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log(`Plugin catalog valid: ${catalog.plugins.length} entries, updated ${catalog.updatedAt}.`);
console.log(`Schema parsed: ${path.relative(root, schemaPath)}; baseline matched: ${deployment.deploymentId}.`);

// This validator intentionally has no dependencies. JSON Schema documents the public
// shape; this script enforces repository paths, cumulative evidence, dates, and lock parity.
void schema;
void deployment;
