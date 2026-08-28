# Repository agent rules

## GitHub identity and published refs

- Use the `cloga` GitHub identity for every issue, push, pull request, review,
  and merge in this repository.
- Load the credential from the repository-local, ignored `.env` file into the
  current process only. Never print, copy into documentation, or commit the
  credential.
- Before any GitHub write, run `gh api user --jq .login` and require the exact
  result `cloga`. Stop if the identity differs.
- Every published branch must be named `cloga-<task-slug>`. Never publish an
  automatically generated workspace branch or a ref containing a personal,
  employer, device, credential, or local-path identifier.
- Create or identify a tracking issue before editing. Deliver every change
  through a pull request to the resolved default branch; never push directly to
  `master` or `main`.

## DSH Desktop integration baseline

- Treat `deployments/windows-copilot.lock.json` as the authoritative Windows
  Desktop + Copilot deployment contract. Run
  `tools/install-windows-copilot.ps1` in its default check mode before any
  install or repair; use its explicit `-Apply` mode instead of translating the
  prose guide into ad hoc commands.
- Do not omit, substitute, or independently upgrade a locked component. Update
  the lock, its fixture tests, and the explanatory guide together after a new
  baseline is verified.
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
  attest Desktop's five official internal-plugin links; never replace them with
  guessed registry packages. The locked installer physically materializes only
  the reviewed hosted-search provider after each profile package install. Run
  its check plus the repository replay self-check and exact-marker dry run
  before applying unrelated patches.

See [Local DSH core, Desktop, and GitHub Copilot practice](docs/local-core-desktop-copilot.md).
