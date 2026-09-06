/**
 * The ONLY place in this backend that calls OpenAI. Mirrors `qbo/client.ts`'s
 * shape (one client class, one method, callers never touch `fetch`
 * directly) so the same "one place to change" property holds for the AI
 * provider that already holds for QBO.
 *
 * CLAUDE.md rule 1 ("Code computes and classifies. Claude explains.") governs
 * the system prompt this is always called with — see `routes/ai.ts`'s
 * `SYSTEM_PROMPT` — not this file, which is deliberately just plumbing with
 * no opinion about what the model is allowed to say.
 */

import type { AIChatTurn, AICompletionClient, AICompletionResult } from "./aiClient.js";

export class OpenAIApiError extends Error {
  constructor(
    message: string,
    readonly httpStatus: number
  ) {
    super(message);
    this.name = "OpenAIApiError";
  }
}

/** @deprecated use `AICompletionResult` from `./aiClient.js` — kept as an alias so nothing importing this name breaks. */
export type OpenAICompletionResult = AICompletionResult;

export class OpenAIClient implements AICompletionClient {
  constructor(
    private readonly apiKey: string,
    private readonly model: string
  ) {}

  /**
   * A single non-streaming chat completion. `history` (added 2026-08-29 —
   * see `AIChatTurn`'s doc comment) replays prior turns of the SAME voice
   * conversation between `systemPrompt` and the final `userMessage`, so a
   * follow-up question isn't answered from zero context. Callers own
   * composing `userMessage`/`history` from whatever context (a finding's
   * fields, a question, recent transcript) needs to be included.
   */
  /** `tools` is accepted only to satisfy `AICompletionClient`'s shared
   * signature and is deliberately ignored — the voice tool-calling loop
   * only ever targets the primary/Ollama tier (see `routes/ai.ts`), never
   * this secondary/OpenAI client. */
  async complete(systemPrompt: string, userMessage: string, history: AIChatTurn[] = [], _tools?: unknown[]): Promise<OpenAICompletionResult> {
    const startedAt = Date.now();
    const response = await fetch("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${this.apiKey}`,
        "Content-Type": "application/json"
      },
      body: JSON.stringify({
        model: this.model,
        messages: [
          { role: "system", content: systemPrompt },
          ...history,
          { role: "user", content: userMessage }
        ],
        // Deterministic-leaning, not creative — this is explaining a
        // computed finding, not drafting marketing copy.
        temperature: 0.2,
        // Owner directive (2026-08-29): the two report buttons now ask for
        // a genuinely fuller, multi-paragraph write-up ("report" format in
        // routes/ai.ts) — 700 was sized for the original concise-only
        // behavior and could truncate a real 5-section report. Raised with
        // headroom; the concise/voice/quick-answer prompts still stop
        // themselves well short of even the old cap, per their own
        // brevity instruction, so this doesn't change their behavior.
        max_tokens: 1100
      }),
      // OpenAI can occasionally hang; a bookkeeper waiting on this panel
      // deserves a bounded wait, not an indefinite spinner.
      signal: AbortSignal.timeout(30_000)
    });
    const latencyMs = Date.now() - startedAt;

    if (!response.ok) {
      // The response body is deliberately never read or included here — it
      // can contain the request's own content reflected back, and this
      // backend's logger forbids prompt/completion content in log lines
      // (logging/logger.ts's LogFields doc comment). The HTTP status alone
      // is enough to classify and log the failure.
      throw new OpenAIApiError(`OpenAI request failed (${response.status})`, response.status);
    }

    const data = (await response.json()) as {
      choices?: { message?: { content?: string } }[];
      model?: string;
    };
    const text = data.choices?.[0]?.message?.content;
    if (typeof text !== "string" || text.trim() === "") {
      throw new OpenAIApiError("OpenAI response had no completion text", response.status);
    }

    return { text, model: data.model ?? this.model, latencyMs };
  }
}
