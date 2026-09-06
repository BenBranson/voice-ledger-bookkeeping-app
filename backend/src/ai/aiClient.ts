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
  /// Owner directive (2026-09-06): Voice Ledger's own in-app voice
  /// assistant moving off phrase-matching onto real tool-calling (see
  /// `routes/ai.ts`'s `tools` param) — populated only when the caller
  /// passed `tools` AND the model actually chose to call one; `undefined`
  /// for every other request, so every existing plain-text caller
  /// (every on-screen Ask AI panel) is completely unaffected.
  readonly toolCalls?: AIToolCall[] | undefined;
}

/** One function call the model chose to make, in response to a `tools`-
 * enabled request — see `AICompletionResult.toolCalls`. `arguments` is
 * whatever JSON shape the model produced for that tool's own schema;
 * the caller (never this file) is responsible for validating it against
 * the specific tool it named. */
export interface AIToolCall {
  readonly id?: string | undefined;
  readonly name: string;
  readonly arguments: Record<string, unknown>;
}

/**
 * One prior turn of the SAME voice conversation, replayed into the model's
 * message list so a follow-up ("why", "what should I do about it") isn't
 * answered from zero context. Added 2026-08-29 after researching a
 * different app's voice assistant (which the owner said felt sharper) —
 * that app replays its last ~6 exchanges into every call; this app's
 * voice engine previously sent a single isolated question/answer with no
 * memory of what was just discussed, which is the most likely reason a
 * follow-up could feel like it was "talking in circles." `content` here
 * is always something this app already said or the user already said —
 * never new authoritative data — so this doesn't touch CLAUDE.md rule 1's
 * boundary at all, only conversational continuity.
 */
export interface AIChatTurn {
  readonly role: "user" | "assistant";
  readonly content: string;
}

export interface AICompletionClient {
  /** `tools` — see `AICompletionResult.toolCalls`'s doc comment. Optional
   * and ignored by providers that don't implement function-calling for
   * this app's purposes (`OpenAIClient`, never used by the voice tool
   * loop); `OllamaClient` is the one real implementation. */
  complete(systemPrompt: string, userMessage: string, history?: AIChatTurn[], tools?: unknown[]): Promise<AICompletionResult>;
}
