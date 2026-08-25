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

- Keep the official DSH Desktop shell unless the task specifically changes the
  shell.
- For `cloga/deepseek-harness` changes, build a local `@deepseek-ai/dsh`
  tarball and make Desktop run that local CLI. Do not redirect Desktop's
  bundled-core release URL as a substitute for local-core testing.
- Prefer an explicit `DSH_CLI_PATH` when more than one `dsh` executable exists.
  Otherwise, verify that Desktop selected the global local CLI.
- Do not use Desktop's local-core update action while testing the fork; it
  installs `@deepseek-ai/dsh@latest` and can replace the fork build.
- Treat plugins and the core as separate compatibility layers. Run the
  repository preflight/self-check and exact-marker dry run before applying
  patches or changing a profile.

See [Local DSH core, Desktop, and GitHub Copilot practice](docs/local-core-desktop-copilot.md).
