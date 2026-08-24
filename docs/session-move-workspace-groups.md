# 会话迁移与侧边栏分组（Host Workspace 注册表）

> 2026-08-24 定型。场景：把 DSH 会话从 A 工作目录迁移到 B（如 `D:\DeepSeek` → `D:\转咪`），
> 迁移后侧边栏看不到该会话——它既不在新组、也不在旧组。

## 根因：侧边栏分组不是 header.cwd 自动归组

DSH 侧边栏（`dsh-client-ui-workspace` 的 `groupByWorkspace`）按 **Host Workspace 实体注册表**分组：

- 持久化：`<DSH_HOME>/storages/workspace.json`（storage domain，`unit.name = "workspace"`）
- 结构：`global.workspaceIds`（显示顺序）+ `global.archivedSessionIds` + `tables.workspaces[id] = { path, title, sessionIds[], createdAt, updatedAt }`
- **会话归属 = 某个 workspace 实体的 `sessionIds` 列表**，与 header.cwd 无关
- 实体的 `sessionIds` getter 动态过滤：`sessionPath(id) === record.path`（`sessionPath` = header.cwd 的 realpath）
- 不属于任何实体的会话 → 「未分组」（Ungrouped）；空会话（仅 header + agent-preset 事件）不显示，属正常

**所以只改 header.cwd / 移动文件不会改分组**：旧组的 record 里还挂着它（但 getter 过滤后不显示），
新组不认领 → 落到「未分组」，看起来就是"两边都没有"。

## 官方 API（@deepseek-ai/dsh-workspace 的 workspaceRegistry 服务）

- `detachSession(id)` / `attachSession(id)`（幂等；attach 校验 header.cwd realpath === workspace.path 后**插最前**）
- `create(path, title?)`：新 workspace **前置**到 `workspaceIds`（prepend）
- `mutate` 写回时：stamp `updatedAt`、裁剪不匹配 id、单写链串行
- `validateStoredState`（启动）：会话**只能被一个 workspace 认领**（双认领 → 拒绝启动）
- `reportFilteredCandidates`（启动）：对被 getter 过滤的 record 会话打 `logger.warn`——**诊断线索**
- `global.pendingMutation` 存在 = domain 处于恢复中，**禁止手动操作**

## 修复顺序（铁律）

**先 detach 旧 → 后 attach 新**。中间态＝无归属（无害）；反过来的中间态会在磁盘上出现
双认领，若进程死在该窗口 → 下次启动拒启。

## 三种修复途径

### 1. 标准迁移工具（推荐）：`tools/dsh-move-session.mjs`（v2）

```
node dsh-move-session.mjs <session-id> <target-cwd> [--dry-run]
```

一次性完成：唯一性检查 → 备份（`tools/backups/`，sessions 树外）→ 官方多帧 zstd 重写 header.cwd
+ 按 projectKey 落位 → 读回验证 → 删旧 → **workspace.json 同步** → 读出复核。幂等（重复执行 no-op）。
目标目录必须存在（realpath 校验）。`node` 需 ≥22（zstd）。

### 2. 事后修复：`tools/dsh-workspace-fix.mjs`

适用：旧版工具/手工搬过的会话、或注册表被写乱的残留。

```
node dsh-workspace-fix.mjs <session-id> <target-cwd> [--dry-run]   # 定点
node dsh-workspace-fix.mjs --auto [--create-missing] [--dry-run]   # 全量对账
```

`--auto` 对每个"record 中含但 getter 被过滤"的会话按真实 cwd 归位；目标目录无 workspace 时
默认跳过（保留残留在 record 中——无害，仅显示忽略），`--create-missing` 则创建。

### 3. 运行时修复（DSH 运行中、不想重启）：动态 Cordis 插件

`tools/workspace-fix-plugin.template.js` → 替换 `__SESSION_ID__` / `__TARGET_CWD__` 后粘贴进
`cordis_define`（host half）→ `cordis_run`。走 `workspaceRegistry` 官方写链 +
`host/workspace-changed` 实时推送，**无需重启**；验证看 desktop.log 的 `[wsfix]` 行。
场景：DSH 正在运行、迁移未走工具（此前的 23831cec 事故即用此法修复）。

## 文件层修改的前提

应用**关闭**时执行。运行中的进程在下次 workspace 写时可能整文件覆盖磁盘改动（storage domain
启动读一次、写时整写）；工具会打印运行进程警告（tasklist 检测）。文件层语义与官方一致
（attach 插最前 / 创建 prepend / updatedAt=ISO / pendingMutation ABORT / 单归属）。

## 验证链

1. `node preflight-check.mjs` → PREFLIGHT CLEAN（重复 id / stray 目录 / header 位置一致性）
2. `node dsh-move-session.selftest.mjs` → ALL PASS（隔离 DSH_HOME 合成数据全链路 16 断言）
3. 启动后：侧边栏新组可见、旧组不再、Ungrouped 不含该会话；
   若页面未更新 → **F5 刷新**（该版本侧边栏不随推送自动重拉）

## 共享库：`tools/dsh-workspace-lib.mjs`

`loadWorkspace` / `saveWorkspace` / `inspectWorkspace` / `requireConsistent` / `findOwners` /
`detachFrom` / `attachTo` / `createWorkspace` / `canonicalDir` / `canonKey` / `runningHint`。

## 环境要求

- Node ≥ 22（zstd 官方帧 API 依赖 `node:zlib` 的 zstd 支持）
- zstd 包路径可用 `DSH_ZSTD` 覆盖（默认 `.../node_modules/@deepseek-ai/dsh-session-persistence-jsonl/lib/types/zstd.js`）
- 工具用 `DSH_HOME` 隔离测试（selftest 即如此）
