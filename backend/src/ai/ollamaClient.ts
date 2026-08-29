/**
 * Local inference via Ollama (http://localhost:11434 by default) —
 * mirrors `OpenAIClient`'s shape exactly (`AICompletionClient`), so
 * `routes/ai.ts` doesn't know or care which provider it's talking to.
 * No API key: this is the owner's own machine talking to its own local
 * Ollama server, not a hosted API — genuinely free per request, which is
 * the whole reason for this provider existing (2026-08-29: "I want to
 * mitigate AI usage since it costs money").
 *
 * Response shape confirmed live (2026-08-29) against a real running
 * Ollama server with `gemma4:e4b` loaded:
 * `{ model, message: { role, content }, done, ... }` — not the
 * OpenAI-shaped `{ choices: [{ message }] }`.
 */

import type { AIChatTurn, AICompletionClient, AICompletionResult } from "./aiClient.js";

export class OllamaApiError extends Error {
  constructor(
    message: string,
    readonly httpStatus: number
  ) {
    super(message);
    this.name = "OllamaApiError";
  }
}

export class OllamaClient implements AICompletionClient {
  constructor(
    private readonly baseUrl: string,
    private readonly model: string
  ) {}

  /** `history` (see `AIChatTurn`'s doc comment): prior turns of the SAME
   * voice conversation, replayed between the system prompt and the final
   * user message so a follow-up isn't answered from zero context. */
  async complete(systemPrompt: string, userMessage: string, history: AIChatTurn[] = []): Promise<AICompletionResult> {
    const startedAt = Date.now();
    const response = await fetch(`${this.baseUrl}/api/chat`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        model: this.model,
        messages: [
          { role: "system", content: systemPrompt },
          ...history,
          { role: "user", content: userMessage }
        ],
        stream: false,
        options: {
          // Same deterministic-leaning reasoning as OpenAIClient's own
          // temperature: this explains an already-computed finding, it
          // doesn't draft creative copy.
          temperature: 0.2
        }
      }),
      // Local inference on consumer hardware is genuinely slower than a
      // hosted API — a longer bound than OpenAIClient's 30s, chosen for
      // that reason, not copied from it. Raised from 90s to 180s
      // (2026-08-29): live-benchmarked on this machine at roughly
      // 6 tokens/sec for gemma4:e4b, and the new "report" format
      // (routes/ai.ts) deliberately asks for a genuinely longer,
      // multi-paragraph answer — a real report-length response could
      // exceed 90s on its own without ever being stuck.
      signal: AbortSignal.timeout(180_000)
    });
    const latencyMs = Date.now() - startedAt;

    if (!response.ok) {
      // Same posture as OpenAIClient: never read/log the response body,
      // which can echo request content back.
      throw new OllamaApiError(`Ollama request failed (${response.status})`, response.status);
    }

    const data = (await response.json()) as {
      message?: { content?: string };
      model?: string;
    };
    const text = data.message?.content;
    if (typeof text !== "string" || text.trim() === "") {
      throw new OllamaApiError("Ollama response had no completion text", response.status);
    }

    return { text, model: data.model ?? this.model, latencyMs };
  }
}
