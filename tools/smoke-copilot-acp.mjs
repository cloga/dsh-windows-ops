import { createRequire } from 'node:module'
import { spawn } from 'node:child_process'
import { Writable, Readable } from 'node:stream'

const require = createRequire(import.meta.url)
const searchPaths = [
  process.env.DSH_HOME,
  process.env.APPDATA ? `${process.env.APPDATA}/npm/node_modules` : '',
  process.cwd(),
].filter(Boolean)
const pluginPackage = require.resolve('@deepseek-ai/dsh-subagent-acp/package.json', { paths: searchPaths })
const acpUrl = new URL('./node_modules/@agentclientprotocol/sdk/dist/acp.js', `file:///${pluginPackage.replaceAll('\\', '/')}`)
const acp = await import(acpUrl.href)

class Client {
  async requestPermission(params) {
    const reject = params.options.find((option) => option.kind === 'reject_once' || option.kind === 'reject_always')
    return reject
      ? { outcome: { outcome: 'selected', optionId: reject.optionId } }
      : { outcome: { outcome: 'cancelled' } }
  }

  async sessionUpdate(params) {
    const update = params.update
    if (update.sessionUpdate === 'agent_message_chunk' && update.content.type === 'text') {
      process.stdout.write(update.content.text)
    }
  }
}

const command = process.env.COPILOT_CLI_PATH || 'copilot'
const child = spawn(command, ['--acp'], { stdio: ['pipe', 'pipe', 'inherit'] })
const stream = acp.ndJsonStream(Writable.toWeb(child.stdin), Readable.toWeb(child.stdout))
const connection = new acp.ClientSideConnection(() => new Client(), stream)
try {
  const initialized = await connection.initialize({ protocolVersion: acp.PROTOCOL_VERSION, clientCapabilities: {} })
  console.error(`\nACP agent: ${initialized.agentInfo?.name} ${initialized.agentInfo?.version}`)
  const session = await connection.newSession({ cwd: process.cwd(), mcpServers: [] })
  const result = await connection.prompt({
    sessionId: session.sessionId,
    prompt: [{ type: 'text', text: 'Reply with exactly COPILOT_ACP_OK. Do not use any tools.' }],
  })
  console.error(`\nstopReason=${result.stopReason}`)
  if (result.stopReason !== 'end_turn') process.exitCode = 1
} finally {
  child.stdin.end()
  setTimeout(() => child.kill(), 1000).unref()
}
