import { z } from "zod";

const GITHUB_COPILOT_AUTHORIZATION_VIEW_TYPE_SYMBOL =
  "dsh-github-copilot#GitHubCopilotAuthorizationView";
const GitHubCopilotAuthorizationViewSchema = z.object({}).strict();
const result = {
  mode: "strict",
  typeSymbol: GITHUB_COPILOT_AUTHORIZATION_VIEW_TYPE_SYMBOL,
  schema: GitHubCopilotAuthorizationViewSchema,
};

export { GITHUB_COPILOT_AUTHORIZATION_VIEW_TYPE_SYMBOL, GitHubCopilotAuthorizationViewSchema, result };
