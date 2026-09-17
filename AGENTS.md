# Repository agent rules

## GitHub identity and published refs

- Use the `cloga` GitHub identity for every issue, push, pull request, review,
  and merge in this repository.
- Use the existing authenticated GitHub CLI session by default. No `.env`
  file is required; its absence must not block GitHub operations.
  If additional credentials are needed, use a user-designated trusted source.
  Never print, copy between repositories, document, or commit credential values.
- Before any GitHub write, run `gh api user --jq .login` and require the exact
  result `cloga`. Stop if the identity differs.
- Every published branch must be named `cloga-<task-slug>`. Never publish an
  automatically generated workspace branch or a ref containing a personal,
  employer, device, credential, or local-path identifier.
- Create or identify a tracking issue before editing. Deliver every change
  through a pull request to the resolved default branch; never push directly to
  `master` or `main`.
- Commits produced with the Copilot App must include the exact trailer
  `Co-authored-by: Copilot App <223556219+Copilot@users.noreply.github.com>`.

## Mandatory DSH PowerShell payload preflight

Before an installation agent emits every `pwsh` tool call:

1. Read the current runtime sandbox mode and approval status.
2. For an initial call, omit `sandbox_permissions` and `justification` entirely.
3. If approval prompts are disabled, the payload MUST NOT contain either key.
4. If the current sandbox mode is `danger-full-access`, the payload MUST NOT
   contain either key.
5. Add both keys only when retrying the exact same command once after a real
   sandbox denial, approval is available, and the target mode is strictly wider
   than the current mode.
6. Omit the keys themselves; never send them as `null`, empty strings, or the
   current sandbox mode.

## Official-first Core upgrade entrypoint

- Treat requests such as "做 DSH Core 新版本适配" / "adapt to a new DSH Core release"
  as the workflow in [docs/core-upgrade.md](docs/core-upgrade.md), with component
  scope in [deployments/core-upgrade-scope.json](deployments/core-upgrade-scope.json).
  Do not depend on an optional Skill being installed to discover this entrypoint.
- Start with `node tools/plan-core-upgrade.mjs --tag dsh-v<version> --commit <full-SHA>`.
  This emits a read-only, unexecuted plan; it neither verifies the supplied target
  nor authorizes installation, activation, restart or a deployment-lock change.
- Before carrying any fork/plugin customization forward, inspect exact official
  release notes and relevant source/contracts. Record purpose, official evidence,
  complete/partial/absent/unverified parity, migrate/retain-temporarily/retire
  decision, remaining gap, retirement condition, migration/rollback and acceptance.
- Prefer verified official replacements. Retain only required differences; remove
  redundant implementations safely while preserving user-requirement acceptance
  tests. Similar names alone prove neither equivalence nor absence.
- Coordinate open PRs, Sessions and releases first. Qualify and publish changes
  through each repository's established workflow, independently verify artifacts,
  then synchronize qualified Ops locks/catalog/fixtures and bilingual docs.
  Do not create gratuitous binary releases for documentation-only planning changes.
- Core fork work stays in its owning repository and only within user-authorized
  scope; this workflow does not permit bypassing the locked Desktop runtime,
  patching live Core/dependencies, rewriting immutable releases or interrupting Sessions.

## DSH Desktop integration baseline

- Treat `deployments/windows-copilot.lock.json` as the authoritative Windows
  Desktop + Copilot deployment contract. Run
  `tools/install-windows-copilot.ps1` in its default check mode before any
  install or repair; use its explicit `-Apply` mode instead of translating the
  prose guide into ad hoc commands.
- Do not omit, substitute, or independently upgrade a locked component. Update
  the lock, plugin catalog, fixtures, tests, and bilingual/current explanatory
  guides together after a new baseline is verified. Run
  `node tools/validate-repository-content.mjs` and
  `node tools/validate-plugin-catalog.mjs` before Pester.
- The Copilot package is distributed only by immutable GitHub Release. Pin its
  exact source and merge commits, versioned tarball URL, size, SHA-256,
  SHA-512/SRI, release tag, immutable-release assertion, and `SHA256SUMS`
  identity; never substitute a registry package or an unverified latest URL.
- Route every official local Desktop build/install/update through the single
  `desktopProvisioning` contract and adapter. `windowsOpsVerifiedRelease` and
  `desktopNativeVerifiedRelease` are mutually exclusive; native mode requires
  committed capability evidence and the removal runbook. Never run ordinary
  `pnpm add` against the live reserved profile or copy `node_modules`.
- Keep the official or fork-owned DSH Desktop shell named by the deployment
  lock; do not switch shells unless the task specifically changes the shell.
- The supported runtime is only Desktop's managed, lock-attested bundled
  `@deepseek-ai/dsh`. Do not build, install, select, or document a private Core
  fork as part of the Windows baseline, and do not persist `DSH_CLI_PATH`.
- Treat plugins and the core as separate compatibility layers. In
  `desktopNativeVerifiedRelease` mode, preserve native delegation and do not
  materialize the reserved Desktop profile from Windows Ops; in legacy
  `windowsOpsVerifiedRelease` mode, preserve and attest Desktop's official
  Profile links plus its non-bundled panel placeholder. Classify
  `dsh-playwright-host` and `dsh-cron` as optional Web
  overlays rather than silently making them baseline requirements. Run the
  check-first installer, repository replay self-check, and exact-marker dry run
  before applying unrelated patches.

## Documentation synchronization

- Important pull requests must update the relevant operational guide and both
  `README.md` and `README.en.md` entry points in the same pull request when they
  change supported behavior, install/update/recovery commands, deployment
  contracts or locks, security boundaries, plugin/Core/Desktop compatibility,
  user-visible workflows, or authoritative defaults.
- In the pull request's **Expected vs Actual** section, list the documentation
  impact and the files synchronized. If no documentation or README change is
  required, state why the change is generated-only, internal, or otherwise has
  no user-facing or operational effect. Do not create artificial documentation
  churn for generated-only changes or internal refactors.

## Temporary tooling and cloud synchronization

- Before downloading or extracting tools, identify whether the destination is cloud-synchronized. Do not default to the current repository or a OneDrive workspace. Use an IT-approved non-synchronized tool directory, for example `C:\tmp\dsh-tools\<tool>-<version>`; temporary locations can be cleaned automatically.
- Keep new portable binaries, tool archives, certificate bundles, browser profiles and download caches out of synchronized workspaces by default. Hidden directory names and `.gitignore` do not prevent OneDrive synchronization.
- A PEM file may contain public CA certificates rather than a private key. Inspect only necessary markers and verify provenance/checksums without displaying secrets; corporate alerts require security-team classification, not an assumption of harmlessness.
- Non-synchronized storage is not an exemption from endpoint monitoring or DLP. Never disable TLS verification or monitoring, disguise files, or delete trust bundles blindly to suppress an alert.
- Relocate existing tools only after approval and coordination with active consumers: verify the copy, update invocation paths, test with TLS verification enabled, then remove only the approved old copy/archive. Do not implicitly move repositories or change global PATH. See [security notes](docs/security-notes.md).

## Restart and browser verification safety

- Before stopping, killing, replacing, or restarting Desktop or its Host,
  query the live `session/list` API and list every running Session. Never
  restart while any Session is running unless the user directly acknowledges
  those interruptions; pass `-AcknowledgeLiveSessionIds <exact listed IDs>` only after that approval; stale, missing, or extra IDs must block.
- A dry run must never stop a process. An unavailable or malformed live-session
  response fails closed while Desktop is running.
- Verify Web changes against the existing `http://127.0.0.1:3080`. Prefer the
  isolated Host Playwright bundle; use the pinned Python/Edge smoke fallback
  when Host MCP is unavailable. Never start a replacement server merely to
  validate the Desktop GUI.

See [Local DSH core, Desktop, and GitHub Copilot practice](docs/local-core-desktop-copilot.md).
