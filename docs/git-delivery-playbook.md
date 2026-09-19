# Verified Git delivery playbook / 已验证的 Git 交付操作指引

## Find this first / 先看这里

这是跨会话的稳定入口，不依赖某次聊天或临时诊断脚本。普通 Git 的安全规则仍由 [GitHub 网络策略](github-network.md)规定；本机已验证的 Git 可执行文件绝对路径和凭据来源记录在用户级 `~/.dsh/AGENTS.md`，不要把机器路径或凭据值复制进仓库默认配置。

This is the durable cross-session entrypoint, not a dependency on one conversation or scratch script. [GitHub network policy](github-network.md) remains authoritative for safety. The machine's verified executable path and approved credential source belong in the user's `~/.dsh/AGENTS.md`, not repository defaults.

## Verified native profile / 已验证的普通 Git 组合

2026-09-19 的已验证组合如下。它是可复现的排查起点，不保证网络长期可用，也不证明 Git 版本或 HTTP 版本是唯一原因。

The following combination was verified on 2026-09-19. It is a reproducible starting point, not an uptime guarantee or a single-variable causal diagnosis.

| Item / 项目 | Verified value / 已验证值 |
|---|---|
| Git executable / Git 程序 | Existing Git for Windows 2.53.0-4; use the exact user-level path, not an assumed PATH entry / 使用用户级指引中的现有绝对路径 |
| HTTP | Process-scoped `http.version=HTTP/1.1` / 仅当前子进程 |
| TLS | `http.sslVerify=true` |
| Redirects / 重定向 | `http.followRedirects=false` |
| Credential helper / 凭据助手 | Empty child-scoped `credential.helper`; no new helper / 子进程内清空，不新增助手 |
| Authentication / 认证 | Approved credential in a GitHub-only header via child environment; verify `/user` before writes / 进程内 header，写入前核验身份 |
| Native launch / 调用 | Node `spawnSync`, `shell:false`, `stdio:'inherit'`, `windowsHide:true` |
| Read probe deadline / 只读探测上限 | `45000` ms |
| Push deadline / 推送上限 | `120000` ms; use a background job when the tool's outer deadline is shorter / 外层超时更短时用后台任务 |

以下片段只说明子进程配置。`gitPath`、`repoPath`、`remoteUrl`、`exactRef` 和 `token` 必须事先从已核验的路径、仓库和获准凭据来源取得；它不是免核验的通用推送脚本。调用前清除继承的 Git tracing、`GIT_CONFIG_*` 和重复认证配置，不输出含密钥的环境变量。

This fragment describes the child-process profile only. Obtain `gitPath`, `repoPath`, `remoteUrl`, `exactRef`, and `token` from reviewed inputs first. It is not a push authorization or a substitute for repository/ref/hook checks. Clear inherited Git tracing, `GIT_CONFIG_*`, and duplicate authentication before constructing this environment; never display secret-bearing environment values.

```js
import { spawnSync } from 'node:child_process';

// Inputs are reviewed before this fragment. Only this child receives the header.
if (process.env.NODE_TLS_REJECT_UNAUTHORIZED === '0' || process.env.GIT_SSL_NO_VERIFY) {
  throw new Error('Review unsafe TLS overrides before any network call');
}
const env = { ...process.env, GIT_TERMINAL_PROMPT: '0' };
for (const key of Object.keys(env)) {
  if (/^(GIT_TRACE|GIT_CONFIG_|GIT_CURL_VERBOSE|GIT_SSL_NO_VERIFY|GIT_ASKPASS|SSH_ASKPASS|GH_TOKEN|GITHUB_TOKEN|NODE_DEBUG|LEFTHOOK_VERBOSE)/i.test(key)) delete env[key];
}
const config = [
  ['http.https://github.com/.extraheader', 'Authorization: Basic ' + Buffer.from('x-access-token:' + token).toString('base64')],
  ['http.followRedirects', 'false'],
  ['http.version', 'HTTP/1.1'],
  ['http.sslVerify', 'true'],
  ['credential.helper', ''],
];
env.GIT_CONFIG_COUNT = String(config.length);
config.forEach(([key, value], i) => {
  env[`GIT_CONFIG_KEY_${i}`] = key;
  env[`GIT_CONFIG_VALUE_${i}`] = value;
});
// Read-only: this proves ref-read connectivity, not push or release success.
const result = spawnSync(gitPath, ['ls-remote', '--heads', remoteUrl, exactRef], {
  cwd: repoPath, env, shell: false, stdio: 'inherit', windowsHide: true, timeout: 45000,
});
```

不要假定将这些环境变量传给 `github-network.mjs` 就能改变其行为：现有 wrapper 会重建 Git 配置，仍有自己的 90 秒上限及低速规则，见[限制与诊断](github-network.md)。本次没有增加 wrapper 参数或更改其默认值。

Do not assume passing this environment into `github-network.mjs` configures that wrapper: it rebuilds Git settings and retains its own 90-second and low-speed limits. See [limits and diagnosis](github-network.md). This update adds no wrapper options or changed defaults.

## Diagnose before retrying / 重试前先定位

1. 核对仓库、现有官方 HTTPS remote、准确 ref、Git 路径／版本、HTTP 设置、实际超时及上次命令结果。程序不存在或被终止不是认证失败。
2. 对同一仓库和 ref 先做只读比较。区分 API 可达、Git advertisement 可读、push 已确认和发布已核验；前一项不证明后一项。
3. 保留三次限定重试预算。换 Git 程序、HTTP 参数、wrapper 或会话不能自动重置预算。预算用尽后只读诊断；继续写入需核对新的人类请求／恢复依据及既有授权。
4. timeout/reset 或不确定写入后，先读取准确远端 ref。等于冻结的预期 SHA 就已交付；不同须检查分叉；读不到则停止，不盲推。
5. 不使用重复 push 测网速，不把错误类别当完整诊断。记录经过脱敏的失败阶段、exit code、timeout 和 elapsed time；不要记录 Token、Basic header 或完整环境。

1. Check the repository, existing official HTTPS remote, exact ref, executable/version, HTTP settings, actual deadlines and previous result. Missing executables and terminated processes are not authentication failures.
2. Compare read-only operations against the same repository/ref. API reachability, Git advertisement reads, confirmed push and verified publication are separate evidence.
3. Preserve the three-attempt budget. Switching executable, HTTP option, wrapper or Session does not reset it. After exhaustion, diagnose read-only and recheck the human request/recovery evidence and existing authorization before writes.
4. After timeout/reset or uncertain writes, read the exact remote ref first. The frozen SHA means delivered; divergence needs review; unavailable readback means stop.
5. Do not benchmark connectivity with repeated pushes or treat a category as a complete diagnosis. Record sanitized failure stage, exit code, timeout and elapsed time, never tokens, Basic headers or environment dumps.

## Hooks and alternative transport / 检查与后备传输

正常 hooks 保持启用。用户的依赖阻塞 CI 交接只覆盖获准的 pre-push build/typecheck 项；某个任务临时获准延后的 pre-commit 项不构成跨会话通用授权。不得使用 `--no-verify`、`LEFTHOOK=0` 或关闭 TLS 来“修复”网络。可信 hooks 也不应打印认证环境；共享 wrapper 对原始输出的保护仍有价值。

Keep normal hooks. Dependency-blocked CI handoff covers only its authorized pre-push build/typecheck jobs; a one-task pre-commit exception is not standing cross-session permission. Never use `--no-verify`, `LEFTHOOK=0`, or disabled TLS as a network fix. Trusted hooks must not print the authentication environment; the wrapper's raw-output protection remains useful.

Node fetch 能读官方 Smart HTTP advertisement，不等于已授权换写入客户端。只有获得明确的一次性授权后，才可评估已有 JavaScript Git 客户端：只传送已有 Git 对象，保持原提交身份；限定官方地址、目标 ref 和预期 SHA；执行真实 pre-push hook；禁止 force／delete／redirect／proxy；限制接收包 POST 次数和大小；即使响应丢失也回读准确 ref，不自动重发。多 ref／原子推送必须另核实客户端能力，不能照搬单分支脚本。不要用 REST 创建提交来代替 Git。

A Node fetch advertisement read does not authorize a different write client. An existing JavaScript Git client requires explicit one-off approval: transfer existing Git objects and preserve commit identity; constrain official URL, ref and expected SHA; invoke the actual pre-push hook; forbid force/delete/redirect/proxy; bound receive-pack POST count and size; reconcile even a lost response without automatic resend. Verify multi-ref/atomic support separately rather than copying a single-ref script. REST-created commits are not a Git fallback.

## Evidence, not a universal guarantee / 证据而非通用保证

- [Core Draft PR #75](https://github.com/cloga/deepseek-harness/pull/75): the native profile above read master in 1376 ms, then one push completed in 15303 ms. Both official-base and feature refs matched their frozen SHAs. No JavaScript-Git fallback was used. PR delivery did not establish green CI or a new release.
- [Desktop PR #69](https://github.com/cloga/deepseek-harness/pull/69): its recorded, separately approved fallback used isomorphic-git 1.41.9 with one receive-pack POST and one actual pre-push hook invocation, preserving existing commits. Its later [Desktop release](https://github.com/cloga/deepseek-harness/releases/tag/dsh-desktop-v0.1.6-alpha.1.cloga.4) was independently verified. That installer retained Core 0.1.6-alpha.1; it was not publication of the new Core model-rule feature.
- [Workspace PR #74](https://github.com/cloga/deepseek-harness/pull/74): its history includes the SHA recorded by the native Git 2.53 / HTTP/1.1 push script. Later branch movement does not negate that earlier success.

以上是已核实的案例，不保证所有会话都成功。声明发布完成仍必须检查实际项目的 CI、受控发布流程、tag/source、资产及校验值；不要把 Desktop、Core、插件版本混为一谈。本文不授权安装、重启或修改其他工作树。

These are verified examples, not proof all Sessions succeed. Publication still requires the actual project's CI, controlled release process, tag/source, assets and checksums. Keep Desktop, Core and plugin versions distinct. This guide authorizes no installation, restart or changes to other worktrees.
