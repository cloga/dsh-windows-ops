# Desktop plugin sources and snapshot recovery

## Availability and ownership

**Source-snapshot installation was first published in historical Desktop `0.1.5-rc.3.cloga.7`; publication is not local installation or activation.** The implementation for [deepseek-harness #50](https://github.com/cloga/deepseek-harness/issues/50) merged in [PR #53](https://github.com/cloga/deepseek-harness/pull/53) on 2026-09-17 at commit [`b8b94437f288fe2dce792a029cbff610101e0319`](https://github.com/cloga/deepseek-harness/commit/b8b94437f288fe2dce792a029cbff610101e0319). Release-plan [PR #57](https://github.com/cloga/deepseek-harness/pull/57) led to the formally published immutable [`.cloga.7` Release](https://github.com/cloga/deepseek-harness/releases/tag/dsh-desktop-v0.1.5-rc.3.cloga.7), ID `390421989`, sequence 9, published `2026-09-17T03:51:36Z`, from source `293b5a79f533005d99cd60cb00b9ecf810187401` (tree `de807cc4c582f3bb6e2829ea98758e98ec5e576c`; reviewed head `acf99f2038c42cafa076d4aff69f01f43260c988`). That `.cloga.7` record remains historical. The [deployment lock](../../deployments/windows-copilot.lock.json) now selects published `0.1.6-alpha.1.cloga.2` / Core `0.1.6-alpha.1` / Copilot alpha.24, immutable Release `391052820`, sequence 12, source `65a236bd65f2971f98b11a0efd020b8860144924` from PR #63. Formal run `35271210350` passed source initial/restart account/settings DOM, read-only search catalog and graph/ancestor acceptance; current native Ops qualification remains pending. Historical [Ops observer run `35210215981`](https://github.com/cloga/dsh-windows-ops/actions/runs/35210215981) at code head `83b0303c250b62f55424be3d88347bf147c593d8` qualifies only `.cloga.1`/alpha.22. Its [scoped summary and exclusions](../local-core-desktop-copilot.md#scoped-ops-ci-qualification) do not establish end-to-end source-plugin/Memory Evolve activation or advanced private-peer/custom-home/missing-addon negatives. Publication and repinning do not upgrade an installed Desktop or activate a plugin. Use these procedures only after the complete qualified Desktop is installed through its consent-gated native flow. Do not replace its bundled runtime independently or assume an older npm-only plugin window accepts source inputs.

**当前目标：已发布 Desktop `0.1.6-alpha.1.cloga.2`（sequence 12）/ Core `.6` / Copilot alpha.24，当前 Native Ops qualification 待完成，本机仍未安装或激活。** 核心 PR #53 / PR #57 的 `.cloga.7` 首次发布记录仍保留为历史证据；当前配套版本来自 PR #63 和正式 run `35271210350`，实际设置 DOM/只读搜索目录验收不代表真实搜索、OAuth/model round 或本机升级。使用下述来源输入前须通过原生、经明确同意的流程安装完整已验证 Desktop；Memory Evolve 仍未激活，获取和校验成功不等于可信、功能验证或纳入正式基线。

The reserved `$DSH_HOME/profiles/desktop` belongs to Desktop's native transaction owner. Install, remove, and reinstall through that owner's plugin-management flow. Do not run a generic CLI, `pnpm add`, `pnpm install`, `pnpm rebuild`, or package-store repair against the reserved profile; do not copy `node_modules` into it. Windows Ops continues to delegate through the selected native provisioning mode rather than becoming a second profile writer. The [deployment guide](../local-core-desktop-copilot.md) and [native provisioning removal runbook](../official-desktop-plugin-provisioning-removal.md) retain their existing responsibilities.

The current Host uses the locked Electron EXE in Node mode with
`resources/app.asar/dsh` and runtime resolution generations; packaged pnpm and
the update helper still use physical bundled upstream Node. The read-only Ops
checker preserves explicit user/release receipt ownership (or conservative
in-memory legacy inference). Required Copilot proof stays exact even if
user-owned; user verified/registry/snapshot extras are permitted metadata with
`contentsAttested:false`, not baseline health or archive-integrity proof.
No check-time ownership migration, Core copy or generic CLI workaround is used.

## Three installation paths

| Path | What is selected | What the result establishes |
|---|---|---|
| npm registry | Package name with a version, tag, or semver range | An exact resolved registry version; **Update** selects another registry version. |
| Verified GitHub Release | The reviewed native `githubRelease` source lock and its immutable package/checksum assets | Release, asset, commit, package identity, and byte checks under the existing verified-release transaction. Use the verified channel to update; do not replace it with a registry package or source URL. |
| Source snapshot | Public GitHub repository, local directory, local archive, or HTTPS archive | A validated, profile-owned package snapshot with requested spec, resolved origin, and byte hashes. **Reinstall from source** reacquires the chosen source; it is not a registry version update. |

A repository archive and a GitHub Release asset are not interchangeable. A source package's SHA-256/SHA-512 identifies its bytes, not its publisher, safety, or an immutable Release assertion. Acquisition does not import the plugin, execute its application code, prove runtime compatibility, or grant the verified-release receipt guarantees.

## Inputs for a source-capable build

The native plugin window's general source field follows the [published Desktop input and snapshot rules](https://github.com/cloga/deepseek-harness/blob/65a236bd65f2971f98b11a0efd020b8860144924/apps/desktop/README.md#plugin-sources-and-snapshots), including the legacy source-input normalization repair in that release. Examples describe input syntax, not permission to install a particular package.

| Source | Accepted examples | Important distinction |
|---|---|---|
| npm registry | `plugin`, `@scope/plugin@next`, `plugin@^1.2.0` | A bare name is a registry package, not a local directory. |
| Public GitHub | `github:owner/repo#ref`, `owner/repo#ref`, `https://github.com/owner/repo.git#ref`, or the same GitHub URL with `git+https` | Omit `#ref` for the default HEAD; branches, tags, full commits, and branch names with slashes are supported. |
| Local directory | An absolute Windows/POSIX path, explicit `./plugin` or `../plugin`, `file:<path>`, `link:<path>` | `link:` still creates a packed snapshot, never a durable live link. |
| Local package archive | An explicit path or `file:<path>` ending in `.tgz` or `.tar.gz` | The input is copied into staging before archive validation. |
| HTTPS package archive | `https://packages.example/plugin.tgz` or an HTTPS `.tar.gz` URL | No credentials, query, fragment, or custom port; redirects remain subject to transport validation. |

GitHub acquisition uses the public credential-free API to resolve a requested ref to a full 40-hex commit and downloads an archive of that commit through approved GitHub HTTPS hosts, including `codeload.github.com`. It does not invoke Git preparation. Arbitrary Git hosts, SSH, HTTP, private-repository authentication, credential-bearing URLs, revision expressions, and `semver:` Git selectors are unsupported. A local Git checkout is a directory input; its branch name is not a durable package link.

Archives have finite compressed, extracted, and entry-count limits. Traversal, absolute/drive paths, backslashes, links, duplicate/case-colliding paths, and multiple top-level roots are rejected. GitHub archives have one repository root; npm package archives require `package/`. A repository's name does not determine the package name: the package manifest is authoritative.

## Prebuilt-only source packages

Before trying an installation, inspect the selected package as data and review its privileges. It must declare a valid package name, an exact semver version, `dsh.bundle.patch`, and existing regular in-package targets for its declared main/root/client exports. A missing built file is an actionable error: obtain a reviewed prebuilt package or build it separately in an appropriately isolated development environment. Desktop does not auto-build it.

Source acquisition rejects root `preinstall`, `install`, and `postinstall` hooks, root `binding.gyp`, bundled dependencies, and nonregistry direct runtime dependencies. File, link, Git, URL, workspace, and npm-alias dependency selectors are not a workaround. Direct dependencies and optional dependencies must use registry versions, tags, or semver ranges; peers use semver ranges and remain subject to Desktop's shared-package rules.

Declared `prepare`, `prepack`, `postpack`, and `build` scripts are inert during acquisition. Packing disables source lifecycle/PNPM hooks and automatic package-manager switching; it preserves the complete package, including relative imports and assets, then revalidates the packed archive. This is not a promise that all transitive registry dependencies execute zero scripts: their reviewed native builds retain Desktop's existing `allowBuilds` policy.

## Reinstallation, snapshot retention, and recovery

1. **Arrange maintenance before a plugin transaction.** Query the actual Desktop's live Session inventory, list the work a Host restart would interrupt, and obtain explicit acknowledgement before proceeding. If the inventory is unavailable, stop rather than assuming no Sessions exist. Do not restart the application's Host to test an acquisition result.
2. **Review the editor before confirming.** Registry **Update** asks for a version. **Reinstall from source** shows the original requested source and allows edits. A stored local `file:` resolution becomes an explicit absolute path instead of replaying an old relative path against a different working directory; an unsafe or unavailable local resolution requires re-entry. Cancel, Escape, or an empty value performs no installation.
3. **Expect explicit source reinstalls to change bytes.** Reusing a branch/tag spec can resolve a new commit even when the package version is unchanged. Ordinary restarts and frozen profile reconstruction reuse the retained snapshot; they do not resolve the moving ref again.
4. **Keep the profile-owned artifact and lock together.** Desktop stores `.desktop-plugin-artifacts/<sha256>.tgz` and `desktop-plugin-package-locks.json`. The lock records the requested spec, resolved origin, optional GitHub commit, package identity, SHA-256, and SHA-512 integrity. These snapshots can outlive the original checkout or downloaded input. Do not manually rewrite the lock, replace a snapshot, or turn it into a symlink.
5. **Remove a broken snapshot, then install the reviewed source again.** Missing or corrupt snapshot packages remain listable/removable. Removal excludes that target before reconstructing retained dependencies. Directly reinstalling the damaged snapshot or disabling it is not a repair guarantee. Corruption in a different retained package stops the transaction before the active Host is stopped; address that package rather than forcing a shared store rebuild.
6. **Preserve application data.** Package removal is not a request to erase shared tasks or plugin-owned memories. In particular, Memory Evolve's reviewed defaults include `$DSH_HOME/memories` and separate skill writes; do not delete those trees, reset the Harness home, or substitute a broad Desktop reset for targeted package recovery. Review any plugin-specific data cleanup separately with the user.

Desktop stages and validates the replacement graph, performs the staged health check, and owns activation/rollback. A successful acquisition is not a successful health check. A failed activation must preserve the prior profile; if rollback recovery itself fails, retain its journal and named transaction directories for the native owner instead of deleting them manually.

## Evidence recorded for issue #50

These observations were recorded during the pre-merge implementation at [`fee04fb069b18960f0f76c7893635bbea7750812`](https://github.com/cloga/deepseek-harness/commit/fee04fb069b18960f0f76c7893635bbea7750812) and remain deliberately separate. Updating the published-code reference does not repeat or broaden that original evidence. These observations do not change the [catalog validation level](plugin-validation.md) or prove local deployment; the later `.cloga.7` publication and baseline repin rely on separate formal release evidence, not these pre-merge observations.

| Observation | Established | Not established |
|---|---|---|
| Memory Evolve source at [`c337dc1af7b5c8a5578e03150bf5c4d6133f66f9`](https://github.com/csyangwen/dsh-memory-evolve/tree/c337dc1af7b5c8a5578e03150bf5c4d6133f66f9) | The new acquisition code obtained, packed, and validated this exact public source without Host activation. One local packed output was 5,684,917 bytes, SHA-256 `7a58618e37092c6ce2336ad21a90643a1c34b39bf8d73a541869aff40a1dbc5d`. | This is not an upstream package Release checksum, a deterministic-repack guarantee, a publisher attestation, a DSH mount, or functional/security acceptance. The candidate remains `L1`/`experimental`. |
| Then-installed Desktop baseline (pre-merge observation) | Its actual native plugin window was opened and read through the application menu, then only that window was closed. It still showed the npm-only label. | The source feature was not deployed in that observation, and the main Desktop/Host was not restarted or replaced; later publication does not change this historical result. |
| Changed source renderer | The actual edited renderer files were exercised in an isolated Edge context in English and Chinese with a mocked Desktop bridge; source editing/reinstallation and registry version flows passed with zero page/network errors. | This was not a native Electron installation or a live source-plugin activation. No real Session screenshots are published here. |
| Real bundled-pnpm fixtures | Isolated installation, removal, and rollback paths passed using real package-manager operations and local fixture packages. | Fixture health does not prove compatibility or safety of Memory Evolve or another third-party plugin. |

The later `.cloga.7` formal run `35178158751` built and published on attempt 1. Only remote-check initially received HTTP 403; the failed-job-only rerun succeeded on attempt 2 without an artifact rebuild or overwrite. Archived formal acceptance artifact `10479574730` establishes isolated packaged Electron initial/restart Copilot Models account UI, graph/ancestor isolation, and standalone helper ACK/cancel. It does **not** establish OAuth, a model round, a local installer upgrade, or an installed end-to-end Memory Evolve/source-plugin workflow. Those historical bytes remain in the [retained cloga.7 formal manifest](../../tests/fixtures/desktop-native-verified-release/formal-cloga7/release.json); the [baseline guide](../local-core-desktop-copilot.md#authoritative-baseline) now records the separate `.6.cloga.2`/alpha.24 target, its formal settings acceptance, and pending current native Ops qualification. The successful Ops run `35210215981` belongs only to historical `.cloga.1`/alpha.22. None of these records is installer execution or a local Desktop change.

Native Desktop uses the `dsh-app://` scheme and parent-owned byte pipes, not a listening service at `127.0.0.1:3080`. A legacy Web-port smoke cannot attest that native window, and a replacement server must not be launched merely to claim Desktop GUI coverage. Acquisition, fixture transactions, source-renderer interaction, packaged/native acceptance, and an installed end-to-end plugin workflow remain distinct evidence steps.

See [choosing a plugin](choosing-a-plugin.md#user-reported-high-privilege-candidates) before evaluating Memory Evolve's persistent memory, automatic edits, external CLI, Git synchronization, or messaging capabilities. The absence of Release package assets is not permission to lower the verified-release channel's checks; source snapshots are a separate opt-in installation path in a qualified build.
