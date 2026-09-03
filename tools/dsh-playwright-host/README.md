# dsh-playwright-host

Optional Windows Profile Bundle that mounts DSH's built-in `@deepseek-ai/dsh-mcp-client` at Host scope and launches pinned Microsoft Playwright MCP with installed Microsoft Edge. Because the tools enter the Host tool-registry layer, every Agent Preset can see names such as `mcp__playwright__browser_navigate`, `browser_snapshot`, `browser_click`, `browser_type`, `browser_take_screenshot`, `browser_console_messages`, and `browser_network_requests`.

## Install without activation

The canonical source is [`cloga/dsh-playwright-host`](https://github.com/cloga/dsh-playwright-host). Use the exact CLI selected by the Desktop deployment and install the reviewed immutable commit:

```powershell
dsh plugin --profile web add github:cloga/dsh-playwright-host#v0.1.2
```

The vendored files in this directory are a reviewed snapshot used by Windows Ops contract tests. This command stages the standalone GitHub bundle in the Web Profile. Do not restart or replace a running DSH Host while other Sessions are live. Before restart, enumerate the current running Sessions and obtain explicit user acceptance of that exact interruption list; if the set changes, ask again. A Host restart is required before the new global tools appear.

Inspect the composed configuration before activation:

```powershell
dsh --profile web --dump-config
```

The composed tree must contain one `mcp-playwright` row using `@deepseek-ai/dsh-mcp-client`, the exact `@playwright/mcp@0.0.80` pin, `--isolated`, and `--browser msedge`.

## Scope and isolation boundary

`--isolated` prevents reuse of the user's everyday Edge profile. It does **not** create a separate MCP process for every DSH Session. One Host bundle instance owns one Playwright MCP stdio process, so concurrent Sessions can affect the same browser state, tabs, snapshot references, cookies, and close operations. Use browser tools from one Session at a time. Do not use authenticated personal profiles or consequential real-account flows.

A future Session-aware Host provider should key one BrowserContext or MCP process by `exec.agent.session.id` before concurrent use can be considered isolated. Until then, Python Playwright remains the per-invocation fallback for independent verification.

## Verification

After an authorized restart, create a new Session with any Preset and confirm that `mcp__playwright__browser_navigate` and related tools are present. Navigate to the existing `http://127.0.0.1:3080`, capture an accessibility snapshot and screenshot, exercise a harmless interaction, and inspect Console and failed Network requests. Do not start a replacement DSH server.

## Remove

```powershell
dsh plugin --profile web remove dsh-playwright-host
```

Removal is staged until the next authorized Host restart. The npm/npx cache and the separately installed Python Playwright binding are not removed by this command.
