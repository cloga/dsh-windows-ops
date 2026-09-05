# Cross-repository GitHub network policy / 跨仓库 GitHub 网络策略

## Default: ordinary Git / 默认普通 Git

Ordinary Git over official HTTPS is the default. The wrapper is OPTIONAL, not a prerequisite and not a connectivity repair service. Keep it for opt-in safety checks, bounded retries and verified downloads; a missing or failed wrapper must not by itself block ordinary Git.

**中文：** 默认使用普通 Git + 官方 HTTPS；共享工具是可选安全辅助，不再强制所有仓库通过它。保留凭据保护、TLS 校验、功能分支/PR 和不确定推送对账要求，不意味着工具失败后可以绕过这些要求。

Before an authenticated write, verify the expected identity through the official `/user` API, inspect the existing remote and trusted hooks, and confirm the intended feature ref is not the default branch. Load credentials only from the user's designated source. Inject the scoped Authorization header using child/process-only `GIT_CONFIG_COUNT` / `GIT_CONFIG_KEY_n` / `GIT_CONFIG_VALUE_n`, never a token in argv, a URL or persistent Git config. Keep TLS enabled and redirects disabled; inspect conflicting URL-specific settings rather than weakening them. Do not print secret-bearing environment/config output.

Normal Git does not automatically run the wrapper's checks. Use an explicit destination, for example `git push origin <verified-sha>:refs/heads/<feature-branch>`, and preserve normal hooks, non-force updates and PR review. On a timeout/reset, read the exact remote ref using Git or the official API before another push: matching SHA means delivered; absent/different SHA permits a bounded non-force retry after checking divergence; unavailable verification means stop as uncertain. This rule also applies when switching from the wrapper to normal Git. Never substitute API-created commits for a failed Git push.

## Optional toolkit route / 可选工具路径

Use official HTTPS with process-scoped GitHub Token authentication. A token authenticates Git HTTPS and the REST API; it cannot authenticate SSH, including `ssh.github.com:443`. Do not select a third-party mirror or weaken TLS verification because authentication failed.

2026-09-05 spot checks found GitHub Git HTTPS working on four repository reads, API/Raw/codeload returning 200 twice, and a real Release checksum download succeeding. SSH 443 completed its handshake but public-key authentication failed. MSFTVPN was disconnected with split tunneling enabled; previous attempts returned 628. Official npm still failed TLS while the configured Microsoft npm feed was reachable. These measurements are point-in-time evidence, not a long-term availability promise. Treat npm separately.

**中文：** 目前使用官方 HTTPS 主通道；共享脚本统一处理 Token、网络错误分类和有限重试。SSH 443 尚未完成认证，不自动切换；MSFTVPN 只能作为明确选择的备用措施，不能认定连上就一定改善 GitHub。不得把 Token 放进 URL，也不得配置全局镜像 `insteadOf`。

## One tool, all repositories / 单一工具服务所有仓库

`tools/github-network.mjs` requires Node >=22 and Git. Invoke it by absolute path from any existing repository; no per-repository copy, PATH change, credential-helper installation, SSH-key generation, or global Git/proxy change is needed.

In the examples, set these **process-local variables** to your existing checkout and explicitly designated credential file:

```powershell
$tool = Join-Path $OpsRoot 'tools/github-network.mjs'
# $TokenFile identifies the existing trusted .env; never copy it into a repo.
node $tool check --token-file $TokenFile --account cloga
node $tool git --repo . --operation ls-remote --token-file $TokenFile --account cloga
node $tool git --repo . --operation fetch --remote origin --token-file $TokenFile --account cloga
node $tool git --repo . --operation push --remote origin --branch cloga-example-feature --token-file $TokenFile --account cloga
```

- `check` verifies the account and probes official endpoints. It does not prove write permission.
- `ls-remote` checks repository access without changing it.
- `fetch` updates the selected remote's tracking refs (no prune, no submodule recursion). It does not rebase or modify working files. Review local work before a separate merge/rebase.
- `push` sends the **frozen current HEAD** to the explicitly named feature branch, without force or hook bypass. It refuses `main`, `master`, the server-advertised default branch, unknown default branches, multiple remote URLs, and differing fetch/push destinations. Existing Git hooks remain active and must be trusted, since hooks run in the authenticated child environment. PR delivery remains mandatory.
- Only credential-free canonical `https://github.com/OWNER/REPO[.git]` remotes are accepted. URL rewrite rules cause an explained refusal before Git network access; inspect them manually rather than silently deleting them.

The wrapper reads exactly one `GH_TOKEN` assignment, checks the expected account through `/user`, clears child credential helpers/tracing, forces TLS verification and disables Git redirects. Authorization is scoped to `https://github.com/` in child-only Git configuration environment variables; it is never passed in argv, a remote URL, or a repository file. Raw subprocess output is not displayed because Git or hooks can echo credentials. Local environment, trusted system Git configuration, credential file access, and trusted hooks are part of the operator trust boundary; this tool is not a sandbox against malicious local software.

### Limits and diagnosis / 限制与诊断

The current wrapper adds API identity verification and a Git `ls-remote --symref` default-branch lookup before a push. Each Git transport subprocess has a 90-second deadline; it sets `http.lowSpeedLimit=1` and `http.lowSpeedTime=20`. These differ from ordinary Git and may interrupt slow but otherwise valid operations. Retries and reconciliation can take longer than 90 seconds overall. Do not place a shorter outer timeout around it; use a managed background job. These limits are documented here, not changed by this policy update.

The wrapper deliberately suppresses raw output to avoid leaking credentials. A failure category is not a complete transport diagnosis. If comparing routes, use the same host, repository, command and intended ref; alternate ordinary/tool environments using read-only probes, report elapsed times/exit status without secrets, and distinguish Node API probes from Git transport. Never use repeated pushes as a connectivity benchmark.

On September 5, 2026, a Trinity-Alpha wrapper push failed and a later ordinary push succeeded. A subsequent paired read-only test used identical `ls-remote --symref` commands with ordinary/tool/tool/ordinary environments: all four failed in approximately 21–31 seconds (the comparison imposed its own 30-second cap). This supports intermittent connectivity, not a proven wrapper-caused failure or a reliability improvement. The 21 synthetic unit tests passed; they validate safety logic, not Internet uptime.

**中文：** 工具不负责修复 DNS、网络路由或 GitHub 服务。默认查询失败、超时或 `uncertain-push` 都应报告具体阶段；改用普通 Git 前仍需对账并保留安全边界。若以后增加可配置超时或脱敏诊断，必须补测试并单独验证，不能把本次文档调整说成已实现这些功能。

### Retries and uncertain writes

Only classified network failures receive up to three attempts, with 1s/2s delays. Authentication, authorization, missing repository, conflicts, TLS trust failures and rate limits stop without automatic VPN/retry. HTTP 403 conservatively stops because it can also mean rate limiting.

After a push network failure, the tool reads the exact destination ref:

- matching frozen SHA: treat as an acknowledged success, do not push again;
- different or absent ref: retry the same non-force push within the limit;
- verification unavailable: report `uncertain-push` and stop. Query remote state later before retrying.

If an operator explicitly wants the existing saved VPN fallback, append `--vpn MSFTVPN`. The command attempts `rasdial MSFTVPN` at most once per retry loop after a network failure, then verifies by retrying the original operation. It never creates a VPN, supplies VPN credentials, changes routes, or disconnects. An uncertain push never starts a new push loop merely to activate VPN. Do not rely on this fallback until its 628 failure is resolved.

### API Issue/PR writes

This toolkit intentionally does **not** implement arbitrary POST/PATCH/PUT retries or transparent REST replacement for Git commits. Continue using the GitHub REST API and the designated Token in memory, verifying `/user` before writes. On an uncertain Issue/PR creation outcome, query existing matching records before another POST. Check merged status/head SHA before retrying a merge. Never send the Token through third-party mirrors or forward API Authorization across a redirect.

## Verified public downloads / 公开制品校验下载

```powershell
node $tool download --url $OfficialAssetUrl --output $ArtifactPath --sha256 $TrustedSha256
# Legacy entry point now delegates to the same safe downloader:
.\tools\gh-dl.ps1 $OfficialAssetUrl $ArtifactPath $TrustedSha256
```

The downloader sends **no Token**. It accepts only known official GitHub HTTPS hosts and validates every redirect (up to six requests), downloads at most 256 MiB, checks nonempty bytes against the supplied SHA-256, and publishes only verified bytes. Existing matching bytes are reused as cache; differing destinations are never overwritten. Partial files are removed on ordinary failures. Hard process termination can leave a `.part` file; it is never a valid cached artifact. Publication uses an exclusive hard link in the destination directory, requiring a filesystem that supports hard links. Unsupported filesystems fail without publishing unverified data.

Obtain the expected hash from a trusted release manifest, reviewed lock, or signature-verified source **before** downloading. A digest calculated solely from an unknown mirror is not independent verification. Private assets and files above the size limit require a separately reviewed download path; this command must not be extended with a mirror credential shortcut.

Allowed destinations include `github.com`, `api.github.com`, `raw.githubusercontent.com`, `codeload.github.com`, `release-assets.githubusercontent.com`, `objects.githubusercontent.com`, `objects-origin.githubusercontent.com`, and `github-releases.githubusercontent.com`. This is a reviewed allowlist, not a complete list of all GitHub services; additions need review.

## User-level adoption / 用户级自动采用

In the user's DSH `AGENTS.md`, record:

1. Absolute path to the maintained Windows Ops toolkit and designated token file.
2. Default to ordinary official-HTTPS Git. Use this tool only when its optional safety/diagnostic/download features are useful; do not require it for every repository operation.
3. Do not clone duplicates, override dirty work, mutate remotes, or create SSH keys automatically.
4. Use bounded retries and reconcile uncertain writes; never retry authorization failures via another identity or a mirror.
5. Call a saved VPN only under the approved fallback rule; do not blindly reconnect a persistently failing profile.

New DSH sessions load user instructions automatically. Existing sessions may need their instructions refreshed; other agents/editors require a reference in their own user-level instruction file. Ordinary `git` commands are not intercepted. The policy is an agent convention plus executable tooling, not an OS-wide traffic redirect.

## Validation and rollback

Implementation smoke on 2026-09-05: the new toolkit authenticated as `cloga` and read the Windows Ops remote successfully. A public `Node.gitignore` download pinned to `github/gitignore` commit `361f1e6afa729dc58ec33bf0849772a03ddf6822` matched SHA-256 `119a33f6ca0e1aa09aca0a66af3f394749e646c13986d2529bd2a594e9a2cd00` (2,189 bytes), independently derived from the official Contents API; a second invocation reused the verified cache. A separate Release-asset smoke hit network errors, exhausted the bounded retries, and published no destination. The saved VPN returned 628. This tool handles failures safely; it does not repair the underlying network or promise uninterrupted downloads.

```powershell
node --test tests/github-network.test.mjs
```

Tests use synthetic credentials, fake transports and temporary fixtures: URL restrictions, dotenv parsing, identity checks, finite retry/VPN behavior, rejected destinations/default branches, lost-push reconciliation, sensitive-output suppression, download redirects/integrity/cache and no overwrite.

Rollback: remove the user-level instruction block (restore its timestamped backup if appropriate). No global Git, registry, SSH, proxy or environment settings are changed. Repository scripts can be reverted through a PR. The old mirror-first downloader and Token-in-URL instructions are intentionally retired; Git history preserves them only as historical evidence, not as supported practice.

Official references:
- https://docs.github.com/en/authentication/troubleshooting-ssh/using-ssh-over-the-https-port
- https://docs.github.com/en/get-started/using-github/troubleshooting-connectivity-problems
