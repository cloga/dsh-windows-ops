# Computer Use and browser automation on Windows

Computer Use requires both a model/tool protocol and an executor that can observe and manipulate a browser or desktop. A model catalog entry containing “computer use” does not install that executor.

This document defines how this repository evaluates candidates. Current machine-readable entries and evidence live in `catalog/plugins.json`; projects found online but not cataloged remain `L0` and must not be presented as verified.

## Capability classes

### Isolated browser automation

A dedicated Chromium/Edge context does not inherit personal cookies or extensions. This is the preferred default for public-site research and deterministic testing.

Minimum acceptance:

1. create a fresh context;
2. open a local fixture URL;
3. read an accessibility or DOM snapshot;
4. click a harmless fixture control;
5. type known text and assert the resulting page state;
6. reject or constrain unexpected private-network navigation;
7. close all browser processes on stop.

### Existing-browser control

Chrome extension, CDP, or local-profile integrations can operate authenticated pages. They are useful when a task requires an existing login, but carry higher risks:

- cookies, messages, account data, and password-manager UI may be visible;
- untrusted page content can influence the agent;
- actions occur with the user's real account and network identity;
- the browser profile may remain modified after a failed run.

Such plugins should normally be `conditional`, even after functional validation. Tests must use a disposable browser profile unless the user explicitly authorizes a real one.

### Windows UI Automation

UIA-based tools can identify native controls semantically and may be more reliable than coordinates. Validation must cover:

- ordinary and elevated-window boundaries;
- UAC and secure-desktop limitations;
- DPI scaling and multiple displays;
- stale element references after window changes;
- cleanup of helper processes and hooks.

### Screenshot/coordinate desktop control

Visual desktop agents are the most general and the easiest to misdirect. They require explicit evidence for screenshot scope, OCR/vision data routing, coordinate scaling, approval gates, and user takeover.

## Security checklist

Before recommending any Computer Use plugin, answer and record:

- Does it capture the full desktop or one target window?
- Can it read clipboard contents?
- Can it type into password or payment fields?
- Does it reuse an authenticated browser profile?
- Are screenshots or page contents sent to an external model/service?
- Does it permit arbitrary URLs, local files, private IPs, or `file:` navigation?
- Which actions require approval?
- Is there a visible pause/takeover mechanism?
- Does stop reliably release input hooks and child processes?
- Are install-time or first-run binaries downloaded from a pinned source with a bounded timeout?

Unknown answers must remain `null` in the catalog and block a broad recommendation.

## Current repository status

As of 2026-08-30:

- no Computer Use executor is part of `deployments/windows-copilot.lock.json`;
- the active Web Profile does not install a Computer Use plugin;
- `desktop-touch-mcp` is retained as a **historical `L1`** integration because this repository documented its launcher startup failure and an upstream reliability fix;
- that history does not prove current DSH activation or desktop-control functionality.

See `docs/startup-60s-timeout.md` for the launcher incident and `docs/plugins/plugin-validation.md` for promotion requirements.

## Maintained browser-verification practice

For local DSH Web development and repair, use Microsoft's upstream
[`@playwright/mcp`](https://github.com/microsoft/playwright-mcp) through DSH's
shipped `@deepseek-ai/dsh-mcp-client`. This is the preferred baseline for
self-verifying Web changes: it minimizes DSH-specific compatibility surface
while retaining accessibility snapshots, deterministic interactions,
screenshots, Console inspection, and network inspection. Community wrappers
that embed a live browser panel remain candidates until they independently
pass the repository validation ladder.

For tools that must be visible under every Agent Preset, install the reviewed
`tools/dsh-playwright-host/` Profile Bundle. It mounts the MCP client in the
Host composition without editing a shipped preset. Pin the upstream version
and upgrade it deliberately. The bundle uses installed Microsoft Edge and an
isolated, disposable browser profile:

```yaml
- id: mcp-playwright
  name: '@deepseek-ai/dsh-mcp-client'
  config:
    serverName: playwright
    transport: stdio
    command: npx
    args:
      - '-y'
      - '@playwright/mcp@0.0.80'
      - '--isolated'
      - '--browser'
      - 'msedge'
      - '--caps'
      - 'testing,devtools,vision'
      - '--viewport-size'
      - '1440x900'
    toolCallTimeoutMs: 120000
    failOnStartupError: true
```

Do not add unrestricted file access, attach the user's everyday browser
profile, or disable origin controls merely for convenience. A normal isolated
browser can navigate to loopback DSH URLs without an unrestricted filesystem
or desktop grant.

Stage the bundle with `dsh plugin --profile web add link:<absolute-bundle-path>`
and inspect `dsh --profile web --dump-config`. Do not restart while other
Sessions are live. After an explicitly authorized Host restart, create a new
Session with any Preset and confirm the `mcp__playwright__*` tools are present.
Browser launch is lazy, so successful composition is necessary but not
sufficient evidence. For a DSH Web change, verify the already-running GUI
(normally `http://127.0.0.1:3080`) rather than starting a replacement server:

1. navigate to the existing GUI and capture an accessibility snapshot;
2. exercise the changed interaction and assert the resulting page state;
3. capture a screenshot when visual behavior matters;
4. inspect Console errors and relevant failed network requests;
5. confirm teardown closes the isolated browser process.

A successful build without this browser pass is not sufficient UI validation.
Record the exact DSH and Playwright MCP versions with any failure because both
are prerelease-sensitive integration surfaces.

The current Host bundle owns one MCP stdio process. `--isolated` protects the
user's everyday Edge profile but does not isolate DSH Sessions from one another;
concurrent Sessions can change the same pages, tabs, snapshot references,
Cookies, and close state. Use it from one Session at a time until a future Host
provider keys BrowserContexts or MCP processes by Agent Session id.

### Preset-independent fallback for every coding session

If the Host bundle is staged but not activated, unavailable, or already in use
by another Session, that must not prevent self-verification. Install the reviewed Python binding pin
once at user scope; it uses the installed Edge channel and does not require a
separate Chromium download:

```powershell
python -m pip install --user playwright==1.62.0
python tools\dsh-web-smoke.py --expect-text "New Session"
```

`dsh-web-smoke.py` launches an isolated headless Edge context, opens
`DSH_WEB_URL` or `http://127.0.0.1:3080`, waits for the rendered page, asserts a
successful non-empty document and requested text, and writes both a screenshot
and a JSON report under `.dsh-windows-ops/browser-verification/`. Console
errors, failed requests, and HTTP failures are always recorded; callers can
make each category fatal with the matching `--fail-on-*` option. The tool never
starts or replaces the DSH server.

The smoke tool proves reachability and captures broad regressions; it does not
prove the feature being changed. After reconnaissance, the agent must write and
run a narrow temporary Python Playwright script that performs the changed
interaction and asserts its expected state. Prefer MCP when it is already in
the session because its accessibility snapshots are efficient for exploratory
work; use the Python path as the universal fallback from any PowerShell-capable
coding session.

## Capturing reusable local practice

When local DSH work reveals a reusable installation, compatibility, debugging,
recovery, or verification technique, proactively add an evidence-based note to
this repository instead of leaving it only in chat or machine-local notes.
Keep the note portable: omit credentials, private data, employer/device
identifiers, and unnecessary machine-specific paths. Every such update still
uses the repository's Issue, `cloga-<task-slug>` branch, verification, pull
request, merge, and sync workflow.

## Recommendation policy

Until a candidate reaches at least `L4` in an isolated test environment:

- describe it as a candidate, not a working recommendation;
- do not install it into the maintained `web` Profile;
- do not reuse personal browser data;
- do not enable unrestricted desktop writes;
- do not add it to the deployment lock.

For ordinary web interaction, prefer isolated browser automation over full-desktop control. Use existing-browser or desktop control only when the task genuinely requires authenticated or native UI state.
