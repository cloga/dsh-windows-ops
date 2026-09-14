import { spawn } from 'node:child_process'
import { join, resolve } from 'node:path'

const project = resolve(process.argv[2] ?? '')
if (!project || project === resolve('.')) {
  throw new Error('desktop plugin health check requires a staged profile')
}

const entry = join(project, 'node_modules', '@deepseek-ai', 'dsh-desktop-host', 'lib', 'index.js')
const child = spawn(process.execPath, [entry, project], {
  cwd: project,
  env: Object.fromEntries(Object.entries(process.env).filter(([name]) => (
    name !== 'NODE_OPTIONS' && !/^DSH_DESKTOP_/u.test(name) && !/^(?:npm|pnpm|corepack)_/iu.test(name)
  ))),
  stdio: ['ignore', 'ignore', 'pipe', 'pipe', 'pipe', 'ipc'],
})

let stderr = ''
let settled = false
const timer = setTimeout(() => finish(new Error('desktop plugin staged Host readiness timed out')), 30_000)
timer.unref()

function finish(error) {
  if (settled) return
  settled = true
  clearTimeout(timer)
  if (child.connected) child.send({ type: 'shutdown' })
  setTimeout(() => child.kill('SIGTERM'), 2_000).unref()
  if (error) {
    console.error(`${error.message}${stderr.trim() ? `: ${stderr.trim()}` : ''}`)
    process.exitCode = 1
  }
}

child.stderr.setEncoding('utf8')
child.stderr.on('data', chunk => { stderr += chunk })
child.on('message', message => {
  if (message?.type === 'ready' && message.protocolVersion === 3 && typeof message.dshVersion === 'string') {
    finish()
  } else {
    finish(new Error('desktop plugin staged Host returned an invalid readiness event'))
  }
})
child.on('error', error => finish(error))
child.on('exit', code => {
  if (!settled) finish(new Error(`desktop plugin staged Host exited before readiness (${String(code)})`))
})
