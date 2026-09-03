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
- [ ] Desktop 0.10.2 shell links and panel placeholder remain intact unless this PR explicitly changes them.
- [ ] Optional overlays remain separate from the required baseline.
- [ ] Artifact URLs, commits, versions, and SHA-256 values are exact and evidence-backed.
- [ ] No credential, token, session content, backup payload, or machine-specific private path is included.

Fixes #
