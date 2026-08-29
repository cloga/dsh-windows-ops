# GitHub Copilot CLI as a DSH ACP subagent

This practice adds GitHub Copilot CLI as an optional, out-of-process coding
agent while preserving DSH's native `spawn` and `fork` delegation paths.

## Architecture and routing

```text
DSH host
  -> subagents registry
     -> spawn provider              (ordinary independent DSH child)
     -> fork provider               (DSH child seeded with parent history)
     -> copilot provider
        -> @deepseek-ai/dsh-subagent-acp
           -> copilot --acp

Host tool registry
  -> subagent_copilot               (copilot ACP, visible to every preset scope)

Agent presets
  -> subagent                       (spawn, when the preset grants it)
  -> subagent_fork                  (fork, when the preset grants it)
```

Provider selection is deterministic. Each `dsh-tool-subagent` row names one
provider; DSH does not randomly load-balance a generic subagent call. The model
may select a tool automatically from its description, while the user can always
name Copilot explicitly.

Use this default policy:

- `subagent_fork`: the child needs completed parent conversation context.
- `subagent`: routine, self-contained research or analysis.
- `subagent_copilot`: an independent coding implementation, GitHub-specific
  workflow task, or heterogeneous code review.
- Parallel DSH and Copilot reviews: important design, security, or regression
  decisions where the extra latency and Copilot allowance are justified.

Copilot ACP receives the task and workspace cwd, but not the parent conversation.
The parent receives final assistant text rather than the full Copilot trace.

## Prerequisites

- A reviewed DSH build containing `@deepseek-ai/dsh-subagent-acp` and
  `@deepseek-ai/dsh-tool-subagent`.
- GitHub Copilot CLI with ACP support:

  ```powershell
  copilot --version
  copilot --help | Select-String -- '--acp'
  ```

- An authenticated Copilot CLI account:

  ```powershell
  copilot login --device-code
  ```

Authentication belongs to Copilot CLI's credential store. Do not put GitHub
credentials in `settings.yaml`, a Cordis patch, a preset, logs, or this
repository.

## Host-plane provider

Install the ACP package into the profile as a dependency when the selected DSH
release does not already make it resolvable:

```powershell
dsh plugin --profile web add @deepseek-ai/dsh-subagent-acp
```

The package has no bundle layer in the validated release, so add both its
provider row and the model-facing tool row to the profile's user patch. Resolve
the executable first and use that exact path in the local patch; do not commit a
machine-specific path:

```powershell
$copilot = (Get-Command copilot).Source
```

```yaml
- insert:
    - id: subagent-copilot-acp
      name: '@deepseek-ai/dsh-subagent-acp'
      config:
        providerName: copilot
        command: '<absolute path returned by Get-Command copilot>'
        args: ['--acp']
        permission: reject

    - id: tool-subagent-copilot
      name: '@deepseek-ai/dsh-tool-subagent'
      config:
        provider: copilot
        toolName: subagent_copilot
        backgroundMode: one-shot
        maxDepth: provider-managed
```

The provider belongs on the host plane because `subagents` is a process-wide,
cross-session registry and a provider name can be registered only once. The tool
row is deliberately host-plane too: `ctx.tools.register()` contributes to the
root tool scope, and every preset scope inherits it. This is the correct layout
when the deployment policy explicitly grants Copilot delegation to every preset.
Do not copy or edit shipped presets for this global capability.

Keep `permission: reject` as the baseline. ACP permission prompts are not shown
to a human: `reject` declines them, while `allow` automatically chooses the first
allow option. For a trusted implementation profile, prefer explicit Copilot CLI
`--allow-tool` and `--deny-tool` arguments over unrestricted `--allow-all`, and
record the policy separately.

Keep the existing preset-owned `subagent` and `subagent_fork` rows. A dedicated
`subagent_copilot` name is the auditable routing boundary and avoids silently
changing existing delegation. After changing the host patch, restart the Host;
new and existing preset types then inherit the global tool on their next session.

## Validation

1. Run the repository deployment checker before any repair or installation:

   ```powershell
   .\tools\install-windows-copilot.ps1
   ```

   Treat unrelated baseline drift as a separate remediation; do not translate
   the prose guide into ad hoc locked-component upgrades.

2. Confirm the profile composes the provider:

   ```powershell
   dsh --profile web --dump-config |
     Select-String 'subagent-copilot-acp|providerName: copilot|permission: reject'
   ```

3. Start a disposable validation web process on a free port and verify the
   client runtime route responds with HTTP 200. Do not start a replacement
   server for the Desktop GUI; the existing Desktop process still owns port
   3080.

4. Run the repository ACP initialize and prompt smoke:

   ```powershell
   node .\tools\smoke-copilot-acp.mjs
   ```

   Set `COPILOT_CLI_PATH` when `copilot` is not on PATH. The validated
   installation returned:

   ```text
   ACP agent: Copilot 1.0.82-1
   COPILOT_ACP_OK
   stopReason=end_turn
   ```

5. After restarting the Host, start sessions with more than one available preset
   and confirm `subagent_copilot` is present in each tool catalog. In a full
   coding preset, also confirm native `subagent` and `subagent_fork` remain
   present. Run a read-only task through `subagent_copilot`.

## Operational limits

- Each delegation starts a fresh Copilot process; there is no process pool.
- ACP is a fresh-context backend and cannot enforce parent persona, tool filters,
  structured output, or a local depth limit.
- Copilot usage is governed by the authenticated account and may consume premium
  requests.
- The profile patch needs a host restart before the provider and global tool
  exist. Existing conversations should be reopened as new sessions so their tool
  catalog includes the new root-scope tool.
- If Copilot is unavailable, existing DSH spawn/fork delegation remains the
  fallback because it is configured as separate tools.

## Rollback

1. Stop the DSH host.
2. Remove both `subagent-copilot-acp` and `tool-subagent-copilot` from the
   profile patch.
3. Remove the ACP dependency from the profile only if no other row consumes it.
4. Restart Desktop and verify native `subagent` and `subagent_fork` still work.

Never delete Copilot CLI credentials as part of a DSH rollback unless the user
explicitly requests account sign-out.
