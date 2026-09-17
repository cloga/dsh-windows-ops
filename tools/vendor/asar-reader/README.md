# Offline upstream ASAR reader

This directory owns a generated, self-contained CommonJS reader closure from
**`@electron/asar@3.4.1`**, not a locally implemented ASAR or Chromium Pickle parser.
It is intended for Node.js 18+; the original upstream `original-fs` choice is
preserved when running inside Electron. No npm package is needed at runtime.

```js
import { getRawHeader, extractFile, uncache } from './reader.cjs';

// Call only after the caller's archive/header/allocation/path validation.
const raw = getRawHeader(archivePath);
// raw: { headerString: string, header: object, headerSize: number }
try {
  const bytes = extractFile(archivePath, 'package.json', false);
  // bytes is a Buffer. false rejects a file link instead of following it.
} finally {
  uncache(archivePath);
}
```

Public signatures and return values are upstream's:

- `getRawHeader(archivePath)` synchronously reads and parses the header; it does
  not use the filesystem cache.
- `extractFile(archivePath, filename, followLinks = true)` synchronously returns
  a `Buffer`; it does **not** write an extracted file. It reads an adjacent
  `.unpacked` file for an unpacked entry, and caches the archive's filesystem.
- `uncache(archivePath)` evicts that exact cache key and returns whether it existed.

No pack/create/write/extract-to-directory APIs are exported or included in the
filesystem dependency closure. The bundle still performs ordinary in-memory
mutation, including upstream cache and Pickle initialization. "Read-only" means
no filesystem mutation; it is not an untrusted-input security boundary.

## Security boundary belongs to the caller

The upstream implementation is deliberately not rewritten or hardened here.
Before calling it, validate the archive identity and stable path, header size
**before allocation**, serialized header structure, payload offsets/sizes against
the archive bounds, allowed target paths, link/unpacked policy, and extraction
allocation limits. Upstream `readFileSync` does not reject a short payload read;
its allocation is based on entry size. The default link-following behavior is
upstream's, including recursive traversal. Do not infer archive integrity merely
from a successful parse or extraction. Evict the cache before reading a changed
archive, and in `finally` after use. Candidate attestation and adversarial tests
live with the consuming tool, outside this vendor directory.

## Source and licensing evidence

`provenance.json` records the exact official npm source tarball URL and SHA-512
SRI from the existing source worktree's `pnpm-lock.yaml`, the upstream MIT license,
and SHA-256 for every installed source file used by the build. `LICENSE.asar.md`
is the exact upstream license, checked byte-for-byte during builds.

The build uses existing installed upstream source. Direct official npm retrieval
failed with TLS handshake errors; an explicitly approved Microsoft npm proxy
subsequently supplied the exact tarball over strict TLS (one HTTPS redirect to
Microsoft package storage). Its bytes match the **unchanged original npm SHA-512
SRI**. All seven selected package/license/source inputs were independently compared
byte-for-byte against members streamed by the existing Windows `tar.exe`, and
against the recorded SHA-256 hashes. No filesystem extraction or TLS bypass was
used. The 25,591-byte tarball's SHA-256 and permanent acquisition URL are recorded
in `provenance.json`; expiring signed redirect URLs are intentionally not persisted.
The source tarball is not committed to this directory.

Only `@electron/asar` code is redistributed in `reader.cjs`. Its `commander`,
`glob`, and `minimatch` dependencies serve the CLI/writer and are excluded rather
than implicitly resolved. The build-only packages are pinned in `provenance.json`:
`esbuild@0.25.12`, `@esbuild/win32-x64@0.25.12`, and `typescript@6.0.3`. Their exact
lockfile integrities and licenses are recorded; their source/binaries are **not**
redistributed or installed by this recipe. Node built-ins (`fs`, `path`, or
Electron's built-in `original-fs`) are the only external runtime imports.

## Reproduce without installation or downloads

Use an **existing** source worktree with the exact pnpm package paths recorded in
`provenance.json`. This Windows x64 recipe uses the already installed esbuild
binary and TypeScript parser. The initial build used Node.js 24.13.0. Run from the
Windows Ops repository root:

```powershell
$sourceRoot = '<existing-source-worktree>'
node tools/vendor/asar-reader/build.mjs --source-root $sourceRoot --check
# Explicitly regenerate only after reviewing source/tool pins and selector:
node tools/vendor/asar-reader/build.mjs --source-root $sourceRoot --write
node tools/vendor/asar-reader/build.mjs --source-root $sourceRoot --check
```

`--check` builds in memory and compares both generated files byte-for-byte.
`--write` writes **only** `reader.cjs` and `bundle-manifest.json` beside the recipe.
There is no installer, network operation, fixture writer, or source-tree mutation.
Source file hashes, package versions, and the license must match before esbuild
runs. Build dependency SRI values are provenance pins from the source lockfile,
not an independent verification of the installed tool binaries. Generated output
contains stable virtual module names, no local absolute paths or timestamps.

For optional independent source provenance replay, supply the already downloaded
source tarball from an approved private, non-synchronized directory and an
existing `tar` executable. The recipe checks the original SRI, size and SHA-256
before streaming selected tar members and comparing all installed inputs. It
does not download or extract files to disk:

```powershell
node tools/vendor/asar-reader/build.mjs --source-root $sourceRoot --check `
  --source-tarball '<approved-private-directory>/electron-asar-3.4.1.tgz' `
  --tar-executable '<existing-system-tar-executable>'
```

### Maintained reader closure

1. TypeScript parses the hash-pinned upstream compiled JavaScript.
2. Explicit declaration/class-method allowlists select the public reader
   functions and their disk/filesystem/Pickle dependencies. Retained function
   and method bodies are sliced verbatim, not reimplemented. Missing or duplicate
   declarations fail the build; a new upstream version requires explicit review.
3. The only adapter replaces upstream's broad fs-promisification facade with a
   frozen facade of `openSync`, `readSync`, `closeSync`, and `readFileSync`, while
   preserving upstream's Node/Electron fs choice. This removes filesystem writer
   capabilities from the closure without changing the parser or reader methods.
4. esbuild bundles those virtual modules with an explicit external allowlist;
   any unexpected dependency fails the build. Public export wiring exposes only
   the three reader/cache APIs. Pickle's memory-only `resize`/`setPayloadSize`
   helpers remain because the unchanged constructor references them.
5. `bundle-manifest.json` records the artifact hash/size, selected-source hashes,
   exact declaration/method closure, tool versions, exports, and external imports.

To update, review a new upstream release and its license, establish source
provenance/integrity, update the pins and allowlists deliberately, regenerate,
and run the consuming tool's tests including upstream-writer-generated fixtures
and malformed input checks. Do not patch generated `reader.cjs` by hand, add a
handrolled parser, install into the live deployment, or silently follow semver
ranges.
