# DSH + GitHub Copilot improvement portfolio

This catalog tracks completed integration work, where the durable implementation
is owned, and whether it has reached the relevant upstream project. Statuses are
a point-in-time view as of 2026-08-25: **Open** does not mean merged or released.

## Ownership and status

### `dsh-web-search-provider`

| Root cause and validated behavior | Owning change | Status | Validation evidence |
|---|---|---|---|
| Responses replay rejected invalid or oversized item IDs. Valid IDs are preserved; invalid IDs become stable, short `fc_` hashes. | [`hiyms/dsh-web-search-provider#3`](https://github.com/hiyms/dsh-web-search-provider/pull/3) | **Open upstream PR** | Focused serialization tests, typecheck, TypeScript compile, and production build passed. |
| Tool calls speculatively requested sandbox escalation. Escalation arguments are now emitted only after an actual DSH sandbox-denial marker. | [`hiyms/dsh-web-search-provider#4`](https://github.com/hiyms/dsh-web-search-provider/pull/4) | **Open upstream PR** | Full tests, typecheck, TypeScript compile, and production build passed. |
| Image-bearing requests entered the custom Responses/web-search wire and bypassed DSH's supported attachment path. Image requests now stay on the official vision channel while text-only web search is unchanged. | [`hiyms/dsh-web-search-provider#5`](https://github.com/hiyms/dsh-web-search-provider/pull/5); fork staging change [`cloga/dsh-web-search-provider#1`](https://github.com/cloga/dsh-web-search-provider/pull/1) | **Both open**; upstream owns the durable destination | Focused tests 20/20, full suite 157/157, typecheck, declaration emit, and production build passed. See [vision dual-channel design](vision-dual-channel.md). |
| Static model configuration drifted from the Copilot-compatible `/v1/models` catalog. Discovery now accepts standard listings plus optional picker, policy, tools, endpoint, vision, token, and reasoning metadata, with static fallback on failure. | [`hiyms/dsh-web-search-provider#6`](https://github.com/hiyms/dsh-web-search-provider/pull/6); fork staging change [`cloga/dsh-web-search-provider#2`](https://github.com/cloga/dsh-web-search-provider/pull/2) | **Both open**; upstream owns the durable destination | Full suite 163/163, typecheck, and production build passed. The provider parses the catalog but does not mutate Harness settings. |

The `cloga` fork PRs are reviewable staging points for changes also proposed to
`hiyms`. They are not evidence of upstream acceptance. Prefer an upstream release
after the matching upstream PR is merged; until then, treat fork deployment as an
explicit compatibility choice.

### `deepseek-harness`

| Root cause and validated behavior | Owning change and upstream design record | Status | Validation evidence |
|---|---|---|---|
| Standard OpenAI model discovery discarded useful gateway metadata or over-filtered minimal catalogs. Discovery now propagates optional picker, policy, endpoint, token-limit, and reasoning metadata without requiring extensions. | [`cloga/deepseek-harness#1`](https://github.com/cloga/deepseek-harness/pull/1); upstream [Discussion #4523](https://github.com/deepseek-ai/deepseek-harness/discussions/4523) | **Open fork PR**; upstream discussion records the design seam | Focused tests 158/158; typecheck, build, lint, docs sync, pre-push build, and contract typecheck passed. Full suite passed 13,960 tests with 21 documented pre-existing Windows/Oxlint failures. |
| Onboarding assumed every provider required the same credential, leaving valid custom/OpenAI-compatible configurations blocked or marked unhealthy. Readiness now derives from usable configured providers while retaining real missing-credential errors. | [`cloga/deepseek-harness#2`](https://github.com/cloga/deepseek-harness/pull/2); upstream [Discussion #4537](https://github.com/deepseek-ai/deepseek-harness/discussions/4537) | **Open fork PR**; upstream discussion records the UX issue | Focused tests 93/93, onboarding replay E2E 3/3, complete GUI suite, typecheck, lint, docs sync, and production build passed. Broader Windows web failures were documented as unrelated fixtures/tooling issues. |
| Discovered image capability stopped before the registry, RPC, profile, and editor surfaces. Optional gateway vision metadata now becomes `text + image`; absent metadata remains safely text-only. | [`cloga/deepseek-harness#3`](https://github.com/cloga/deepseek-harness/pull/3); upstream [Discussion #4524](https://github.com/deepseek-ai/deepseek-harness/discussions/4524) | **Open fork PR**; upstream discussion records the capability gap | Focused tests 157/157; relevant GUI suite 3,997 passed with 1 skipped; typecheck, build, lint, docs sync, models-settings E2E 11/11, pre-push build, and contract typecheck passed. |

These implementations currently belong to the `cloga` fork. The linked upstream
Discussions establish problem and design context, but they are not merged code or
release commitments.

### Desktop shell and Windows operations

| Root cause and validated behavior | Owning change | Status | Validation evidence |
|---|---|---|---|
| A service that became ready after the initial window was left in a stale error state, and silent plugin installs lacked actionable diagnostics. The shell now keeps probing, clears delayed-startup errors, remounts the UI, cancels stale probes, and reports missing manifests. | [`dsh-tauri-desk/deepseek-harness-desktop#118`](https://github.com/dsh-tauri-desk/deepseek-harness-desktop/pull/118) | **Merged** | ESLint, typecheck, Vitest 9/9, production build, `cargo check`, and Rust tests 226/226 passed. The unrelated full-prebuild dependency 404 was explicitly documented. See [Tauri A/B adaptation](ab-tauri-adapt.md). |
| Local integrations needed repeatable detection, exact-marker patching, dry-run, backup, rollback, and recovery rather than one-off machine edits. | [`cloga/dsh-windows-ops#13`](https://github.com/cloga/dsh-windows-ops/pull/13) | **Merged** | Pester 10/10, Windows PowerShell 5.1 self-check, and JavaScript syntax checks passed. See the maintained [replay/self-heal guide and compatibility matrix](windows-replay-tooling.md#compatibility-matrix). |

### `copilot2api`

| Root cause and validated behavior | Owning change | Status | Validation evidence |
|---|---|---|---|
| The integration boundary was undocumented, causing provider/Harness responsibilities to be mistaken for gateway defects. The guide documents `/v1/responses`, hosted web search, official vision routing, and complete `/v1/models` metadata. | [`whtsky/copilot2api#9`](https://github.com/whtsky/copilot2api/pull/9) | **Open documentation PR** | Markdown structure, links, diff, and sensitive-data checks passed. |

Copilot2API did **not** require a functional fix for this portfolio. Replay
serialization, sandbox cleanup, image routing, picker filtering, and Harness
settings synchronization are owned by the provider or Harness layers above.

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
