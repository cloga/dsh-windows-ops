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

## Recommendation policy

Until a candidate reaches at least `L4` in an isolated test environment:

- describe it as a candidate, not a working recommendation;
- do not install it into the maintained `web` Profile;
- do not reuse personal browser data;
- do not enable unrestricted desktop writes;
- do not add it to the deployment lock.

For ordinary web interaction, prefer isolated browser automation over full-desktop control. Use existing-browser or desktop control only when the task genuinely requires authenticated or native UI state.
