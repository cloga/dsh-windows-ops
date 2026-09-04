## Summary

<!-- State the operational problem, affected lock/tool/doc surfaces, and what remains unchanged. -->

## Verification

- [ ] `node tools\validate-repository-content.mjs`
- [ ] `node tools\validate-plugin-catalog.mjs`
- [ ] Node catalog/host-bundle tests
- [ ] Complete Windows PowerShell 5.1 Pester suite
- [ ] Installer default check mode
- [ ] Replay `SelfCheck` and `Apply -DryRun`

## Safety and contract checklist

- [ ] No verification step used `-Apply`, restarted Desktop/Host, or interrupted a live Session.
- [ ] Lock, catalog, fixtures, tests, and bilingual/current guides agree.
- [ ] Desktop 0.10.3's eight official 0.6.7 Profile links (including `dsh-tauri-panel-scheduler`) and panel placeholder remain intact unless this PR explicitly changes them.
- [ ] Required `dsh-github-copilot@0.3.0-cloga.15` and optional `dsh-cron` / `dsh-playwright-host` roles remain distinct.
- [ ] Runtime verification attests the Desktop-managed wrapper/tree/entrypoint and exact active PID owning IPv4 `127.0.0.1:3080`.
- [ ] Optional overlays remain opt-in through `-IncludeCompanionSuite` and share the main transaction without becoming base requirements.
- [ ] Artifact URLs, commits, versions, and SHA-256 values are exact and evidence-backed.
- [ ] No credential, token, session content, backup payload, or machine-specific private path is included.

Fixes #
