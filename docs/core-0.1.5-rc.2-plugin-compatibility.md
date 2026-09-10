# Core 0.1.5-rc.2 plugin compatibility follow-up

This is a **plugin-source certification record**, not a replacement Desktop lock,
installer manifest, local installation receipt, or authorization to restart.
The existing `deployments/windows-copilot.lock.json` remains unchanged.

## Exact upstream target

Official tag [`dsh-v0.1.5-rc.2`](https://github.com/deepseek-ai/deepseek-harness/releases/tag/dsh-v0.1.5-rc.2)
resolves to `fb2c4b9e698e30edb738bca4cf0618587db7d203`.
Use that full commit for source fixtures rather than a moving branch/version label.
Earlier supported Core pins must remain covered independently.

Compared with `0.1.5-alpha.2`, the consumed pi-ai adapter, Session persistence
and MCP-client implementation trees are unchanged. That observation narrows the
review; it does **not** replace actual adapter/handle regressions or allow a new
version through an old exact allowlist automatically.

## Tracked candidates — not publication evidence

| Plugin | Candidate | Tracking | Required evidence |
|---|---|---|---|
| Copilot | `0.4.0-alpha.13` | [Copilot #109](https://github.com/cloga/dsh-github-copilot/issues/109) | rc.2 actual native adapter, Session and Remote fixtures; retain earlier runtime baselines and full release dependency prerequisites |
| Cron | `0.4.8` | [Cron #32](https://github.com/cloga/dsh-cron/issues/32) | execute the tagged `JsonlSessionHandle`, not only source markers; preserve ownership and close-before-resume tests |
| Playwright Host | `0.1.6` | [Playwright #13](https://github.com/cloga/dsh-playwright-host/issues/13) | five exact commit/version source-seam gates; unchanged MCP patch and strict source-selection checks |

Candidate versions and source PRs are not immutable Release proof. Publication
requires successful required CI, an authorized merge, an exact annotated tag,
immutable Release status, tarball identity and independently verified checksums.
Do not install a candidate or local source archive as if it were that Release.

## Preserved runtime and maintenance boundaries

- Copilot and Cron package peer declarations must admit rc.2 explicitly without
  dropping older tested releases. Source-runtime tests must actually select rc.2;
  a condition limited to `alpha` versions can silently skip the new target.
- Copilot release preparation must install both pi-ai and Session Controller
  dependency closures before the actual tagged Session/Remote fixture runs.
- Playwright remains `@playwright/mcp@0.0.80`, stdio, installed Edge and
  `--isolated`. This protects the everyday browser profile, **not concurrent DSH
  Sessions from each other's shared Host MCP process**. Source-marker checks do
  not establish a working browser session.
- Preserve quarantined overlays and original bundle membership. Core/API source
  compatibility does not authorize re-enabling Sidebar, Worktree, Scheduler or
  other disabled contributions.
- Use the [optional companion maintenance contract](plugins/optional-companion-suite.md)
  when evaluating a separately requested installation. That entry follows its
  exact reviewed lock; it does not track these candidates automatically. Do not
  apply an older whole-machine lock merely to obtain newer plugin certification.
- Do not replace Core, migrate credentials/routes, run package installers or
  restart Desktop/Host as a side effect of this documentation/source update.
  Installed-on-disk and loaded-runtime acceptance remain separate observations.

## 中文边界

本记录只跟踪三个自有插件对官方 `0.1.5-rc.2` 的源码与回归认证，不修改现有
Windows 部署锁，也不表示候选版本已经发布、安装或加载。保留旧版支持；必须
实际运行 rc.2 的 adapter/SessionHandle 测试，不能仅放宽 peer 范围或添加源码
标记。Playwright 的固定版本、隔离浏览器与跨 Session 共享进程边界保持不变。
本次工作不自动更换 Core、修改账号路由、安装插件或重启；另行维护时仍需核对
精确制品、依赖闭包、运行中的 Session 和禁用配置。
