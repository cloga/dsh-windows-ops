# DSH 原生视觉通道与本地图片读取

> 当前 Windows 基线只使用 DSH 官方图片附件通道和 `read_image` 文件工具；不再推荐安装 `dsh-vision-any` 或同类视觉转发插件。

## 结论

视觉理解由所选模型原生提供。DSH 负责校验、规范化、持久化并把图片作为原生 image block 送到模型：

| 图片来源 | 支持路径 | 是否需要 `read_image` |
|---|---|---|
| 用户在会话中粘贴或上传 | DSH attachment admission → 当前 LLM adapter → 模型原生视觉输入 | 否 |
| Agent 需要查看工作区中的 PNG/JPEG/WebP/GIF | `read_image` → `ctx.fs` 有界读取 → attachment store → 下一次模型请求 | 是 |

`read_image` 不实现视觉推理，也不调用独立视觉模型。它只是把模型原先只能看到的文件路径转换成持久的图片内容块；最终仍由当前模型的原生视觉能力理解图片。

## 官方组件

当前能力来自 DSH 第一方包：

- `@deepseek-ai/dsh-attachment-local`：保存、校验、缩放或转码图片附件；
- `@deepseek-ai/dsh-tool-fs`：注册 `read_image`，通过当前 `ctx.fs` 后端读取本地图片；
- 当前 LLM adapter（Windows Copilot 基线使用内建 `llm-pi-ai`）：把 Harness image block 投影为提供方支持的原生图片输入。

这些组件属于官方 Cordis 组合。它们是插件化的第一方 Core 能力，不是 `dsh-github-copilot`、Desktop patch 或 Windows Ops 自建的视觉实现。

## 模型能力门禁

只有模型目录明确声明图片输入时，DSH 才允许图片进入该路由。目录应以显式 metadata 为准，例如：

```yaml
input: [ text, image ]
```

不要根据模型名称中是否包含 `vision`、`image`、`vlm` 等字符串猜测能力。当前 Core 会解析所选 provider/model 的 `inputModalities`；`read_image` 也会在任何图片文件 I/O 前检查同一条路由。

如果当前模型只声明 `text`：

- 用户上传的图片不会被当作该模型可理解的视觉输入；
- `read_image` 会拒绝执行并提示切换到 image-capable 模型；
- Windows 基线不会把图片暗中转发给第二个视觉提供方。

这种失败是明确的能力边界，而不是需要再安装一个通用视觉插件的信号。

## 为什么退役 Vision Any fallback

旧设计为 text-only 路由保存图片路径，再提示模型调用 `dsh-vision-any` 的 `vision` 工具。当前基线不再采用它，因为它会引入第二套：

- 模型能力判断；
- 图片 admission 与临时文件生命周期；
- 外部视觉提供方、凭据和数据流；
- 提示词与工具调用约定。

这与 DSH 已有的附件、文件系统、模型目录和原生视觉通道重复，而且容易让“当前模型是否真正支持图片”与“另一个工具能否代看图片”混为一谈。

`dsh-vision-any` 仍作为历史评估记录保留在插件目录中，但推荐状态为 `historical`，不属于锁定 Windows Copilot 基线，也不应由 bootstrap 或可选套件安装。

## 验证

1. 在 Models 中确认目标模型明确显示 text + image 能力。
2. 新建该模型的 Session，直接上传一张测试图片；模型应在同一用户消息中收到原生图片，而不是路径 hint。
3. 让 Agent 查看工作区中的测试图片；应调用内建 `read_image`，工具结果包含图片内容块。
4. 切换到明确的 text-only 模型并调用 `read_image`；应在读取文件前得到 image-capability 拒绝。
5. 检查 Web/headless composition 和插件清单，确认没有安装 `dsh-vision-any` 或其他视觉转发 fallback。

## 历史记录

早期双通道方案和 `tianmingwan/dsh-vision-any#2` 曾用于研究 text-only 路由的工具兜底。它们不再代表当前推荐架构；历史链接仅用于解释迁移背景。
