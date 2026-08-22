# DSH 视觉双通道（官方 + vision 工具兜底）

> 目标：text-only 模型（flash/pro）也能"看图"，image-capable 模型（vision-exp）直接用官方通道，二者共存不冲突。

## 背景

DSH 官方 `dsh-llm-deepseek` 0.1.1 起有官方视觉通道（Files API 上传 → `file_id`），但**只对声明了 `inputModalities: [text, image]` 的模型**生效；text-only 模型收图只给占位文本（`[image omitted because this model accepts text only...]`），**无任何转发**。

往 DSH 里贴图 → `apiProxy.sessions.prompt` → 官方门检查 `resolveModelInfo(当前模型).inputModalities` → text-only 直接拒绝（前端横幅「当前模型不支持图片」）。

## 双通道设计

| 会话模型 | 通道 | 行为 |
|---|---|---|
| image-capable（`deepseek-v4-flash-vision-exp`） | **官方** | admission 放行原始图片 → 官方适配器（Files API 上传，回退 base64；640k 像素/1MiB 预算）→ 模型原生看图 |
| text-only（`deepseek-v4-flash` / `deepseek-v4-pro`） | **兜底** | admission 拦截：图片保存到本地 `TMP_DIR`，替换为 path hint `[Image #N auto-saved to ...]` + 提示"调用 vision 工具"，模型自动调 `vision` 工具（后端=DeepSeek 官方 vision API，免额外 key） |

## 关键实现点（`dsh-vision-any` 插件 + 官方配置）

### 1. 模型目录声明（必须双层）
runtime 的 `resolveModelInfo` 需要模型清单里 vision-exp 声明 `[text, image]`：

```yaml
# ~/.dsh/cordis.patch.yml（GUI 设置页保存会整文件重写 settings.yaml，放 patch 更稳）
- id: llm-deepseek
  config:
    models:
      - id: deepseek-v4-flash
        name: DeepSeek-V4-Flash
        inputModalities: [ text ]
      - id: deepseek-v4-pro
        name: DeepSeek-V4-Pro
        inputModalities: [ text ]
      - id: deepseek-v4-flash-vision-exp
        name: DeepSeek-V4-Flash-Vision-Exp
        inputModalities: [ text, image ]
```

### 2. admission 判定铁律（踩坑 2026-08-22，已 PR #2）
`currentModelOf` **必须镜像官方门 `selectionFor(agent).current` 的解析顺序**：

```
selectModel GUI 选择 > 会话 requestHeader > 默认选择
```

**严禁跨源优先找 vision 名**！旧实现（上游）"任一源含 vision 就判 vision"导致：

- GUI 切到 flash，但 `requestHeader`/`options` 残留旧 vision-exp → admission 误判 image-capable → **放行** → 官方门按真模型 flash 拒图 → 用户看到「当前模型不支持图片」，hint 和 vision 工具**轮不到出现**（2026-08-22 必现）

### 3. 模型名优先于 catalog
0.1.1 适配器 read 路径对 vision-exp 返回 `["text"]`（配置声明了 `[text, image]` 也如此）——所以 admission 判定：**模型名含 `vision|multimodal|vlm|image` 直接 image-capable**，不信 catalog；仅非 vision 名才查 catalog；catalog 查询失败保守放行。

### 4. systemPrompt 中性化
原插件无条件说 "The active model is text-only" → **误导 vision-exp 模型调 vision 工具**。改为：

```
Image handling: if the active model supports images, pasted images are delivered to it directly.
If the active model is text-only, the image is saved to <TMP_DIR> and replaced with a hint like "[Image #N auto-saved to ...]"; then call the `vision` tool with that exact path.
```

## 验证方式

- `/model-info`（自建 `/brand-info` 同源）应返回三个模型 modalities：
  `{"deepseek-v4-flash":["text"],"deepseek-v4-pro":["text"],"deepseek-v4-flash-vision-exp":["text","image"]}`
- vision-exp 会话发图 → **原生进模型**（无 hint 提示）
- flash 会话发图 → 出现 `[Image #N auto-saved ...]` + 模型调 vision 工具

## 已回馈上游
- `tianmingwan/dsh-vision-any` [PR #2](https://github.com/tianmingwan/dsh-vision-any/pull/2)：model-aware admission（byName + 诊断日志）+ systemPrompt 中性化
