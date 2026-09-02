export const name = 'github-copilot'
export const strictJsonOAuthGrantMarkers = [
  'normalizeGitHubCopilotOAuthCredential',
  'Reflect.get(credential, "type")',
  'Number.isFinite(expires)',
  'payload: normalizeGitHubCopilotOAuthCredential(credential)',
]

export const perModelApiRouteMarkers = [
  '[model.id, model.api]',
  'const effectiveApi = selectedApi ?? routeApi;',
]

export const existingGrantRouteSelfHealingMarkers = [
  'ensureGitHubCopilotProviderProfile(ctx)',
  'function sameProviderProfile(current, expected)',
  'normalizeGitHubCopilotOAuthCredential(record.payload)',
]
