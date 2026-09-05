# Optional scheduling with dsh-cron

## Scope and status

`dsh-cron` is an **optional Web-profile overlay** for scheduled prompts. The authoritative Windows Copilot lock records its reviewed identity only under `profile.optionalOverlays` with `required: false`; it is excluded from `requiredBundles`, installation success criteria, and the required Desktop/Core/Copilot component set. Install it only when persistent Session automation is wanted, and never promote it implicitly into the required baseline.

The reviewed overlay is:

| Field | Reviewed value |
|---|---|
| Package | `dsh-cron` |
| Version | `0.4.1` |
| Source | `github:cloga/dsh-cron#v0.4.1` |
| Resolved commit | `5f99313e110932195821d924259b2836947271f3` |
| Release artifact | `dsh-cron-0.4.1.tgz`, SHA-256 `9be9e7c6ea1b4bf8a6f354dd1533e8a920f4d397c09fb20e14a2b5c91a50ce5f`, 34,276 bytes |
| Checksum manifest | `SHA256SUMS`, SHA-256 `ad66a15d46072952f250001e875331b2dbc7bf2b5db615481d72a3e1e7925bbf`, 85 bytes |
| Profile | `web` only |

The tag-to-commit resolution above was verified from the local Git checkout with `git rev-parse 'v0.4.1^{commit}'`. The Release is immutable. Keep the tag or exact Release artifact pin; do not install an unpinned branch for an operational baseline.

## Compatibility

The bounded peer contract is `>=0.1.1-rc.2 <0.1.2-0 || >=0.1.2-alpha.4 <0.1.2`. The current Windows certification target is the official Desktop-managed DSH `0.1.2-rc.1` at `a66e4702047846cdaa10c66c9d3df3951f5ea70d`. Stable `0.1.2` is intentionally excluded until separately reviewed.

The package consumes Agent, Agent Preset, default-model, LLM, live Session, Session persistence, and Tools APIs. Optional HTTP mounting consumes WebServer and Web services. Node.js must satisfy `^22.19.0 || >=24.0.0`.

The HTTP `sessionId` is supplied by the local Client. Loopback or `trustedHosts` plus same-origin checks provide operational Session separation, not authentication against a malicious local process; do not expose this API as a security boundary.

When a task fires, its stored prompt is sent to the Session's configured external LLM. Treat task prompts as outbound model input: do not place credentials or secrets in schedules, and review the selected provider before enabling persistent automation.

Use the `web` Profile. A one-shot `headless` process exits after its current work and cannot own a persistent scheduler; the certified rc.1 headless composition also does not provide every service required for cold Session recovery.

Windows Ops currently records v0.4.1 at **L2 (source/import compatible)**. Unit, package, exact-source, ownership, and restart tests pass, but a disposable rc.1 Web composition mount and harmless scheduled-turn smoke have not yet been recorded; do not claim L3/L4 until that evidence exists.

## Installation as an overlay

Install through the exact CLI selected by the Desktop deployment:

```powershell
dsh plugin --profile web add 'github:cloga/dsh-cron#v0.4.1'
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

It never falls back to another active Session. If the bound Session cannot be inspected or resumed, the task remains overdue and is retried on a later scheduler tick. One in-flight resume is allowed per Session, and one in-flight execution per task prevents duplicate overlap.

Deleting or moving Session persistence can therefore strand bound tasks. Review scheduled tasks before archiving or removing Sessions.

## Time zone example

The reviewed overlay defaults to the IANA zone `Asia/Shanghai`. An explicit zone is preferable for portable intent:

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

On Windows, `systemNotify` and `systemNotifySound` are **quiet no-ops**. Version 0.4.1 implements Host-native notifications only for:

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
