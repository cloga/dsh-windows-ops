export const name = 'github-copilot'
export const strictJsonOAuthGrantMarkers = [
  'normalizeGitHubCopilotOAuthCredential',
  'Reflect.get(credential, "type")',
  'Number.isFinite(expires)',
  'payload: normalizeGitHubCopilotOAuthCredential(credential)',
]

export const perModelApiRouteMarkers = [
  'routeFacts(modelId)',
  'const snapshot = source.readSnapshot();',
  'api: descriptor.api',
  'baseURL: proof.baseURL',
]

export const existingGrantRouteSelfHealingMarkers = [
  'ensureGitHubCopilotProviderProfile(ctx)',
  'validateGrant(record)',
  'current !== void 0 && providerSupportsStrictMode(current) !== false',
  'async function repairGitHubCopilotProviderProfile(ctx)',
  'normalizeGitHubCopilotOAuthCredential(record.payload)',
]

export const authorizationBootstrapMarkers = [
  'ctx.get("authorization", false)',
  'ctx.plugin(AuthorizationService)',
  'ctx.inject(integrationInject',
]

export const sharedCredentialMarkers = [
  'llm-pi-ai/github-copilot',
  'models.getAuth("github-copilot")',
  'createGitHubCopilotTokenResolver(ctx, async () =>',
]

export const directHostedSearchMarkers = [
  'resolveRequestAuth(candidate.model, candidateSignals.get(candidate))',
  'COPILOT_MANAGED_SEARCH_METADATA_CHANGED',
  'const RESPONSES_PROBE_ROUNDS = 2;',
  'github-copilot-hosted',
  'api.individual.githubcopilot.com',
]

export const toolSchemaMarkers = [
  'const ESCALATION_FIELDS',
  'assembly.variables.provider !== "github-copilot" && !(ownedPreview && assembly.variables.provider === "github-copilot-preview")',
  'isPluginPreviewProvider(ctx, assembled.variables.provider ?? "")',
  'installCopilotToolSchemaCompatibility(ctx)',
]
