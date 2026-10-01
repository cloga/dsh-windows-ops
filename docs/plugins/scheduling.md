# Scheduling decision: official Schedule first

## Official-first decision (source review, 2026-09-29)

**Decision:** Pause further feature development of `cloga/dsh-cron`. For future
Windows Ops scheduled/automation tasks, prefer the official Schedule automation
tasks where the exact runtime has been independently qualified and the task fits
its contract. The official implementation replaces **most ordinary schedules**,
not every `dsh-cron` workflow. Keep the plugin as a temporary rollback reference
only for a migration blocker or serious regression, not as the default solution.
Reassess an exceptional gap against a pinned upstream release before resuming
plugin development; this decision does not remove existing task data or silently
change an installed profile.

**版本口径：**可公开核实的是 DeepSeek Harness
[`dsh-v0.2.0-rc.1`](https://github.com/deepseek-ai/deepseek-harness/releases/tag/dsh-v0.2.0-rc.1)
的**可选 experimental Schedule bundle**，不是稳定版 DSH Desktop 0.2.0，
也不是本仓库当前 Windows 部署锁已验证或已安装的能力。Windows Ops 对今后的常规定时任务
选择官方优先，`dsh-cron` 暂停功能演进；仅在迁移受阻或严重回归时临时参考回退。

The comparison is pinned to official Harness
[`4878cdabd87d4041bdaff61d04c966883b9fd07a`](https://github.com/deepseek-ai/deepseek-harness/commit/4878cdabd87d4041bdaff61d04c966883b9fd07a)
and plugin [`v0.7.3`](https://github.com/cloga/dsh-cron/releases/tag/v0.7.3),
source [`850f80842fc9ae80f8f00e7b96de25fed1af9005`](https://github.com/cloga/dsh-cron/commit/850f80842fc9ae80f8f00e7b96de25fed1af9005).
See the official [Schedule package README](https://github.com/deepseek-ai/deepseek-harness/blob/4878cdabd87d4041bdaff61d04c966883b9fd07a/packages/schedule/schedule/README.md),
[user guide](https://github.com/deepseek-ai/deepseek-harness/blob/4878cdabd87d4041bdaff61d04c966883b9fd07a/docs/user/guide/schedule.md),
plugin [README](https://github.com/cloga/dsh-cron/blob/850f80842fc9ae80f8f00e7b96de25fed1af9005/README.md)
and [package peer dependencies](https://github.com/cloga/dsh-cron/blob/850f80842fc9ae80f8f00e7b96de25fed1af9005/package.json).
The plugin's bounded peers end at Core `0.1.6-alpha.2`; they do **not**
certify compatibility with Core `0.2.0-rc.1`.

| Capability | Official Schedule at `dsh-v0.2.0-rc.1` | `dsh-cron@0.7.3` / migration implication |
|---|---|---|
| Ordinary timing | One-shot `at` (also relative `after`), intervals **at least 60 seconds**, daily, weekly, five-field cron with explicit IANA zones for wall-clock recurrence | Supports one-shot, daily and five-field cron, plus **10-59 second** intervals; translate and verify each rule, not just its label |
| Ownership and durability | Host-wide task catalog/management, original-Session cold restoration and persistence across Host restarts; due prompts are queued into the original conversation | Session-bound tasks with cold wake and separate task/history files; neither engine wakes a stopped machine |
| Controls and outcomes | Edit active task name/instruction/timing and delete; delivery records prove **inbox persistence**, not model completion | Pause/resume, run now, model-run final status/summary and human owner transfer have no equivalent official operation; inspect the Session and business outcome separately |
| Failure recovery | Pending delivery remains stored after restoration/enqueue failure, but **no automatic retry timer** or backoff; a later wake, management change or restart may retry; exactly-once is not guaranteed | Cold-owner recovery has a bounded 30/60/120/240/300-second tick-based backoff; this is not a guarantee of retrying failed business/model work |

### Migration and rollback boundary

1. Inventory tasks, owners, rule/zone, enabled state and required run-result
   behavior. Back up `$DSH_HOME/cron-tasks.json` and
   `$DSH_HOME/cron-history.jsonl` together before editing or removing anything;
   protect prompts and Session IDs. Official Schedule's storage-domain
   `schedule.json` format is incompatible with these plugin files: **there is
   no automatic migration** and no safe JSON copy/rename conversion.
2. Qualify the exact official runtime/bundle through the normal deployment
   workflow first. Stop the old task before creating its official replacement;
   the official creation path does not offer a pause switch. Never run both
   schedulers for the same task. Do not assume this document
   authorizes installation, activation, lock promotion or a Host restart.
3. Recreate each supported task explicitly in its intended original Session,
   set an explicit IANA zone for each wall-clock rule, compare the next due
   instant (including DST behavior), and actually trigger a harmless occurrence.
   Confirm the delivery in that Session and separately verify any required
   model/business outcome; a saved delivery receipt is not a completion receipt.
   Keep the backup until every task and its owner are confirmed.
4. Do not silently approximate sub-minute intervals, pause/resume, run-now,
   execution-status dependent actions, owner transfer or automatic recovery.
   Redesign or defer such tasks with the operator; where genuinely blocked,
   use the old plugin only as a **temporary**, separately qualified fallback
   on its compatible Web runtime. Disable the official counterpart first and
   restore from the protected backup only with an explicit data/owner review.
   Avoid dual dispatch in either rollback direction.

## Scope and status (historical optional dsh-cron overlay)

The following instructions document the **historical locked v0.7.1 Web-profile
overlay**, not an instruction to prefer or install it for new tasks. The
authoritative Windows Copilot lock records its reviewed identity only under
`profile.optionalOverlays` with `required: false`; it is excluded from
`requiredBundles`, installation success criteria, and the required
Desktop/Core/Copilot component set. Never promote it implicitly into the
required baseline.

The reviewed overlay is:

| Field | Reviewed value |
|---|---|
| Package | `dsh-cron` |
| Version | `0.7.1` |
| Source | `github:cloga/dsh-cron#v0.7.1` |
| Resolved commit | `6dae9da71e6c36c58e04f3ca8c10cc5c4790b3bd` |
| Reviewed head / PR | `7628e5bb9d8b24981962548974cafd3dfa9e509c` / [#45](https://github.com/cloga/dsh-cron/pull/45) |
| Immutable Release / artifact asset | `389294372` / `566045997` |
| Release artifact | `dsh-cron-0.7.1.tgz`, SHA-256 `136ba9d66ba2f2ada87f1ce97dfb21be97474dc76504fc65ae8e01cde60768d0`, 64,919 bytes |
| SHA-512/SRI | `sha512-9brysYXc0aurJ0PI8Gq66q7acV6os66KOM8/WGR0JWEr8e92mYTZ++kqY3GZY+eFwXiKpcjN4by//Ak11ewKxA==` |
| Checksum manifest | `SHA256SUMS`, asset `566046029`, SHA-256 `f05eef489a31f38ee203b91808d54e2100ae18b222907fbe4125c680bac802f2`, 85 bytes |
| Profile | `web` only |

On 2026-09-17, authenticated GitHub-gate queries verified the non-draft immutable [v0.7.1 Release](https://github.com/cloga/dsh-cron/releases/tag/v0.7.1) and dereferenced annotated tag object `15e5a97e58ab9f3016b974e59dea718e512cb223` to the commit above. Independently downloaded artifact/checksum bytes matched the sizes, SHA-256, SHA-512/SRI and checksum entry. Keep the tag or exact Release artifact pin; do not install an unpinned branch for an operational baseline.

## Compatibility

The published bounded DSH peer contract is `>=0.1.1-rc.2 <0.1.2-0 || >=0.1.2-alpha.4 <0.1.2 || >=0.1.3-alpha.1 <0.1.3-alpha.2 || 0.1.5-alpha.1 || 0.1.5-alpha.2 || 0.1.5-rc.2 || 0.1.6-alpha.1`. The companion-suite lock now selects only `0.1.6-alpha.1`; this is not a blanket certification of future 0.1.6 versions or arbitrary forks. Published [exact-source tests](https://github.com/cloga/dsh-cron/blob/6dae9da71e6c36c58e04f3ca8c10cc5c4790b3bd/tests/core-compat.test.mjs) target official commit `0a15e36e7f82b6ed45af6fa9759f29b40dcd965d`: modern persistence read handles, root ownership, `agent/created` lifecycle, public `session.seq` transfer freshness and optional plugin activation. They explicitly distinguish source-backed fixtures from full Host compatibility.

The package consumes Agent, Agent Preset, default-model, LLM, live Session, Session persistence, and Tools APIs. Optional HTTP mounting consumes WebServer and Web services. Node.js must satisfy `^22.19.0 || >=24.0.0`.

The HTTP `sessionId` is supplied by the local Client. Loopback or `trustedHosts` plus same-origin checks provide operational Session separation, not authentication against a malicious local process; do not expose this API as a security boundary.

When a task fires, its stored prompt is sent to the Session's configured external LLM. Treat task prompts as outbound model input: do not place credentials or secrets in schedules, and review the selected provider before enabling persistent automation.

Use the `web` Profile. A one-shot `headless` process exits after its current work and cannot own a persistent scheduler. Keep the scheduler at Host lifetime, not per-Agent Preset lifetime; this task does not install it into the reserved native Desktop profile.

Windows Ops records v0.7.1 at **L1 (source reviewed)** with independently verified release bytes. Historical v0.4.1 L2 does not transfer to this pin. The repin did not perform a new Host-entry import, disposable Web mount, browser interaction or scheduled model turn; source/test review and synthetic installer fixtures do not establish L2/L3/L4 or target-fork runtime acceptance.

The published version includes the current-session native Sidebar tab with optional Better Sidebar/modal fallback, plus a capability-gated global owner index. The index exposes counts and next-run time, not task prompts or cross-owner task management. `/cron-transfer` is a direct top-level human command for validated idle tasks and blank root destinations, not a model tool or HTTP route; its freshness guarantee is single-Host only. Do not re-enable incompatible sidebar plugins to obtain these features.

## Installation as an overlay

Install through the exact CLI selected by the Desktop deployment:

```powershell
dsh plugin --profile web add 'github:cloga/dsh-cron#v0.7.1'
dsh --profile web --dump-config
```

The composed configuration should contain one `dsh-cron` row. The package ships its built Client bundle and has no install-time build script.

Treat installation as staged until an authorized Host restart. Before restarting:

1. Query `session/list` and enumerate every current running Session ID.
2. If another Session is active, leave the overlay installed but inactive.
3. Restart only after the user explicitly accepts interruption of that exact listed ID set; if the set changes, enumerate it again and obtain new approval. Missing, stale, or extra acknowledged IDs must fail closed.
4. After restart, hard-refresh the existing DSH Web page; do not start a replacement server.

## Session-bound cold wake semantics

A dynamic task created with `cron_add` is bound to the calling Session ID. At fire time the plugin:

1. reuses the exact live bound Session when present;
2. when `coldWake: true`, reads that Session from persistence and resumes it with its recorded Agent Preset and most recent request provider/model selection;
3. verifies that the resumed Agent still owns the exact requested Session ID; and
4. injects the scheduled prompt with plugin provenance and records the resulting run.

It never falls back to another active Session. If the bound Session cannot be inspected or resumed, the task remains overdue and is retried on a later scheduler tick with shared per-owner 30/60/120/240/300-second recovery backoff (then at most every 300 seconds). One in-flight resume is allowed per Session, and one in-flight execution per task prevents duplicate overlap. Persisted nonterminal runs are closed as interrupted after Host restart; already consumed schedules are not replayed. Cold list/history reads validate persisted root metadata without waking an Agent, while mutations still require the loaded root.

Deleting or moving Session persistence can therefore strand bound tasks. Review scheduled tasks before archiving or removing Sessions.

## Time zone example

The published 0.7.1 default time zone is **UTC**, not the machine's local zone. Set an explicit IANA zone for portable intent:

```json
{
  "id": "monday-briefing",
  "prompt": "Summarize the current Session's open work and reply with a short briefing.",
  "cron": "0 9 * * 1",
  "timeZone": "Asia/Shanghai"
}
```

This runs each Monday at 09:00 in Shanghai time. Each task must use exactly one schedule rule: `at`, `every`, `daily`, or a standard five-field `cron` expression.

## Cron tool smoke test

After restart, use a disposable task to verify registration, Session binding, persistence, and removal:

1. Call `cron_list`; it should return the current task list without an unknown-tool error.
2. Call `cron_add` with the example above (or another harmless future schedule).
3. Call `cron_list` again and confirm the task has a non-empty bound Session ID and `nextRunAt`.
4. Call `cron_history` to confirm the history tool is available; no record is expected before the first run.
5. Call `cron_remove` with `id: "monday-briefing"` and confirm a final `cron_list` no longer contains it.

The complete model-tool surface is `cron_list`, `cron_add`, `cron_update`, `cron_remove`, and `cron_history`.

## Persistence and backup

By default, dynamic state is stored under DSH Home:

- `$DSH_HOME/cron-tasks.json` — dynamic tasks, run stamps, enablement overrides, and Session bindings;
- `$DSH_HOME/cron-history.jsonl` — bounded execution history.

Writes use a temporary file followed by rename. History is capped by the plugin, but both files remain operational state and should be included in DSH Home backups when schedules matter.

Before plugin upgrades, removal, Session migrations, or DSH Home recovery:

1. stop creating or editing tasks;
2. copy both files together with the Web Profile manifest and lockfile;
3. preserve file ACLs and do not commit task prompts or Session IDs to Git; and
4. after restore, run `cron_list` before allowing overdue tasks to fire.

Static tasks declared in composition are configuration-owned and are not removed through `cron_remove`; dynamic tasks created through tools live in `cron-tasks.json`.

## Windows notification caveat

On Windows, `systemNotify` and `systemNotifySound` are **quiet no-ops**. Version 0.7.1 implements Host-native notifications only for:

- macOS through `osascript`; and
- Linux through `notify-send`.

This does not disable the Web UI's unread badge, page toast, WebAudio sound, or browser notification behavior while the page is available. Do not treat successful scheduling on Windows as proof that an operating-system-native notification will appear.

## Rollback and removal

First inspect and remove or export dynamic tasks that should not survive rollback. Then remove the overlay:

```powershell
dsh plugin --profile web remove dsh-cron
dsh --profile web --dump-config
```

Confirm the composed configuration no longer contains `dsh-cron`. Removal is staged until the next authorized Host restart; apply the same live-Session safety check used for installation.

Removing the plugin does not automatically delete `cron-tasks.json` or `cron-history.jsonl`. Retain them for rollback, or delete them only after an explicit data-retention decision and a verified backup.
