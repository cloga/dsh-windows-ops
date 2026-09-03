# DSH + GitHub Copilot improvement portfolio

This catalog tracks completed integration work, where the durable implementation
is owned, and whether it has reached an external upstream project. The controlled
`cloga/*` forks are described by deployed capability and exact pin, not internal
PR workflow status. External statuses are a point-in-time view as of 2026-09-03:
**Open** does not mean merged or released.

## Ownership and status

### `dsh-web-search-provider`

| Root cause and validated behavior | Owning change | Status | Validation evidence |
|---|---|---|---|
| Responses replay rejected invalid or oversized item IDs. Valid IDs are preserved; invalid IDs become stable, short `fc_` hashes. | [`hiyms/dsh-web-search-provider#3`](https://github.com/hiyms/dsh-web-search-provider/pull/3) | **Open upstream PR** | Focused serialization tests, typecheck, TypeScript compile, and production build passed. |
| Tool calls speculatively requested sandbox escalation. Escalation arguments are now emitted only after an actual DSH sandbox-denial marker. | [`hiyms/dsh-web-search-provider#4`](https://github.com/hiyms/dsh-web-search-provider/pull/4) | **Open upstream PR** | Full tests, typecheck, TypeScript compile, and production build passed. |
| Image-bearing requests entered the custom Responses/web-search wire and bypassed DSH's supported attachment path. Image requests now stay on the official vision channel while text-only web search is unchanged. | [`hiyms/dsh-web-search-provider#5`](https://github.com/hiyms/dsh-web-search-provider/pull/5); deployed from `cloga/dsh-web-search-provider` | **Upstream PR open; fork default branch** | Focused tests 20/20, full suite 157/157, typecheck, declaration emit, and production build passed. See [vision dual-channel design](vision-dual-channel.md). |
| Static model configuration drifted from the Copilot-compatible `/v1/models` catalog. Discovery now accepts standard listings plus optional picker, policy, tools, endpoint, vision, token, and reasoning metadata, with static fallback on failure. | [`hiyms/dsh-web-search-provider#6`](https://github.com/hiyms/dsh-web-search-provider/pull/6); deployed from `cloga/dsh-web-search-provider` | **Upstream PR open; fork default branch** | Full suite 163/163, typecheck, and production build passed. The provider parses the catalog but does not mutate Harness settings. |
| The complete deployment baseline needed replay, sandbox, image, catalog, and orphan filtering fixes under one self-describing artifact. | `cloga/dsh-web-search-provider`, deployment history [`#3`](https://github.com/cloga/dsh-web-search-provider/pull/3) | **Fork default branch** | Linux and Windows CI, 169 tests, typecheck, build, pack, and deployment metadata verification passed. |
| DSH's traditional `Search` tool could not use Copilot hosted search, and empty Responses/Anthropic reasoning items rendered blank Think cards. The provider now registers `copilot-hosted` in `ctx.web` and lazily opens only nonempty reasoning blocks. | `cloga/dsh-web-search-provider`, history [`#4`](https://github.com/cloga/dsh-web-search-provider/pull/4) | **Fork default branch / 0.2.3-cloga.3** | Linux and Windows CI passed; 184 tests, typecheck, seven-capability baseline verification, build, and pack passed. |
| The inline parser incorrectly capped total lifetime SSE bytes, rejecting valid long tool-call streams and reporting `UNKNOWN`. It now bounds only one incomplete event and classifies a genuine oversize event as `INVALID_REQUEST`. | `cloga/dsh-web-search-provider`, historical deployment pin `57dafb1e`, history [`#6`](https://github.com/cloga/dsh-web-search-provider/pull/6) | **Fork history / superseded 0.2.3 pin** | 188/188 tests, typecheck, baseline verification, production build, pack, installed import probe, and an 8,455,113-byte cumulative SSE regression passed. |
| A gateway-backed package duplicated auth, catalog, route, and token concerns already owned by DSH's built-in pi-ai adapter. The current companion reuses that owner while adding the controlled rc.2 client handoff, strict Remote codecs and Host-only grant normalization, authorization fallback, account-aware leaf-only model reconciliation, mixed per-model protocols, provider-scoped Tool Schema filtering, Responses/Anthropic inline search, Responses-only `ctx.web` search, explicit probe-bypass semantics, and validated GitHub-hosted/Enterprise endpoints. Missing profiles are created without connection references; existing profiles preserve unowned fields, while the Windows deployment removes reviewed legacy references. “All-in-one” means one DSH plugin, not an embedded gateway; ACP remains excluded. | [`cloga/dsh-github-copilot#48`](https://github.com/cloga/dsh-github-copilot/pull/48), source `62363304`, merge `adfce229` | **Current locked baseline / immutable Release 0.3.0-cloga.13** | Immutable Release URL, `SHA256SUMS`, artifact hash, exact source/merge commits, 14-capability exported baseline, web/headless profile coherence, packaged current/fresh Session schema-filter proofs, and both tested DSH source baselines are pinned by the Windows operations lock. |

Merged `cloga` fork PRs are deployment inputs, not evidence of acceptance by
`hiyms`. Prefer an upstream release after the matching upstream PR is merged;
until then, treat the fork baseline as an explicit compatibility choice.

### `deepseek-harness`

| Root cause and validated behavior | Owning change and upstream design record | Status | Validation evidence |
|---|---|---|---|
| Standard OpenAI model discovery discarded useful gateway metadata or over-filtered minimal catalogs. Discovery now propagates optional picker, policy, endpoint, token-limit, and reasoning metadata without requiring extensions. | `cloga/deepseek-harness`; upstream [Discussion #4523](https://github.com/deepseek-ai/deepseek-harness/discussions/4523) | **Fork default branch** | Focused tests 158/158; typecheck, build, lint, docs sync, pre-push build, and contract typecheck passed. |
| Onboarding assumed every provider required the same credential, leaving valid custom/OpenAI-compatible configurations blocked or marked unhealthy. Readiness now derives from usable configured providers while retaining real missing-credential errors. | `cloga/deepseek-harness`; upstream [Discussion #4537](https://github.com/deepseek-ai/deepseek-harness/discussions/4537) | **Fork default branch** | Focused tests 93/93, onboarding replay E2E 3/3, complete GUI suite, typecheck, lint, docs sync, and production build passed. |
| Discovered image capability stopped before the registry, RPC, profile, and editor surfaces. Optional gateway vision metadata now becomes `text + image`; absent metadata remains safely text-only. | `cloga/deepseek-harness`; upstream [Discussion #4524](https://github.com/deepseek-ai/deepseek-harness/discussions/4524) | **Fork default branch** | Focused tests 157/157; relevant GUI suite 3,997 passed with 1 skipped; typecheck, build, lint, docs sync, and models-settings E2E passed. |
| The Core lacked a complete, provenance-bearing local release installation and a stable Desktop-facing shim. | `cloga/deepseek-harness` | **Fork default branch** | Complete release closure pack/install, receipt hashes, isolated Web boot, and Desktop shim validation passed. |
| Same-mode or narrower sandbox requests were rejected as invalid escalation. They now retain the effective policy without approval; only strict widening asks once. | `cloga/deepseek-harness`, deployment base `bd520d6e`, retained at pin `a772dbbd` | **Controlled maintenance branch** | Focused bash/pwsh/shared 154/154 and fs 74/74; typecheck, lint, official build, release pack, truthful receipt install, installed-file attestation, and sandbox probe passed. |
| pi-ai OAuth grants could contain own `undefined` members that cannot survive credential JSON/YAML persistence. The Core adapter now recursively rebuilds detached strict JSON, preserves valid provider extension fields, applies JSON array semantics, and rejects cyclic or non-JSON values without disclosing them. | `cloga/deepseek-harness`, originally delivered on `cloga-pi-ai-oauth-json-records`, retained at pin `a772dbbd`; [`cloga/dsh-windows-ops#65`](https://github.com/cloga/dsh-windows-ops/issues/65) | **Current locked baseline / 0.1.1-rc.2** | The pin directly descends from `ec7aa651` and retains installed-file receipt and sandbox fixes. Core credential-store regressions cover the Copilot `enterpriseUrl: undefined` case, recursive normalization, exact round-trip, rejection categories, and redacted diagnostics; the Windows lock and replay manifest independently pin the capability and built markers. |
| A provider route could select only one wire protocol, so mixed Copilot catalogs could not serve Responses and Chat Completions models together. Core now validates `api` on each model entry and resolves it before route and catalog defaults. | `cloga/deepseek-harness`, maintenance branch `cloga-pi-ai-model-api`, pin `a772dbbd`; [`cloga/dsh-windows-ops#68`](https://github.com/cloga/dsh-windows-ops/issues/68) | **Current locked baseline / 0.1.1-rc.2** | The pin retains receipt, sandbox, and OAuth JSON behavior. Core schema, programmatic validation, catalog precedence, streaming, and built replay markers cover mixed-protocol routes. |

These implementations currently belong to the `cloga` fork. The linked upstream
Discussions establish problem and design context, but they are not merged code or
release commitments.

### Desktop shell and Windows operations

| Root cause and validated behavior | Owning change | Status | Validation evidence |
|---|---|---|---|
| A service that became ready after the initial window was left in a stale error state, and silent plugin installs lacked actionable diagnostics. The shell now keeps probing, clears delayed-startup errors, remounts the UI, cancels stale probes, and reports missing manifests. | [`dsh-tauri-desk/deepseek-harness-desktop#118`](https://github.com/dsh-tauri-desk/deepseek-harness-desktop/pull/118) | **Merged** | ESLint, typecheck, Vitest 9/9, production build, `cargo check`, and Rust tests 226/226 passed. The unrelated full-prebuild dependency 404 was explicitly documented. |
| Local integrations needed repeatable detection, exact-marker patching, dry-run, backup, rollback, and recovery rather than one-off machine edits. | [`cloga/dsh-windows-ops#13`](https://github.com/cloga/dsh-windows-ops/pull/13) | **Merged** | Pester 10/10, Windows PowerShell 5.1 self-check, and JavaScript syntax checks passed. See the maintained [replay/self-heal guide and compatibility matrix](windows-replay-tooling.md#compatibility-matrix). |
| Partial upgrades mixed Desktop with old Core/plugin and gateway routes. The check-first installer now pins official Desktop 0.10.2, preserves its seven Profile links plus the non-bundled panel placeholder under `resources\node_modules`, migrates reviewed gateway/route/reference state with backup, and accepts only the built-in pi-ai grant plus reference-free direct route. | `cloga/dsh-windows-ops#53`, `cloga/dsh-windows-ops#72` | **Current deployment baseline** | Combined installer/bootstrap Pester suites, plugin catalog tests, validator, replay self-check, artifact hash verification, and default read-only check define the verification gate. |

### Historical gateway work

| Root cause and validated behavior | Owning change | Status | Validation evidence |
|---|---|---|---|
| The integration boundary was undocumented, causing provider/Harness responsibilities to be mistaken for gateway defects. The guide documents `/v1/responses`, hosted web search, official vision routing, and complete `/v1/models` metadata. | [`cloga/copilot2api@5a042b40`](https://github.com/cloga/copilot2api/commit/5a042b4033a845789da5926bb3beea92c4cd7115); upstream [`whtsky/copilot2api#9`](https://github.com/whtsky/copilot2api/pull/9) | **Upstream PR open** | Fork default branch contains the guide. Markdown structure, links, diff, and sensitive-data checks passed. |

This is migration history only. The current Windows lock keeps its binary,
listener, route, and credential-reference signatures under an explicit legacy
migration contract; none is an active component or success criterion.

### Historical and optional integrations

| Integration | Owning change | Current status | Relationship to the locked baseline |
|---|---|---|---|
| Host-wide isolated Edge testing through `dsh-playwright-host@0.1.0` | [`cloga/dsh-playwright-host@e4c8decc`](https://github.com/cloga/dsh-playwright-host/commit/e4c8decc5c2e6ae815d974049af2dc33e42743d0) | **Optional active overlay** | Cataloged and functionally verified, but not required by the Windows Copilot lock; one Host MCP process is shared across Sessions. |
| Session-bound scheduling through `dsh-cron@0.3.3` | [`cloga/dsh-cron@v0.3.3`](https://github.com/cloga/dsh-cron/releases/tag/v0.3.3) | **Optional active overlay** | Cataloged Web-only scheduler; Windows native notification flags are documented quiet no-ops. |
| Model-aware admission and neutral prompting for the vision-tool fallback | [`tianmingwan/dsh-vision-any#2`](https://github.com/tianmingwan/dsh-vision-any/pull/2) | **Open** | Optional fallback design; not installed by the Windows Copilot lock. |
| Offline-first release resolution and bounded fetch for the desktop-touch MCP launcher | [`Harusame64/desktop-touch-mcp#586`](https://github.com/Harusame64/desktop-touch-mcp/pull/586) | **Merged 2026-08-23** | Historical startup-timeout fix for an optional MCP; not a required Desktop/Core/provider component. |

## Compatibility and maintenance

- Use the [replay/self-heal compatibility matrix](windows-replay-tooling.md#compatibility-matrix)
  as the maintained version reference. It records the validated DSH runtime
  baselines, provider baseline, component detection, and patch lifecycle.
- Before deployment, run `tools\dsh-replay.ps1 -Action SelfCheck`, then
  `-Action Apply -DryRun`. Unknown source markers must remain incompatible rather
  than receiving a guessed patch.
- Update a row only from the linked PR or Discussion. Record `Open`, `Closed`, or
  `Merged` exactly; never infer merge or release status from a working fork.
- When a fix ships upstream, record the first verified release and retire the fork
  or temporary replay path only after the compatibility matrix passes.
- Keep published branch names generic and task-based. Do not include personal,
  employer, device, credential, or local-path identifiers in refs, commits,
  documentation, fixtures, or examples.
- Keep credentials outside the repository and report only behavior, versions,
  test counts, and public links. See [security notes](security-notes.md).
