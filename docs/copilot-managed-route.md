# Copilot managed-route maintenance / 自动识别路由维护

## 中文

这是 **只改配置** 的维护流程，不是完整安装器，也不是新的 Desktop/Core 部署基线。`deployments/windows-copilot.lock.json` 仍约束完整安装；本流程使用单独的 `deployments/copilot-managed-route.policy.json`，记录经验证的不可变插件 Release 和只读迁移协议。不能据此把当前机器宣布为完整锁定基线。

目标是一个共享的 Copilot 账号和自动发现目录，各个 Session 独立选择模型。搜索跟随发起请求会话的有效请求配置。只有移除实际原生路由后，Chat 与 `/model` 才只剩一个 Copilot 分组；隐藏分组或改显示名称不算迁移。

### 先检查，不做隐式安装或重启

```powershell
# 被动实时检查：不查询模型目录，不触发账号发现。
# 因缺少目录证据，catalog-unverified 是正常的阻止原因。
.\tools\migrate-copilot-managed-route.ps1 -Live

# 明确允许读取账号模型目录；可能触发缓存更新和原生 OAuth 刷新。
.\tools\migrate-copilot-managed-route.ps1 -Live -AllowAccountDiscovery
```

- 策略中的确切插件版本必须已经在 Host **加载**，不仅安装到磁盘。插件的 `githubCopilot/migrationStatus` 提供加载版本与实时 live-Agent 模型依赖；磁盘版本和可能过期的 `session/list` 都不能替代它。
- 这个接口不读取凭据、不查询模型、不写设置或 Session。它的加载版本和结构能力报告不是 Desktop/Core 的完整字节证明。
- 缺少接口、未知/不完整会话证据、原生默认模型、原生会话选择或仍在运行的原生请求都会阻止迁移。其他明确使用不受影响模型的会话不会被强制切换。
- 如需先更换模型，必须由操作人另行确认并使用正常选择入口。Core 的 `session.selectModel` 还会保存未来全局默认值；本工具从不自动调用它，也不直接改默认模型。
- `activeRequestSelection` 是 running Agent 最近记录的请求，不是“当前一定正在发 HTTP”的证明。
- 目录查询是有副作用的服务读取，可能更新 OAuth；只有 `-AllowAccountDiscovery` 明确允许后才执行。它不是聊天或搜索实测。

**不要**用 `install-windows-copilot.ps1 -Apply` 或旧 `enable-copilot-search-vision.ps1` 代替此流程。它们属于完整旧锁定基线，可能安装组件或写配置文件，且完整安装器会拒绝降级较新的 Desktop。新工具不会安装任何插件、替换 Core、读取凭据、停止进程或重启。

### 明确批准后 Apply

只有检查结果无阻止项、理解下面的历史影响并逐项确认后，才运行：

```powershell
.\tools\migrate-copilot-managed-route.ps1 -Action Apply -Live `
  -AllowAccountDiscovery `
  -ApproveNativeRemoval `
  -ApproveSearchAllowlist `
  -AcknowledgeColdHistoryLimitation
```

工具只会执行以下已获批准的路径级操作：

1. 将 `github-copilot.providers` 从确切的 `[github-copilot]` 改成 `[github-copilot-preview]`；不接受空列表、任意自定义列表或自动扩张列表。
2. **最后**以 namespace revision 比较交换（CAS）移除 `llm-pi-ai` 用户层的 `providers.github-copilot`。
3. 在各阶段重新读取运行状态、设置和目录，核对原生配置及真实路由已经消失、managed 目录存在且无重复。

不会移除 `llm-pi-ai` 插件挂载、OAuth 记录、其他 Provider、会话历史或修改已选模型。发现继承自 base 的原生配置、所有权 journal、可能含秘密的配置或未识别自定义内容时停止；不会清空 journal、复制凭据或强制占有配置。

**历史边界：**只读状态覆盖所有当前 live Agent，包括子 Agent，不扫描冷存储历史。冷历史文件不变，但再次打开旧会话时可能需要重新选择 managed 模型。`-AcknowledgeColdHistoryLimitation` 明确承认这一点，不代表已经迁移了这些历史。

**并发与失败：**不存在跨 namespace/Session 的原子事务。发现修订号或相关事实改变时停止；已有部分写入或无法确认写入结果时，报告 `partial-or-uncertain-review-required`，不自动重试写入、不盲目回滚其他人的修改。Core 的异步路由更新尚未收敛时，也不能报告成功；稍后只读 Verify。尽量在协调好的安静窗口进行维护。

```powershell
.\tools\migrate-copilot-managed-route.ps1 -Action Verify -Live -AllowAccountDiscovery
```

`-SnapshotPath` 仅用于离线 Check/Verify，可审阅合成或保存的输入；不能用于 Apply，也不能证明当前运行状态。不要把含设置描述的原始快照提交到仓库。

### 生成器与旧基线的关系

`Set-DshCopilotProfilePatch` / `Test-DshCopilotProfile` 具有显式 `-RouteMode Managed`。Managed 模式只识别原样生成的已知 Ops block，输出确切 `[github-copilot-preview]` 并保持 `probe: true`。被编辑的 block、引用键、自定义列表、额外字段及注释伪装需单独审阅，不能靠字符串片段冒充有效 YAML。其他不相关 block 保留。

旧完整锁定安装器的调用仍使用 `NativeLegacy`，没有被悄悄改成另一个未经整体验证的安装基线。已有 managed block 不允许被旧生成调用静默退回原生路由。这些文件生成/校验函数也不是 live 配置迁移器；实时迁移只走上述公开 RPC 与 CAS。

### 不能承诺的事

- Core 的原生 Add provider 不能被现有公开插件接口拦截。插件会警告保存它会再次增加一组模型；本工具能检测漂移，不能永久禁止重新添加。
- 完成配置迁移不代表所有模型支持搜索。协议、账号权限、能力探测仍决定每个会话的可用性。
- 策略与测试通过不等于本机已安装、已加载或已迁移。Release、磁盘安装、Host 加载和最终目录验证要分别记录。

## English

This is **configuration-only maintenance**, not an installer or a new full Desktop/Core baseline. The full installer remains governed by `windows-copilot.lock.json`; the separate `copilot-managed-route.policy.json` pins the immutable integration release and maintenance protocol. It must not certify an otherwise unverified machine.

The goal is one account and one discovered directory shared by independently selected Sessions. Search uses the triggering Session's effective request configuration. Actual native-route removal—not hidden groups—leaves one Copilot group in Chat and `/model`.

1. Run passive `migrate-copilot-managed-route.ps1 -Live` first. No account catalog call is made, so missing-catalog evidence blocks mutation.
2. Explicitly add `-AllowAccountDiscovery` for a catalog check; it can refresh metadata and native OAuth. The exact policy version must be **loaded** and supply `githubCopilot/migrationStatus`. Generic Session lists and on-disk versions are not live proof.
3. Resolve native/default/unknown live-selection blockers separately. The tool never selects models or changes defaults. Native Core model selection also changes the future default, so those decisions require their own approval.
4. After review, use `-Action Apply -Live -AllowAccountDiscovery -ApproveNativeRemoval -ApproveSearchAllowlist -AcknowledgeColdHistoryLimitation`. Only the exact native-to-managed search allowlist transition and CAS unset of the reviewed user-native provider path are permitted. Native removal is last.
5. Verify with `-Action Verify -Live -AllowAccountDiscovery`. Require configuration **and actual registry/catalog** readback; asynchronous registry convergence is not assumed.

Inherited native profiles, ownership journals, secret-bearing or custom unknown fields, malformed evidence, changed revisions and model dependencies fail closed. Preserve the native OAuth mount/record, other providers, selected Sessions and history. No plugin install, process control, credentials access or live file rewrite occurs. Do not substitute the legacy full installer or search/vision bootstrap for this operation.

The live receipt includes all loaded Agents and their pending/header/default selection provenance. It does not scan cold stored histories; those files remain unchanged and may need a new model selection when reopened. Running-request metadata is the last recorded header, not proof of an active HTTP call. The build-version and structural-capability report is not full Desktop/Core byte attestation.

There is no cross-namespace/Session transaction. Every stage re-reads relevant facts; uncertain or partial writes are reported, not retried or blindly rolled back. Use a coordinated quiet window. Offline snapshots are for review only and cannot authorize live Apply.

Managed generator mode accepts exact known generated Ops blocks, retains probing and emits only `[github-copilot-preview]`; quoted-key/comment tricks and edited/custom blocks require review. Legacy full-lock callers retain their existing mode, but cannot silently overwrite an already managed generated block with legacy policy.

The native Core Add-provider UI still cannot be vetoed by a plugin. Its warning and later drift detection are not permanent prevention. Search remains model/account/protocol/probe dependent. Report Release, installation, loaded version and final migration verification as separate facts.
