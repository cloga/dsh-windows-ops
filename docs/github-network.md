# GitHub 网络优化（本机 GitHub 访问不稳的实测方案）

> 本机对 GitHub：`api.github.com` / `raw.githubusercontent.com` 直连通常 OK（~1s），但 **release 大文件下载 / git push 偶发连接重置**（curl `Connection was reset`、git `Failed to connect ... Could not connect to server`）。以下为本机实测有效的方案。

## 1. git clone/pull 走镜像（insteadOf）

```powershell
git config --global url."https://ghfast.top/https://github.com/".insteadOf "https://github.com/"
```

所有 `git clone https://github.com/...` 自动用 ghfast.top 镜像（实测稳定）。**镜像只读**（push 仍走原地址；要 push 临时清除：`git config --global --unset url."https://ghfast.top/https://github.com/".insteadof`）。

## 2. release/大文件下载走镜像（脚本）

见 `tools/gh-dl.ps1`：按序试 `ghfast.top → ghproxy.net → mirror.ghproxy.com`，第一个成功的用（>0 字节即成功）。

**关键**：`github.com/<repo>/raw/...` 这种**网页跳转路径**镜像处理不好（会 302 错乱），**raw 文件应改直连 `raw.githubusercontent.com`**（本机 ~900ms 稳定），脚本已内置该改写。

## 3. 无 SSH key 时 push 的变通

hmm, push 直连间歇性失败时：
- **重试**：直连有时第二次就通（本机实测）
- 镜像 push 不可靠（只读为主）
- 需要 token 的 `x-access-token:<PAT>@github.com/<owner>/<repo>.git` 直连即可

## 4. 其他

- `npx` 在无 `AppData\Roaming\npm` 的机器上恒报错（npx 的 npm prefix 未创建）——**别依赖 npx 拉包，直跑本地包**（见 startup-60s 文档）
- 本机 `D:\Git\cmd\git.exe`（PATH 里无 git，用全路径）

## 已验证的镜像可用性（2026-08-23）

| 镜像 | clone | release 下载 | raw | push |
|---|---|---|---|---|
| ghfast.top | ✅ | ✅（8MB zip） | ❌（raw 走 302 错乱） | ❌（只读） |
| ghproxy.net | 未测 | ❌（本次失败） | ❌ | ❌ |
| mirror.ghproxy.com | 未测 | ❌（本次失败） | ❌ | ❌ |
| raw.githubusercontent.com 直连 | — | — | ✅ ~900ms | — |
| github.com 直连 | ✅（间歇） | ❌（连接重置） | — | ✅（间歇，重试即通） |
