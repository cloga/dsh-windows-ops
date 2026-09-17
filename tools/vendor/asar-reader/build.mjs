#!/usr/bin/env node
// Build-time only. No package installation, network access, or archive parser.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

const here = path.dirname(fileURLToPath(import.meta.url));
const require = createRequire(import.meta.url);
const lock = JSON.parse(fs.readFileSync(path.join(here, 'provenance.json'), 'utf8'));
const args = process.argv.slice(2);
const options = new Map();
const valued = new Set(['--source-root', '--source-tarball', '--tar-executable']);
for (let i = 0; i < args.length; i++) {
  const option = args[i];
  if ((!valued.has(option) && !['--write', '--check'].includes(option)) || options.has(option)) {
    throw new Error(`Unknown or duplicate option: ${option}`);
  }
  if (valued.has(option)) {
    const value = args[++i];
    if (!value || value.startsWith('--')) throw new Error(`Missing value: ${option}`);
    options.set(option, value);
  } else {
    options.set(option, true);
  }
}
if (!options.has('--source-root') || options.has('--write') === options.has('--check') ||
    (options.has('--tar-executable') && !options.has('--source-tarball'))) {
  throw new Error('Usage: node tools/vendor/asar-reader/build.mjs --source-root <existing-source-worktree> (--check | --write) [--source-tarball <verified-source.tgz> [--tar-executable <existing-tar>]]');
}
const sourceRoot = path.resolve(options.get('--source-root'));
const sha256 = (value) => crypto.createHash('sha256').update(value).digest('hex');
const upstream = path.join(sourceRoot, lock.upstream.packageRelativePath);
const sources = new Map();
for (const [name, expected] of Object.entries(lock.upstream.filesSha256)) {
  const bytes = fs.readFileSync(path.join(upstream, name));
  if (sha256(bytes) !== expected) throw new Error(`Upstream source hash mismatch: ${name}`);
  sources.set(name, bytes.toString('utf8'));
}
if (options.has('--source-tarball')) {
  const archive = path.resolve(options.get('--source-tarball'));
  const bytes = fs.readFileSync(archive);
  const integrity = `sha512-${crypto.createHash('sha512').update(bytes).digest('base64')}`;
  if (integrity !== lock.upstream.integrity || bytes.length !== lock.upstream.verifiedTarball.bytes ||
      sha256(bytes) !== lock.upstream.verifiedTarball.sha256) {
    throw new Error('Source tarball differs from the original locked npm identity');
  }
  const tar = options.get('--tar-executable') || (process.platform === 'win32' ? 'tar.exe' : 'tar');
  for (const [name, expected] of Object.entries(lock.upstream.filesSha256)) {
    const extracted = spawnSync(tar, ['-xOf', archive, `package/${name}`], {
      encoding: null, maxBuffer: 1024 * 1024, timeout: 30000,
    });
    if (extracted.error) throw extracted.error;
    if (extracted.status !== 0) throw new Error(`Source tar member read failed: ${name}`);
    if (sha256(extracted.stdout) !== expected || !extracted.stdout.equals(Buffer.from(sources.get(name)))) {
      throw new Error(`Source tar member differs from pinned installed bytes: ${name}`);
    }
  }
  console.log('Verified original source tarball SRI and all seven installed source/license inputs');
}
const pkg = JSON.parse(sources.get('package.json'));
if (pkg.name !== lock.upstream.name || pkg.version !== lock.upstream.version) throw new Error('Wrong upstream package');
if (!fs.readFileSync(path.join(here, 'LICENSE.asar.md')).equals(Buffer.from(sources.get('LICENSE.md')))) {
  throw new Error('Vendored upstream license differs from pinned source');
}
for (const [name, pin] of Object.entries(lock.buildDependencies)) {
  const installed = JSON.parse(fs.readFileSync(path.join(sourceRoot, pin.packageRelativePath, 'package.json'), 'utf8'));
  if (installed.name !== name || installed.version !== pin.version) throw new Error(`Wrong build dependency: ${name}`);
}
const ts = require(path.join(sourceRoot, lock.buildDependencies.typescript.packageRelativePath, 'lib/typescript.js'));
const esbuild = require(path.join(sourceRoot, lock.buildDependencies.esbuild.packageRelativePath, 'lib/main.js'));

// This is a declaration/method allowlist, not an implementation of ASAR or
// Chromium Pickle. Every retained declaration/method body is sliced verbatim
// from hash-pinned upstream JavaScript using the maintained TypeScript AST.
const interop = ['__createBinding', '__setModuleDefault', '__importStar'];
const plans = {
  'asar.js': {
    declarations: [...interop, 'disk', 'getRawHeader', 'extractFile', 'uncache'],
    exports: ['getRawHeader', 'extractFile', 'uncache'],
  },
  'disk.js': {
    declarations: [...interop, '__importDefault', 'path', 'wrapped_fs_1', 'pickle_1', 'filesystem_1',
      'filesystemCache', 'readArchiveHeaderSync', 'readFilesystemSync', 'uncacheFilesystem', 'readFileSync'],
    exports: ['readArchiveHeaderSync', 'readFilesystemSync', 'uncacheFilesystem', 'readFileSync'],
  },
  'filesystem.js': {
    declarations: [...interop, 'path', 'Filesystem'],
    classes: { Filesystem: ['constructor', 'getRootPath', 'getHeaderSize', 'setHeader',
      'searchNodeFromDirectory', 'getNode', 'getFile'] },
    exports: ['Filesystem'],
  },
  'pickle.js': {
    declarations: ['SIZE_INT32', 'SIZE_UINT32', 'PAYLOAD_UNIT', 'CAPACITY_READ_ONLY', 'alignInt', 'PickleIterator', 'Pickle'],
    classes: {
      PickleIterator: ['constructor', 'readInt', 'readUInt32', 'readString', 'readBytes',
        'getReadPayloadOffsetAndAdvance', 'advance'],
      // resize/setPayloadSize are required by the untouched constructor's
      // empty-buffer branch; they mutate memory only and are not public APIs.
      Pickle: ['constructor', 'createFromBuffer', 'getHeader', 'getHeaderSize', 'createIterator',
        'setPayloadSize', 'getPayloadSize', 'resize'],
    },
    exports: ['Pickle'],
  },
  'wrapped-fs.js': { declarations: ['fs'], exports: [] },
};

function selectModule(name) {
  const text = sources.get(`lib/${name}`);
  const ast = ts.createSourceFile(name, text, ts.ScriptTarget.Latest, true, ts.ScriptKind.JS);
  if (ast.parseDiagnostics.length) throw new Error(`Cannot parse pinned module: ${name}`);
  const plan = plans[name];
  const selected = [];
  const seen = new Set();
  for (const statement of ast.statements) {
    let declarationName;
    if (ts.isFunctionDeclaration(statement) || ts.isClassDeclaration(statement)) {
      declarationName = statement.name?.text;
    } else if (ts.isVariableStatement(statement) && statement.declarationList.declarations.length === 1) {
      const declaration = statement.declarationList.declarations[0];
      if (ts.isIdentifier(declaration.name)) declarationName = declaration.name.text;
    }
    if (!plan.declarations.includes(declarationName)) continue;
    if (seen.has(declarationName)) throw new Error(`Duplicate declaration: ${name}:${declarationName}`);
    seen.add(declarationName);
    if (ts.isClassDeclaration(statement) && plan.classes?.[declarationName]) {
      const keep = plan.classes[declarationName];
      const methods = new Map(statement.members.map((member) => [
        ts.isConstructorDeclaration(member) ? 'constructor' : member.name?.getText(ast), member,
      ]));
      const retained = keep.map((method) => {
        if (!methods.has(method)) throw new Error(`Missing method: ${name}:${declarationName}.${method}`);
        return methods.get(method).getText(ast);
      });
      selected.push(`class ${declarationName} {\n${retained.join('\n')}\n}`);
    } else {
      selected.push(statement.getText(ast));
    }
  }
  for (const declaration of plan.declarations) {
    if (!seen.has(declaration)) throw new Error(`Missing declaration: ${name}:${declaration}`);
  }
  const exports = plan.exports.map((name) => `exports.${name} = ${name};`);
  if (name === 'wrapped-fs.js') {
    // The sole adapter: retain upstream's Node/Electron fs choice, but expose
    // only the four synchronous read operations consumed by disk.js. No
    // promisification, directory creation, stream writing or writer fs methods.
    exports.push('exports.default = Object.freeze({ openSync: fs.openSync, readSync: fs.readSync, closeSync: fs.closeSync, readFileSync: fs.readFileSync });');
  }
  return ['"use strict";', 'Object.defineProperty(exports, "__esModule", { value: true });',
    ...selected, ...exports, ''].join('\n');
}

const modules = Object.fromEntries(Object.keys(plans).map((name) => [name, selectModule(name)]));
const result = await esbuild.build({
  stdin: {
    contents: "const reader = require('./asar'); exports.getRawHeader = reader.getRawHeader; exports.extractFile = reader.extractFile; exports.uncache = reader.uncache;",
    sourcefile: 'reader-entry.cjs',
    resolveDir: here,
  },
  bundle: true,
  platform: 'node',
  format: 'cjs',
  target: ['node18'],
  charset: 'utf8',
  minify: false,
  sourcemap: false,
  legalComments: 'none',
  treeShaking: true,
  write: false,
  metafile: true,
  logLevel: 'silent',
  banner: { js: '// GENERATED by build.mjs; do not edit. @electron/asar 3.4.1 reader closure.\n// MIT: Copyright (c) 2014 GitHub Inc. See LICENSE.asar.md and provenance.json.' },
  plugins: [{
    name: 'pinned-reader-closure',
    setup(build) {
      build.onResolve({ filter: /.*/ }, ({ path: request }) => {
        if (['fs', 'path', 'original-fs'].includes(request)) return { path: request, external: true };
        const name = `${request.replace(/^\.\//, '').replace(/\.js$/, '')}.js`;
        if (!Object.hasOwn(modules, name)) throw new Error(`Unexpected dependency: ${request}`);
        return { path: name, namespace: 'upstream-reader' };
      });
      build.onLoad({ filter: /.*/, namespace: 'upstream-reader' }, ({ path: name }) => ({ contents: modules[name], loader: 'js' }));
    },
  }],
});
const output = result.outputFiles[0].contents;
const metadata = {
  schemaVersion: 1,
  artifact: 'reader.cjs',
  sha256: sha256(output),
  bytes: output.length,
  upstream: `${pkg.name}@${pkg.version}`,
  bundler: `esbuild@${esbuild.version}`,
  selector: `typescript@${ts.version}`,
  exports: lock.publicExports,
  closure: Object.fromEntries(Object.keys(plans).map((name) => [name, {
    declarations: plans[name].declarations,
    ...(plans[name].classes ? { classes: plans[name].classes } : {}),
    selectedSourceSha256: sha256(modules[name]),
  }])),
  externalImports: [...new Set(Object.values(result.metafile.outputs).flatMap((entry) => entry.imports.map((item) => item.path)))].sort(),
};
const generated = new Map([
  ['reader.cjs', Buffer.from(output)],
  ['bundle-manifest.json', Buffer.from(`${JSON.stringify(metadata, null, 2)}\n`)],
]);
for (const [name, bytes] of generated) {
  const destination = path.join(here, name);
  if (options.has('--write')) {
    fs.writeFileSync(destination, bytes);
  } else if (!fs.readFileSync(destination).equals(bytes)) {
    throw new Error(`Non-reproducible or stale generated file: ${name}`);
  }
}
console.log(`${options.has('--write') ? 'Generated' : 'Verified byte-for-byte'} reader.cjs (${output.length} bytes, SHA-256 ${metadata.sha256})`);
