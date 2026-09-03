# Repository agent rules

## GitHub identity and published refs

- Use the `cloga` GitHub identity for every issue, push, pull request, review,
  and merge in this repository.
- Load the credential into the current process only from a user-designated
  trusted `.env`. Prefer one centralized file explicitly designated by the
  user; a repository-local `.env` is allowed only when it is explicitly chosen
  and Git confirms it is ignored. Never print, copy between repositories,
  include in documentation, or commit the credential.
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
  exact source and merge commits, versioned tarball URL and SHA-256, release tag,
  immutable-release assertion, and `SHA256SUMS` identity; never substitute a
  registry package or an unverified latest URL.
- Keep the official DSH Desktop shell unless the task specifically changes the
  shell.
- For `cloga/deepseek-harness` changes, build a local `@deepseek-ai/dsh`
  tarball and make Desktop run that local CLI. Do not redirect Desktop's
  bundled-core release URL as a substitute for local-core testing.
- Prefer an explicit `DSH_CLI_PATH` when more than one `dsh` executable exists.
  Otherwise, verify that Desktop selected the global local CLI.
- Do not use Desktop's local-core update action while testing the fork; it
  installs `@deepseek-ai/dsh@latest` and can replace the fork build.
- Treat plugins and the core as separate compatibility layers. Preserve and
  attest Desktop's seven official Profile links plus its non-bundled panel
  placeholder; never replace them with guessed registry packages. The locked
  installer physically materializes only the reviewed `dsh-github-copilot`
  integration. Classify `dsh-playwright-host` and `dsh-cron` as optional Web
  overlays rather than silently making them baseline requirements. Run the
  check-first installer, repository replay self-check, and exact-marker dry run
  before applying unrelated patches.

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
