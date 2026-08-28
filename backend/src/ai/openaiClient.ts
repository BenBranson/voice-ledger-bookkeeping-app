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

export class OpenAIApiError extends Error {
  constructor(
    message: string,
    readonly httpStatus: number
  ) {
    super(message);
    this.name = "OpenAIApiError";
  }
}

export interface OpenAICompletionResult {
  readonly text: string;
  readonly model: string;
  readonly latencyMs: number;
}

export class OpenAIClient {
  constructor(
    private readonly apiKey: string,
    private readonly model: string
  ) {}

  /**
   * A single non-streaming chat completion. No conversation history is
   * threaded through here — each call is independent, `systemPrompt` +
   * `userMessage` fully determine the request. Callers own composing
   * `userMessage` from whatever context (a finding's fields, a question)
   * needs to be included.
   */
  async complete(systemPrompt: string, userMessage: string): Promise<OpenAICompletionResult> {
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
          { role: "user", content: userMessage }
        ],
        // Deterministic-leaning, not creative — this is explaining a
        // computed finding, not drafting marketing copy.
        temperature: 0.2,
        max_tokens: 700
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
