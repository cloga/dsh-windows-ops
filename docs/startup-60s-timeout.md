# 首次启动 60 秒超时根因分析（The local service did not start within 60 seconds）

> **2026-08-25 历史注**：本文针对旧 Electron 桌面壳（DeepSeek Harness.exe）。Tauri 壳（dsh-tauri-desk）有独立启动时序与下载流程，本案例机制不同；恢复时应停止孤儿 DSH 后端，再由 Desktop 正常重启，不再使用仓库内已退役的双 Home 快照或重启脚本。

## 现象

Windows 打包版桌面 shell（Electron 主进程）启动 dsh web 服务时，**冷启动**（taskkill 后立刻再开，或系统刚开机）经常弹出：

> **DeepSeek Harness could not start — The local service did not start within 60 seconds.**

**关闭应用等几分钟再打开就正常**。热重启（正常退出再开）通常不出现。

## 根因链（本机逐层证实）

```
桌面壳 main.mjs:
    spawn('--expose-internals', entry, 'web', '--host', '127.0.0.1', '--port', '0')
    等待 stdout/stderr 出现 "dsh web: http://..." 行，超时 START_TIMEOUT_MS = 60_000
        ↓
dsh web 启动 → cordis 加载所有插件（含 dsh-mcp-client）
        ↓
dsh-mcp-client 的 apply() 是 async：await connection.ready
    # MCP client 插件激活被"首个 MCP server 连接就绪"阻塞！
        ↓
我们挂了 mcp-desktop，其 config: command: npx, args: ['-y', '@harusame64/desktop-touch-mcp']
        ↓
npx 首次解析包在 flaky 网络下很慢（或失败重试）→ launcher.js 启动后：
    ensureRelease() → fetchReleaseByTag()（GitHub API）→ 网络对 GitHub 不稳 → 挂起/超时无界
    launcher 是"先下载完整 release 再 stdio"的 —— 下载完成前不进入 MCP stdio 握手
        ↓
connection.ready 永不 resolve → 插件激活阻塞 60s+ → 桌面壳超时弹错
```

**为什么"关掉过一会儿再打开就好"**：第一次 npx 把包/二进制拉进了 `~/.desktop-touch-mcp/`、npx 缓存了 `@harusame64/desktop-touch-mcp`。第二次 launcher 走内存/磁盘缓存（`isInstalled` 校验通过或下载已缓存），快 → 通过。**但 launcher 每次仍做 GitHub 版本检查**（`fetchReleaseByTag`），网络一抖又卡。

## 关键代码位置（各版本一致，1.14.3/1.15.0 均复现）

`Harusame64/desktop-touch-mcp` `bin/launcher.js`：

```js
async function ensureRelease() {
  const expected = expectedReleaseSpec();
  const targetDir = releaseDirForTag(expected.tagName);
  if (await isInstalled(targetDir, expected)) {  // 校验不过（SHA/元数据任何问题）→ 不走这里
    await writeCurrentRelease(expected);
    return targetDir;
  }
  const current = await readCurrentRelease(expected);
  if (current) return current.releaseDir;
  const release = await fetchReleaseByTag(expected);   // ← 无条件走网络，无超时！
  return installRelease(release, expected);            // ← 下载 8MB zip 无超时
}
```

- `fetch()` 无 `AbortSignal` → 网络半挂时 **TCP 连接超时可达几十秒~几分钟**
- 下载（`downloadFile`）同样无超时 → 大文件弱网下更久
- **即使本机已完整安装 release**（`~/.desktop-touch-mcp/releases/v1.14.3/`），只要元数据校验不通过（如 `.desktop-touch-release.json` 缺失/被清），照样走网络

## 修复（本机采用）

**方案 A（推荐，本机已用）**：绕开 launcher/npx 的全部网络路径，MCP 直配**本地已解压的 server 入口**：

```yaml
# ~/.dsh/cordis.patch.yml
- insert:
    - id: mcp-desktop
      name: '@deepseek-ai/dsh-mcp-client'
      config:
        serverName: desktop
        transport: stdio
        command: <node.exe>          # 任意 Node >= 18
        args: ['C:\Users\<you>\.desktop-touch-mcp\releases\v1.14.3\dist\server-windows.js']
```

实测：`node dist/server-windows.js` 直接 stdio 启动，零网络依赖，稳定待机。

**方案 B（回馈上游，见 PR #586）**：给 launcher 加**超时 + 离线优先 + 缓存回退**：
- `fetchReleaseByTag` 15s 硬超时（`AbortSignal`）
- `ensureRelease` 在本地已有目标版本目录时**优先用本地**（不再无条件走网络）
- 网络失败时扫描 `releases/` 用任一已装版本兜底

**方案 C（基建）**：`npx` 换成直接 `node <本地包>/bin/launcher.js`，仍保留其"下载+验证+启动"能力，但至少 npx 那层网络解析消失。

## 验证方式

1. 改配置后 `taskkill /IM "DeepSeek Harness.exe" /F`（或脱树重启脚本）
2. 立即重开应用 → 不再出现 60s 超时弹窗
3. `desktop.log`（`%APPDATA%\deepseek-harness-desktop\logs`）里不再有 `npm error ... AppData\Roaming\npm` 刷屏（这是 npx 失败重连循环的噪音，修复后消失）

## 附：其他可能拖慢启动的 MCP 注意事项

- `dsh-mcp-client` 的 **`failOnStartupError` 默认 false**——失败只重连不致命；但**重连循环不释放 apply 的 await**，所以"连不上"也会拖插件激活（看 connection.js 的 ready 语义）
- 多个 MCP server 串行激活——每个都 `await connection.ready`，多个 flaky server 会叠加超时（本例只 desktop 一个，60s 就卡满）


