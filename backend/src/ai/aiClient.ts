/**
 * The shape every AI provider client returns, and the interface
 * `routes/ai.ts` depends on — it never imports `OpenAIClient`/`OllamaClient`
 * by name for typing purposes, only for construction, so adding a third
 * provider later means writing one more class with this shape, not
 * touching the route.
 */

export interface AICompletionResult {
  readonly text: string;
  readonly model: string;
  readonly latencyMs: number;
}

export interface AICompletionClient {
  complete(systemPrompt: string, userMessage: string): Promise<AICompletionResult>;
}
