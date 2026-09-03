# Security policy

## Supported baseline

Security fixes apply to the deployment lock on the default branch. Historical locks, incidents, migration signatures, and community-catalog entries remain available as evidence but are not maintained deployment baselines unless explicitly marked otherwise.

## Report privately

Do not open a public issue for exposed credentials, unsafe backup/rollback behavior, session-loss risk, command injection, artifact-integrity bypasses, or another vulnerability that could put a deployment at risk.

Use GitHub private vulnerability reporting:

https://github.com/cloga/dsh-windows-ops/security/advisories/new

Include the affected lock commit, Windows/Desktop/DSH versions, the exact check or apply action, a redacted reproduction, and whether any live Session or credential may have been affected. Never include a live token, OAuth grant, `.env`, credential-store payload, private message, browser cookie, or raw sensitive provider response.

## Operational boundaries

- The default installer mode is read-only check mode; mutation requires explicit `-Apply`.
- Desktop/Host restart requires a live `session/list` preflight and direct acknowledgement of the exact running Session IDs.
- `deployments/windows-copilot.lock.json` is the authoritative artifact, source, hash, install, acceptance, and rollback contract.
- GitHub Release artifacts must match the lock SHA-256; the current Copilot release also carries `SHA256SUMS` and an immutable-release assertion.
- Community catalog validation levels describe evidence, not blanket safety approval.

See [docs/security-notes.md](docs/security-notes.md) for the detailed deployment threat model and handling rules.
