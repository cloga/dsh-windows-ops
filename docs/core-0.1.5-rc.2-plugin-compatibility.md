# Core 0.1.5-rc.2 plugin compatibility follow-up

This is a **plugin-source and release certification record**, not a replacement
Desktop lock, installer manifest, local installation receipt, or authorization
to restart. `deployments/windows-copilot.lock.json` remains unchanged.

## Exact upstream target

Official tag [`dsh-v0.1.5-rc.2`](https://github.com/deepseek-ai/deepseek-harness/releases/tag/dsh-v0.1.5-rc.2)
resolves to `fb2c4b9e698e30edb738bca4cf0618587db7d203`.
Use that full commit for source fixtures, not a moving branch/version label.
Earlier supported Core pins remain covered independently.

Compared with `0.1.5-alpha.2`, the consumed pi-ai adapter, Session persistence
and MCP-client implementation trees are unchanged. That observation narrows
review; it does **not** replace native regressions or automatically admit rc.2
through an older exact version allowlist.

## Reconciled delivery evidence

| Plugin | Verified immutable Release | Delivery | Exact release commit |
|---|---|---|---|
| Copilot | [0.4.0-alpha.13](https://github.com/cloga/dsh-github-copilot/releases/tag/v0.4.0-alpha.13) | [PR111](https://github.com/cloga/dsh-github-copilot/pull/111) | `0cd91363e277e86ba9ef0df6c675c96e8a1a3d09` |
| Cron | [0.4.8](https://github.com/cloga/dsh-cron/releases/tag/v0.4.8) | [PR33](https://github.com/cloga/dsh-cron/pull/33) | `45f86744c5e57705ccb85c360d57406c0508bab0` |
| Playwright Host | [0.1.6](https://github.com/cloga/dsh-playwright-host/releases/tag/v0.1.6) | [PR15](https://github.com/cloga/dsh-playwright-host/pull/15), [PR17](https://github.com/cloga/dsh-playwright-host/pull/17) | `d94d97ee7155c8e4241ab2e36cfcc2d96b27d9c2` |

Copilot and Playwright already had independently merged delivery when this
stalled task regained Git access. Their published sources were reviewed and
adopted rather than overwriting them with duplicate local candidates. Those
sources additionally admit exact Core rc.1
`183f08e9c6dde7e36cd2318eaee70b0da08fb35e`; Cron's follow-up adds rc.2 only.
Original tracking: [Copilot109](https://github.com/cloga/dsh-github-copilot/issues/109),
[Cron32](https://github.com/cloga/dsh-cron/issues/32),
[Playwright13](https://github.com/cloga/dsh-playwright-host/issues/13).

Official API observations confirmed non-draft immutable Releases, annotated tags
at the commits above and successful required CI. Artifact identities:

| Tarball | Bytes | SHA-256 |
|---|---:|---|
| `dsh-github-copilot-0.4.0-alpha.13.tgz` | 503564 | `6614404c1ad9d9025af985da218398399604d5b65b2910b4205ecf8d0cacc0ac` |
| `dsh-cron-0.4.8.tgz` | 45896 | `b6321a84e6f6b02f58fa9492913954062ab63da88753e79b53384a2d7e0570ae` |
| `dsh-playwright-host-0.1.6.tgz` | 6851 | `bc06873369a1a143db7f1a728a06d1515030cf7fb0e25c4e23d1565c4722e891` |

| Corresponding `SHA256SUMS` | SHA-256 of the manifest |
|---|---|
| Copilot | `ac92879c2f9ff93460fc813e133dda9fbd7b76849edf1651638eb613878a64ac` |
| Cron | `55461993f0762a2be54e142af9f1660b1f64d24d8666dd1e5402a42548fa04ef` |
| Playwright Host | `94ec3c22c8c9a335788f3cea444d268894df0376d8885aa3b7599eda98931a7d` |

These are plugin release observations, **not a new whole-machine baseline**.
Never install a local candidate archive under the same version as a verified
Release, or infer byte identity from the version alone.

## Test and maintenance boundaries

- Copilot's prerequisite seven-baseline Windows/Linux matrix executes all five
  actual rc.2 native fixture files, including Session and Remote. Both pi-ai and
  Session Controller closures are installed before preparation. Its dedicated
  release-job rerun and top-level current-target shorthand remain **alpha.2**;
  rc.2 is supported and tested by the mandatory matrix, not by a separate rc.2
  release-job rerun. Do not conflate these evidence scopes.
- Cron's five-baseline matrix explicitly selects the actual tagged rc.2
  `JsonlSessionHandle`, owner/nonmutation/close-before-resume cases and Slot
  kind/scope assertions. Synthetic storage/agents are not full JSONL migration
  or live Host acceptance.
- Playwright retains six exact source-seam pairs, the `@playwright/mcp@0.0.80`
  pin, stdio, installed Edge and `--isolated`. Isolation protects the everyday
  browser profile, **not concurrent DSH Sessions from their shared Host MCP
  process**. Source markers and a version command are not browser-session proof.
- Preserve quarantined overlays and original bundle membership. Source support
  does not authorize re-enabling Sidebar, Worktree, Scheduler or disabled peers.
- The [optional companion maintenance contract](plugins/optional-companion-suite.md)
  still follows its exact reviewed lock; it does not adopt these releases
  automatically. Do not apply an older whole-machine lock merely to obtain
  newer plugin support. Any new locked baseline needs its own complete review.
- This source/release follow-up does not replace Core, install into a Profile,
  migrate credentials/routes, or restart Desktop/Host. Installed-on-disk and
  loaded-runtime acceptance remain separate observations.

## 中文边界

本记录确认了三个插件对官方 `0.1.5-rc.2` 的支持和上述精确发布制品，不修改
Windows 部署锁，也不代表本机已经安装或加载。恢复网络后发现 Copilot 和
Playwright 已由其他提交完成交付，因此核验并采用现有发布，而非重复覆盖。
Copilot 的 rc.2 证据来自发布前必需的完整矩阵，单独的 release-job 仍复验
alpha.2，不能混为一谈。Cron 使用真实 tagged handle 配合合成存储；Playwright
源码标记不等于浏览器验收。另行安装仍需核对依赖闭包、运行 Session、禁用配置
和精确制品，本次不自动更换 Core、迁移账号路由、安装插件或重启。
