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

## 3. push 的正确姿势（insteadOf 会拦截带 token 的 push！）

**坑（2026-08-23 实测）**：`url.insteadOf` 全局配置对 **push 同样生效**——`git push https://github.com/...` 会变成 `git push https://ghfast.top/https://github.com/...`，而**镜像只读**，带 token 的 push 返回：

```
remote: Invalid username or token.
fatal: Authentication failed for 'https://ghfast.top/https://github.com/<owner>/<repo>.git/'
```

**姿势 A：push 前临时移除、push 后恢复**（最通用，无需改 remote）：

```powershell
# 1) 临时移除镜像规则
git config --global --unset url."https://ghfast.top/https://github.com/".insteadOf

# 2) push（直连 + token；间歇失败就重试一次——实测第二次常通）
git push https://x-access-token:<PAT>@github.com/<owner>/<repo>.git <branch>

# 3) 恢复镜像规则
git config --global url."https://ghfast.top/https://github.com/".insteadOf "https://github.com/"
```

**姿势 B：pushurl 一劳永逸**（clone/pull 走镜像、push 走直连共存）：

```powershell
git remote add origin https://ghfast.top/https://github.com/<owner>/<repo>.git   # fetch/pull 走镜像
git config remote.origin.pushurl https://github.com/<owner>/<repo>.git          # push 走直连（token 嵌 URL 或凭据助手）
```

> 或者最精简：直接在仓库里 push 时用 `git push https://x-access-token:<PAT>@github.com/<owner>/<repo>.git <branch>`（忽略 remote 的 URL，每次显式直连）。

**无 SSH key 时**：token 用 `x-access-token:<PAT>@github.com/...` 直连即可；直连间歇失败就重试（本机实测第二次通）。

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
