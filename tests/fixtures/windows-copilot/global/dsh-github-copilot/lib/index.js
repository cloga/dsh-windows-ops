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

export const authorizationBootstrapMarkers = [
  'ctx.get("authorization", false)',
  'ctx.plugin(AuthorizationService)',
  'ctx.inject(integrationInject',
]

export const sharedCredentialMarkers = [
  'llm-pi-ai/github-copilot',
  'models.getAuth(catalogModel)',
]

export const directHostedSearchMarkers = [
  'Openai-Intent',
  'const RESPONSES_PROBE_ROUNDS = 2;',
  'github-copilot-hosted',
  'api.individual.githubcopilot.com',
]
