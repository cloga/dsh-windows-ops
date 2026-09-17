# DSH 0.1.6-alpha.2 official-first assessment

## Scope and evidence limits

Tracking: [Ops #181](https://github.com/cloga/dsh-windows-ops/issues/181).
Official target: [dsh-v0.1.6-alpha.2](https://github.com/deepseek-ai/deepseek-harness/releases/tag/dsh-v0.1.6-alpha.2), exact commit `ddefc45fbc7f8e46dd73185e68295696d1297887`.

This is a source-review assessment and migration worklist, **not** a qualified
deployment lock, installed-state report or runtime acceptance. The existing
`deployments/windows-copilot.lock.json` remains authoritative until replacement
artifacts are independently qualified. No installation or restart is authorized
by this document. Follow [the upgrade workflow](core-upgrade.md).

本页记录源码对照和迁移决定，不代表 alpha.2 已适配、已部署或可直接升级。
优先官方实现，但不能因为功能同名就丢失日历调度、冷会话恢复、完整性校验或账号权限保证。
现有部署锁保持不变；安装和重启仍另行授权。

## Audited starting points

| Component | Audited source | Starting release | Adaptation tracking |
|---|---|---|---|
| Core fork/Desktop | `65a236bd65f2971f98b11a0efd020b8860144924` | `dsh-desktop-v0.1.6-alpha.1.cloga.2` | [Core #67](https://github.com/cloga/deepseek-harness/issues/67) |
| Copilot | `e49bf7c9307cf22dd9ea720bed8750101fc986ed` | `v0.4.0-alpha.24` | [Copilot #139](https://github.com/cloga/dsh-github-copilot/issues/139) |
| cron | `6f5f9f77e00c2f18838ec48c26543eb608bbc441` | `v0.7.2` | [cron #49](https://github.com/cloga/dsh-cron/issues/49) |
| Playwright Host | `fdec939b48d14d66d14bef3d8f12ec68411d58fb` | `v0.1.7` | [Playwright #20](https://github.com/cloga/dsh-playwright-host/issues/20) |

Source pins above are review inputs, not automatic promotion of those versions to
alpha.2 compatibility. Open Core #59 and Ops #180 are separate work and must not be
silently included or declared qualified by this upgrade.

## Decisions by customization

| Purpose / customization | Official parity | Decision and concrete gap | Retirement condition / migration safeguards |
|---|---|---|---|
| Desktop Plugin Manager UI, live enable/disable | Complete management primitives; fork integration unverified | Migrate to official management/UI; do not carry the old fork renderer unchanged | Preserve user-installed plugins, settings and exact profile lock ownership; qualify disable/re-enable, rollback and deferred replacement |
| Verified GitHub Release installation and source snapshots | Partial: official accepts git/path/tarball syntax, not equivalent reviewed Release identity | Retain only narrow acquisition/integrity adapters integrated with the official transaction owner | Retire after official supports pinned asset/commit/hash validation, safe immutable snapshot acquisition and equivalent rollback; no plain URL/name parity claims |
| Desktop Host and runtime resolution | Official architecture changed | Migrate to official `runProfile` and runtime-resolution model, reattach justified integrity/update hooks | Qualify Electron/Host start, authentication, external dependency resolution, native addons, user plugin preservation and restart; old byte-pipe/link tests do not certify new topology |
| Plugin ancestor-SDK isolation | Partial: official runtime/link/dual resolver still has native ancestor fallback | Use official resolution generation and retain only fork import-policy guard | Retire when official prevents unintended ancestor SDK imports in ESM/CJS and nested Workers while preserving Host shared class identity; no parallel resolver or profile-link rebuilding |
| Windows filesystem identity and multiline goal editing | Absent from inspected official implementations | Retain Windows birthtime-based stability and multiline goal/pending-edit guards | Retire after official stable Windows file-version tests and multiline Ctrl/Cmd+Enter plus pending-Escape acceptance pass |
| Copilot OAuth/native transport | Complete primitives, partial account UX | Reuse official OAuth/adapter; retain narrow account controller and dynamic entitlement metadata | Retire custom glue when native current-account models, supported protocols, TTL/cancellation and unknown-model behavior meet acceptance; preserve credential and Session ownership |
| Planner/executor model roles | Partial: official persists/inherits allowed-model delegation policy | Retain fixed-role policy, dedicated roots and creation recovery on official subagent primitives | Official equivalent must preserve session-local role seeding without altering global chat defaults, restrictions and cold recovery |
| Copilot/native/independent search routing | Partial: native exact search-provider dispatch exists | Retain explicit routing, independent account model, proof/cancellation and backend/charge disclosure; reuse official search implementation | Retire when official supplies equivalent chat association, explicit disabled/default/final-fallback semantics and account proof; similar provider IDs are insufficient |
| Ordinary root-owned live reminder followups | Complete for the narrow common subset | Prefer official scheduler for new reminders that satisfy its limits | Preserve owner, due instant, pending/consumed state and no dual dispatch; no bulk JSON-to-Session-log rewriting |
| Interval scheduling | Partial: official >=300s creation-anchored fixed-rate/latest-only; cron >=10s last-delivery anchored | Retain non-equivalent cron interval behavior | Migrate only after explicit phase/rate/missed-run/batching semantics are accepted or official equivalence is available |
| Calendar/IANA cron and unattended cold owner wake | Absent from inspected official scheduler contract | Retain calendar recurrence and cold-session resume | Retire after equivalent timezone/DST and durable cold-owner resume without fallback-owner substitution are verified |
| Task editing, pause/run-now, history/transfer and notifications | Partial/absent in official scheduler | Retain required management features; official active catalog is not execution history | Preserve IDs, owner/preset/model and receipts. Do not claim Windows OS notifications: current cron native notification code covers macOS/Linux only |
| Playwright Session/browser isolation and lifecycle | Complete source support; Windows runtime acceptance unverified | Prefer official Browser Use foundation, not new custom session-isolation machinery | Qualify simultaneous Sessions, tabs/cookies/refs, one-owner disposal, attached-browser survival, namespace/allowlist migration and first native/PTC catalogs |
| Edge/headed/caps/viewport expectations | Partial: explicit executablePath/headless exists; legacy caps and viewport controls absent | Retain the thin existing entry temporarily until required testing/devtools/vision and viewport behavior is accepted | Compare actual tool catalog and screenshot/console/network behavior; do not silently remove capabilities just to shrink the fork |
| Browser automatic reconnect | Intentionally absent officially | Prefer failure-transparent official lifecycle over copying reconnect flags | Migrate only with clear state-loss reporting and user-visible recovery; never reuse stale snapshot references |

## Exact official evidence

All links below point to the same immutable target commit, not mutable master:

- [Plugin Manager](https://github.com/deepseek-ai/deepseek-harness/blob/ddefc45fbc7f8e46dd73185e68295696d1297887/packages/boot/plugin-manager/README.md): profile-wide installation/removal and HMR limits; package replacement still needs a new code generation/restart.
- [Desktop Host](https://github.com/deepseek-ai/deepseek-harness/blob/ddefc45fbc7f8e46dd73185e68295696d1297887/apps/desktop-host/src/index.ts), [Host process](https://github.com/deepseek-ai/deepseek-harness/blob/ddefc45fbc7f8e46dd73185e68295696d1297887/apps/desktop/src/host-process.ts), [profile migration](https://github.com/deepseek-ai/deepseek-harness/blob/ddefc45fbc7f8e46dd73185e68295696d1297887/apps/desktop/src/profile-packages.ts): official Web-backed `runProfile` topology and legacy-link migration.
- [Native model discovery](https://github.com/deepseek-ai/deepseek-harness/blob/ddefc45fbc7f8e46dd73185e68295696d1297887/packages/llm/llm-pi-ai/src/discovery.ts): installed-provider catalog discovery is not current-account entitlement refresh.
- [Subagent descriptor](https://github.com/deepseek-ai/deepseek-harness/blob/ddefc45fbc7f8e46dd73185e68295696d1297887/packages/subagent/subagent/src/descriptor.ts) and [model-selection state](https://github.com/deepseek-ai/deepseek-harness/blob/ddefc45fbc7f8e46dd73185e68295696d1297887/packages/subagent/tool-subagent/src/model-selection-state.ts).
- [Remote codec types](https://github.com/deepseek-ai/deepseek-harness/blob/ddefc45fbc7f8e46dd73185e68295696d1297887/packages/typert/protocol/src/types.ts) and [registry validation](https://github.com/deepseek-ai/deepseek-harness/blob/ddefc45fbc7f8e46dd73185e68295696d1297887/packages/typert/registry/src/service.ts).
- [Scheduler runtime](https://github.com/deepseek-ai/deepseek-harness/blob/ddefc45fbc7f8e46dd73185e68295696d1297887/packages/schedule/schedule/src/runtime.ts), [types](https://github.com/deepseek-ai/deepseek-harness/blob/ddefc45fbc7f8e46dd73185e68295696d1297887/packages/schedule/schedule/src/types.ts), [semantics](https://github.com/deepseek-ai/deepseek-harness/blob/ddefc45fbc7f8e46dd73185e68295696d1297887/docs/subsystems/schedule.md).
- [Official Playwright provider](https://github.com/deepseek-ai/deepseek-harness/blob/ddefc45fbc7f8e46dd73185e68295696d1297887/packages/experimental/browser-use-playwright-mcp/src/index.ts), [browser runtime](https://github.com/deepseek-ai/deepseek-harness/blob/ddefc45fbc7f8e46dd73185e68295696d1297887/packages/experimental/browser-use-runtime/src/index.ts), [MCP lifecycle](https://github.com/deepseek-ai/deepseek-harness/blob/ddefc45fbc7f8e46dd73185e68295696d1297887/packages/experimental/browser-use-runtime/src/mcp.ts).

## Qualification work still required

1. Copilot handwritten strict Remote codecs require `create()` on alpha.2; merely widening peer ranges leaves Client `$mount` broken. Preserve explicit owned view validation because Gateway success is not result-schema validation.
2. Copilot role child descriptor parsing expects version 1 while official emits version 3. This predates alpha.2 (also present in alpha.1): label it as a pre-existing mismatch, rebuild the plugin projection cache safely, and do not invent migration of old durable children.
3. Cron's module-global active Session from header mount/unmount is unsafe with coexisting main/embedded Session views. Bind actions to the correct instance/owner and qualify simultaneous views. `openSession(SessionTarget)` still accepts SessionId; update exact contract tests rather than claim the API disappeared.
4. Browser migration needs actual Windows/Edge tool capability acceptance, not only `--version` or synthetic RPC tests. Never mount legacy global MCP and official Browser Use simultaneously as a silent transition.
5. Neither scheduler has established exactly-once crash delivery. Official documents at-least-once behavior; cron queue-before-persist also has a crash window. Clean-restart tests are not crash-safety evidence.
6. Core merge preview reports substantial Desktop/Host conflicts and upstream deletion of the old plugin-manager renderer/preload. Resolve against the official architecture and retained requirements, not blanket ours/theirs.

Each component's implementation Issue/PR must attach actual checks, release/artifact
identities and migration limits before Ops promotes a new lock. Source review is
useful progress, not permission to report alpha.2 deployment complete.
