export const name = 'github-copilot'
export const strictJsonOAuthGrantMarkers = [
  'normalizeGitHubCopilotOAuthCredential',
  'Reflect.get(credential, "type")',
  'Number.isFinite(expires)',
  'payload: normalizeGitHubCopilotOAuthCredential(credential)',
]
