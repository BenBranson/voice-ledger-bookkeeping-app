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
  complete(systemPrompt: string, userMessage: string, history?: AIChatTurn[]): Promise<AICompletionResult>;
}
