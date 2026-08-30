# Community plugin validation

This repository separates four questions that are often collapsed into “does the plugin work?”:

1. **Discovery:** does the project exist and target DSH?
2. **Compatibility:** can its host entry resolve and load in this Profile?
3. **Activation:** does its Cordis composition fully mount and register the expected capabilities?
4. **Function and support:** does a representative operation work safely, and is the exact version supported by a maintained deployment?

The machine-readable status is maintained in `catalog/plugins.json`.

## Required workflow

### 1. Pre-install source review (`L1`)

Inspect an unpacked, immutable source or package artifact before execution:

- package name, version, repository, commit or artifact hash;
- `package.json` lifecycle scripts;
- `cordis.patch.yml` and any host/client entry points;
- child processes, downloaded binaries, network endpoints, file writes, environment-variable reads, and credential access;
- native dependencies such as `koffi`, `sharp`, `canvas`, `node-pty`, or `.node` files;
- whether the plugin publishes a Service and therefore belongs in the Host composition or an isolated preset realm;
- whether stop/update disposes processes, listeners, UI slots, timers, and browser contexts.

Do not treat an upstream README as evidence that the local artifact was reviewed.

### 2. Import compatibility (`L2`)

Install into a disposable Profile, not the maintained `web` Profile, then run:

```powershell
node tools\dsh-compat-check.mjs <profile> --probe=<package>
```

This checks dependency resolution and executes the host entry's top-level import. A pass means **import-compatible**, not functionally usable or secure.

### 3. Isolated composition mount (`L3`)

Use a disposable `DSH_HOME` and verify:

- DSH starts within the expected timeout;
- no composition row remains waiting for a missing Service;
- no process-global Service collision occurs;
- expected model tools, Host services, Client slots, or MCP tools are registered;
- shutdown removes child processes and temporary resources.

Save the command, DSH/Core version, Node version, plugin identity, and relevant log excerpt as evidence.

### 4. Functional smoke (`L4`)

Exercise a harmless representative operation against a controlled target. The test must assert an outcome, not merely observe that the tool returned without throwing.

Examples:

- search: query a deterministic fixture or test endpoint and assert the result shape;
- browser automation: open a local fixture, click a harmless button, type known text, and assert the DOM result;
- desktop automation: operate a disposable test window and verify its label or text state;
- subagent: run a bounded task and assert the provider identity and final result contract.

### 5. Deployment validation (`L5`)

Record:

- exact source commit or packaged artifact hash;
- supported DSH/Desktop/Node versions;
- installation and composition steps;
- acceptance commands and expected results;
- security boundaries and known limitations;
- rollback and uninstall steps.

Only components intentionally supported by the maintained deployment should be promoted to `baseline` and added to a lock under `deployments/`.

## Recommendation is separate

A plugin's `recommendation` is independent of its validation level. For example, a real-browser controller might reach `L4` but remain `conditional` because it inherits cookies and exposes authenticated pages to model prompts.

## Failure terminology

Use precise terms in reports:

- **load-fatal:** host entry cannot resolve or import;
- **import warning:** optional/dynamic/native dependency requires further testing;
- **activation failure:** Cordis composition does not fully activate;
- **functional failure:** registered capability fails its representative operation;
- **security rejection:** behavior works but violates the intended trust boundary.

Never summarize `L2` as “verified working.”
