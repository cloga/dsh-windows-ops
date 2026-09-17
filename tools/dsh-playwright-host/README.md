# dsh-playwright-host

Optional Windows Profile Bundle that mounts DSH's built-in `@deepseek-ai/dsh-mcp-client` at Host scope and launches pinned Microsoft Playwright MCP with installed Microsoft Edge. Because the tools enter the Host tool-registry layer, every Agent Preset can see names such as `mcp__playwright__browser_navigate`, `browser_snapshot`, `browser_click`, `browser_type`, `browser_take_screenshot`, `browser_console_messages`, and `browser_network_requests`.

## Verified release and compatibility boundary

The optional Web-only pin is [v0.1.7](https://github.com/cloga/dsh-playwright-host/releases/tag/v0.1.7), immutable Release **389282244**. Its annotated tag object `8fb643706d8659435c4681008a9426273de14179` resolves to commit `fdec939b48d14d66d14bef3d8f12ec68411d58fb` ([PR #19](https://github.com/cloga/dsh-playwright-host/pull/19), reviewed head `c8f514b838516eed8cced19ef2dd514ef1f2f0a4`), not the release metadata's moving `main` target.

On 2026-09-17, authenticated GitHub-gate downloads independently verified:

- `dsh-playwright-host-0.1.7.tgz`: asset **566016151**, **8,280 bytes**, SHA-256 `647c2112f09c9aa9aabfb6fbe3659dad32658a63eeb034a9040736695ca061f3`.
- SHA-512/SRI: `sha512-bJAtkjJwCCaXh3QCMhlEq4GTWkmyDlSNFkA+ErVYL4JUHSuFGt6550ypudI67wc0nhQuD3XSof7EwC8fVoQdzg==`.
- `SHA256SUMS`: asset **566016150**, **96 bytes**, SHA-256 `45a32a05036595e23d22c101126c41e9f6c77ac0fe1402a2ebc9456f55952a6b`; its tarball entry matches the downloaded bytes.

The composition is identical to the published package after line-ending normalization. This private test mirror keeps a repository commit annotation and local README/files list; it is not a separately published artifact. Its peers match the published `>=0.1.6-alpha.1 <0.1.7-0` contract for MCP client, MCP resources and system prompt. Base owns resources/system prompt; the overlay must not duplicate those rows or move the shared MCP client into an Agent Preset.

Published [source tests](https://github.com/cloga/dsh-playwright-host/blob/fdec939b48d14d66d14bef3d8f12ec68411d58fb/test.mjs) certify upstream DSH `0.1.6-alpha.1` at `0a15e36e7f82b6ed45af6fa9759f29b40dcd965d`, tree `66c4c9c2053c6fcf91ad4e47d85bd77539c0b101`, including MCP SDK v2, cancellation, negotiation/quiescence and Base resource ownership. The published README still contains historical candidate-blocked prose; the independently observed immutable release is publication evidence, not evidence of installation. Windows Ops records this repin at **L1**: source/byte verification and static mirror tests, no new import probe, Host mount, browser launch, OAuth or model round. Historical 0.1.2 L4 does not certify 0.1.7 or the target Desktop fork.

## Install without activation

The canonical source is [`cloga/dsh-playwright-host`](https://github.com/cloga/dsh-playwright-host). Use the exact CLI selected by the Desktop deployment and install the reviewed immutable commit:

```powershell
dsh plugin --profile web add github:cloga/dsh-playwright-host#v0.1.7
```

The vendored files in this directory are a reviewed snapshot used by Windows Ops contract tests. This command stages the standalone GitHub bundle in the Web Profile. Do not restart or replace a running DSH Host while other Sessions are live. Before restart, enumerate the current running Sessions and obtain explicit user acceptance of that exact interruption list; if the set changes, ask again. A Host restart is required before the new global tools appear.

Inspect the composed configuration before activation:

```powershell
dsh --profile web --dump-config
```

The composed tree must contain one `mcp-playwright` row using `@deepseek-ai/dsh-mcp-client`, the exact `@playwright/mcp@0.0.80` pin, `--isolated`, and `--browser msedge`. Preserve `toolCallTimeoutMs: 120000`, `failOnStartupError: true`, `maxInstructionBytes: 32768`, and reconnect enabled with 500 ms initial delay, 30,000 ms maximum delay and 10 attempts. The existing Base composition must supply exactly one MCP resources row and one system-prompt service.

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
