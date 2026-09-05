import { existsSync, readFileSync } from 'node:fs'
import { pathToFileURL } from 'node:url'
import { dirname, join, resolve } from 'node:path'

function fail(message) {
  process.stdout.write(JSON.stringify({ status: 'failed', reason: message }) + '\n')
  process.exitCode = 2
}

const packageRoot = process.argv[2] ? resolve(process.argv[2]) : ''
if (!packageRoot) {
  fail('missing-package-root')
} else {
  const packageEntry = (name) => {
    const relative = [...name.split('/'), 'lib', 'index.js']
    const candidates = [
      join(packageRoot, 'node_modules', ...relative),
      join(dirname(dirname(packageRoot)), ...relative),
    ]
    return candidates.find(candidate => existsSync(candidate)) ?? candidates[0]
  }
  const sandboxEntry = packageEntry('@deepseek-ai/dsh-sandbox')
  const toolEntries = [
    {
      name: 'bash',
      command: 'true',
      path: packageEntry('@deepseek-ai/dsh-tool-bash'),
    },
    {
      name: 'pwsh',
      command: '$null',
      path: packageEntry('@deepseek-ai/dsh-tool-pwsh'),
    },
  ]
  if (!existsSync(sandboxEntry) || toolEntries.some(tool => !existsSync(tool.path))) {
    fail('sandbox-contract-files-missing')
  } else if (toolEntries.some(tool => !/\bapproveEscalation\s*\(/.test(readFileSync(tool.path, 'utf8')))) {
    fail('shell-tools-do-not-delegate-to-shared-escalation')
  } else {
    try {
      const toolEvidence = []
      for (const tool of toolEntries) {
        const module = await import(pathToFileURL(tool.path).href)
        if (typeof module.apply !== 'function') throw new Error(`${tool.name}-tool-apply-export-missing`)
        let registered
        let approvals = 0
        let executionRequest
        const policy = {
          resolve: () => ({
            mode: 'danger-full-access',
            workspaceRoot: packageRoot,
          }),
        }
        const context = {
          get: (name) => {
            if (name === 'sandboxPolicy') return policy
            if (name === 'approval') {
              return {
                request: async () => {
                  approvals += 1
                  return 'allowed-once'
                },
              }
            }
            return undefined
          },
          shell: {
            sandboxMode: 'danger-full-access',
            resolve: request => request,
            run: async (request) => {
              executionRequest = request
              return {
                exitCode: 0,
                signal: null,
                timedOut: false,
                aborted: false,
                timeoutMs: 1000,
                stdout: { text: '', truncated: false },
                stderr: { text: '', truncated: false },
              }
            },
          },
          shellEnv: { collect: () => ({}) },
          systemPrompt: {
            getSectionOrder: () => 0,
            section: () => {},
          },
          tools: { register: value => { registered = value } },
        }
        await module.apply(context)
        if (!registered || registered.name !== tool.name || typeof registered.execute !== 'function') {
          throw new Error(`${tool.name}-tool-registration-missing`)
        }
        if (registered.parameters?.sandbox_permissions?.required === true
          || registered.parameters?.justification?.required === true) {
          throw new Error(`${tool.name}-tool-escalation-fields-required`)
        }
        await registered.execute(
          { command: tool.command, description: `${tool.name} no-escalation probe` },
          { callId: `ops-probe-${tool.name}`, signal: new AbortController().signal },
        )
        if (approvals !== 0) throw new Error(`${tool.name}-tool-requested-approval-${approvals}`)
        if (executionRequest?.sandboxPolicy?.mode !== 'danger-full-access') {
          throw new Error(`${tool.name}-tool-lowered-effective-policy`)
        }
        toolEvidence.push({ name: tool.name, omittedEscalationFields: true, approvalCalls: approvals })
      }

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
      const expectNonWideningRejected = async (requestedMode, label) => {
        try {
          await approveEscalation({
            requestedMode,
            justification: `${label} probe`,
            effectiveMode: 'danger-full-access',
            subject: 'command',
          }, ingredients)
        } catch (error) {
          if (error instanceof Error && error.message.includes('not strictly wider')) return
          throw error
        }
        throw new Error(`${label}-request-was-not-rejected`)
      }
      await expectNonWideningRejected('danger-full-access', 'same-mode')
      await expectNonWideningRejected('workspace-write', 'narrower-mode')
      if (approvals !== 0) throw new Error(`non-widening-requested-approval-${approvals}`)

      const wider = await approveEscalation({
        requestedMode: 'danger-full-access',
        justification: 'wider mode probe',
        effectiveMode: 'workspace-write',
        subject: 'command',
      }, ingredients)

      if (wider !== 'danger-full-access') throw new Error('wider-request-not-granted')
      if (approvals !== 1) throw new Error(`unexpected-approval-count-${approvals}`)

      process.stdout.write(JSON.stringify({
        status: 'passed',
        capability: 'sandbox-same-and-narrower-no-op',
        sameMode: 'omitted-no-op-explicit-rejected',
        narrowerMode: 'omitted-no-op-explicit-rejected',
        widerMode: 'approved-once',
        effectiveMode: 'danger-full-access',
        sameAndNarrowerApprovalCalls: 0,
        widerApprovalCalls: 1,
        tools: toolEvidence,
      }) + '\n')
    } catch (error) {
      fail(error instanceof Error ? error.message : 'sandbox-contract-failed')
    }
  }
}
