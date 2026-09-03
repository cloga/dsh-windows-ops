# Contributing

Read [AGENTS.md](AGENTS.md) before changing this repository. The deployment lock, not prose or a machine's incidental state, defines the supported Windows baseline.

## Workflow

1. Create or reuse a tracking issue.
2. Branch from the resolved default branch using `cloga-<task-slug>` for `cloga`-owned work.
3. Keep `deployments/windows-copilot.lock.json`, catalog entries, fixtures, tests, and explanatory guides synchronized for every baseline change.
4. Preserve the official Desktop shell, seven Profile links, non-bundled panel placeholder, and optional-overlay boundary unless the issue explicitly changes them.
5. Run verification in read-only/check modes first. Do not use `-Apply`, stop Desktop, or restart Host merely to validate a repository change.
6. Commit with the issue reference. Work produced with the Copilot App uses the exact trailer `Co-authored-by: Copilot App <223556219+Copilot@users.noreply.github.com>`. Open a pull request with `Fixes #<issue>`.
7. Merge only after required policy, catalog, and Windows Pester checks pass.

## Required verification

```powershell
node tools\validate-repository-content.mjs
node tools\validate-plugin-catalog.mjs
node --test tests\plugin-catalog.test.mjs tests\host-playwright-bundle.test.mjs tests\repository-content.test.mjs

powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools\install-windows-copilot.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools\dsh-replay.ps1 -Action SelfCheck
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools\dsh-replay.ps1 -Action Apply -DryRun
```

Run the complete Pester suite under Windows PowerShell 5.1. A check may truthfully report deployment drift when the machine has not yet applied a newly reviewed lock; it must not mutate the machine.

## Safety

Do not commit `.env`, tokens, credentials, generated deployment artifacts, backup payloads, session content, or machine-specific roots. Security-sensitive findings belong in [private vulnerability reporting](SECURITY.md), not a public issue.
