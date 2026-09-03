import assert from 'node:assert/strict'
import path from 'node:path'
import { pathToFileURL } from 'node:url'

const rc1Root = path.resolve(process.env.DSH_RC1_ROOT)
const pluginRoot = path.resolve(process.env.DSH_DEV_TOOLS_ROOT)
const fromRc1 = (relative) => pathToFileURL(path.join(rc1Root, ...relative.split('/'))).href

const [{ Context }, { default: SystemPrompt }, { default: ToolRuntime }, { default: SubprocessRuntime }, plugin] = await Promise.all([
  import(fromRc1('vendor/cordis/src/index.ts')),
  import(fromRc1('packages/core/system-prompt/src/index.ts')),
  import(fromRc1('packages/core/tools/src/index.ts')),
  import(fromRc1('packages/subprocess/subprocess/src/index.ts')),
  import(`${pathToFileURL(path.join(pluginRoot, 'index.js')).href}?lifecycle=${Date.now()}`),
])

class MockSubprocessRuntime extends SubprocessRuntime {
  async resolveExecutable(command) { return command }
  spawn() { throw new Error('lifecycle registration test must not spawn') }
  async spawnTerminal() { throw new Error('lifecycle registration test must not spawn a terminal') }
}

const names = ['dsh_status', 'dsh_doctor', 'dsh_patch', 'dsh_build', 'dsh_upgrade']
const ctx = new Context()
await ctx.plugin(SystemPrompt)
await ctx.plugin(ToolRuntime)
await ctx.plugin(MockSubprocessRuntime)
const fiber = await ctx.plugin(plugin)
for (const name of names) assert.ok(ctx.tools.get(name), `${name} was not registered`)
await fiber.dispose()
for (const name of names) assert.equal(ctx.tools.get(name), undefined, `${name} survived Fiber disposal`)
