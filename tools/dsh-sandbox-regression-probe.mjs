import { existsSync, readFileSync } from 'node:fs'
import { pathToFileURL } from 'node:url'
import { join, resolve } from 'node:path'

function fail(message) {
  process.stdout.write(JSON.stringify({ status: 'failed', reason: message }) + '\n')
  process.exitCode = 2
}

const packageRoot = process.argv[2] ? resolve(process.argv[2]) : ''
if (!packageRoot) {
  fail('missing-package-root')
} else {
  const sandboxEntry = join(packageRoot, 'node_modules', '@deepseek-ai', 'dsh-sandbox', 'lib', 'index.js')
  const toolEntries = [
    join(packageRoot, 'node_modules', '@deepseek-ai', 'dsh-tool-bash', 'lib', 'index.js'),
    join(packageRoot, 'node_modules', '@deepseek-ai', 'dsh-tool-pwsh', 'lib', 'index.js'),
  ]
  if (!existsSync(sandboxEntry) || toolEntries.some(path => !existsSync(path))) {
    fail('sandbox-contract-files-missing')
  } else if (toolEntries.some(path => !readFileSync(path, 'utf8').includes('approveEscalation'))) {
    fail('shell-tools-do-not-delegate-to-shared-escalation')
  } else {
    try {
      const { approveEscalation } = await import(pathToFileURL(sandboxEntry).href)
      if (typeof approveEscalation !== 'function') throw new Error('approveEscalation-export-missing')

      let approvals = 0
      const approver = {
        request: async () => {
          approvals += 1
          return 'allowed-once'
        },
      }
      const ingredients = { approver, agent: {}, callId: 'ops-probe', toolName: 'pwsh' }
      const same = await approveEscalation({
        requestedMode: 'danger-full-access',
        justification: 'same mode probe',
        effectiveMode: 'danger-full-access',
        subject: 'command',
      }, ingredients)
      const narrower = await approveEscalation({
        requestedMode: 'workspace-write',
        justification: 'narrower mode probe',
        effectiveMode: 'danger-full-access',
        subject: 'command',
      }, ingredients)
      const wider = await approveEscalation({
        requestedMode: 'danger-full-access',
        justification: 'wider mode probe',
        effectiveMode: 'workspace-write',
        subject: 'command',
      }, ingredients)

      if (same !== 'danger-full-access') throw new Error('same-mode-lowered-effective-policy')
      if (narrower !== 'danger-full-access') throw new Error('narrower-request-lowered-effective-policy')
      if (wider !== 'danger-full-access') throw new Error('wider-request-not-granted')
      if (approvals !== 1) throw new Error(`unexpected-approval-count-${approvals}`)

      process.stdout.write(JSON.stringify({
        status: 'passed',
        sameMode: 'no-op',
        narrowerMode: 'no-op',
        widerMode: 'approved-once',
        effectiveMode: 'danger-full-access',
      }) + '\n')
    } catch (error) {
      fail(error instanceof Error ? error.message : 'sandbox-contract-failed')
    }
  }
}
