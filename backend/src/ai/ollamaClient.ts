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
 * Ollama server with `gemma4:e4b` loaded, and reconfirmed (2026-08-30)
 * against `gemma4:12b`, the current default:
 * `{ model, message: { role, content }, done, ... }` — not the
 * OpenAI-shaped `{ choices: [{ message }] }`.
 *
 * `think: false` in the request body (2026-08-31): `gemma4:12b` is a
 * reasoning-capable model that, left to its own defaults, generates a
 * hidden `thinking` chain-of-thought BEFORE `content` on every single
 * request — confirmed live this was the actual cause of the slow
 * generation times previously blamed on the model/hardware being simply
 * slow (see the timeout comment below): a trivial "reply with OK" request
 * spent 39 output tokens and 2.4s on an invisible thinking trace nobody
 * ever saw, and a real report-format request that took 127s with
 * thinking on took 27s for a LONGER, more detailed report with thinking
 * off — real numbers, not an estimate. Setting `think: false` disables
 * that reasoning pass entirely; since this endpoint only ever narrates
 * numbers the app already computed (never asked to reason its way to an
 * answer — CLAUDE.md rule 1), there was never anything for the thinking
 * pass to usefully do here in the first place. `data.message.content` is
 * still the only field ever read below, unaffected either way.
 */

import type { AIChatTurn, AICompletionClient, AICompletionResult, AIToolCall } from "./aiClient.js";

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
   * user message so a follow-up isn't answered from zero context.
   *
   * `tools` (2026-09-06): Voice Ledger's own in-app voice assistant moving
   * off exact-phrase matching onto real function-calling — confirmed live
   * against this exact model (`gemma4:12b`) before this was wired in:
   * given a `tools` array, it correctly returns `message.tool_calls`
   * (empty `content`) rather than guessing at prose, and forwarding a
   * `role: "tool"` result back in a follow-up `history` turn produces a
   * correctly grounded final answer. Omitted entirely from the request
   * body when not provided (`undefined` inside `JSON.stringify` is
   * dropped, not sent as `null`), so every non-voice caller is unaffected. */
  /** Loads the model into memory without generating anything (empty prompt). */
  async warmUp(): Promise<void> {
    try {
      await fetch(`${this.baseUrl}/api/generate`, {
        method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ model: this.model, prompt: "", keep_alive: "30m" }),
        signal: AbortSignal.timeout(120_000)
      });
    } catch { /* best effort */ }
  }

  async complete(systemPrompt: string, userMessage: string, history: AIChatTurn[] = [], tools?: unknown[]): Promise<AICompletionResult> {
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
        // See this file's own doc comment — disables gemma4:12b's hidden
        // reasoning pass, which was the actual dominant cost in every
        // request, not model size or hardware. Harmless on a model that
        // doesn't support "thinking" at all (e.g. gemma4:e4b): Ollama
        // simply ignores the field rather than erroring.
        think: false,
        // Keep the 8 GB model resident between turns (default is 5 min, after
        // which the next spoken turn pays ~8 s to reload). Owner directive
        // 2026-09-30: speed matters, this Mac has the RAM.
        keep_alive: "30m",
        tools,
        options: {
          // Same deterministic-leaning reasoning as OpenAIClient's own
          // temperature: this explains an already-computed finding, it
          // doesn't draft creative copy.
          temperature: 0.2,
          // Ollama's default window is ~4k tokens on this hardware and it
          // silently drops the START of a longer prompt — which is where
          // the tool definitions and system prompt live. 16k holds the
          // voice tool loop's full prompt (owner directive 2026-09-30: best
          // answers from gemma4:12b even if slower).
          num_ctx: 16384
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
      //
      // Re-benchmarked 2026-08-30 after switching the default to
      // gemma4:12b: ~7.7-9.8 tokens/sec, similar to e4b — but a real
      // "report"-format request (routes/ai.ts's REPORT_CLOSING) took 127s
      // for a modest 1240-token report in testing, uncomfortably close to
      // this 180s ceiling.
      //
      // Root-caused and fixed 2026-08-31: that slowness was never model
      // speed — it was the hidden `thinking` pass this request now
      // disables (see this file's top doc comment). The same report
      // request, same hardware, thinking off: 27s for a LONGER report.
      // 180s is now a very comfortable ceiling rather than a real risk;
      // left as-is since there's no live evidence it needs to move either
      // direction, not raised or lowered on a guess.
      signal: AbortSignal.timeout(180_000)
    });
    const latencyMs = Date.now() - startedAt;

    if (!response.ok) {
      // Same posture as OpenAIClient: never read/log the response body,
      // which can echo request content back.
      throw new OllamaApiError(`Ollama request failed (${response.status})`, response.status);
    }

    const data = (await response.json()) as {
      message?: {
        content?: string;
        tool_calls?: { id?: string; function: { name: string; arguments: Record<string, unknown> } }[];
      };
      model?: string;
    };
    const rawToolCalls = data.message?.tool_calls;
    const toolCalls: AIToolCall[] | undefined =
      rawToolCalls && rawToolCalls.length > 0
        ? rawToolCalls.map((call) => ({ id: call.id, name: call.function.name, arguments: call.function.arguments }))
        : undefined;

    const text = data.message?.content;
    // A tool-call response legitimately has empty `content` — confirmed
    // live (see this method's own doc comment) — so only requests that
    // did NOT produce a tool call are held to the "must have real text"
    // rule every other caller of this client still depends on.
    if (!toolCalls && (typeof text !== "string" || text.trim() === "")) {
      throw new OllamaApiError("Ollama response had no completion text", response.status);
    }

    return { text: text ?? "", model: data.model ?? this.model, latencyMs, toolCalls };
  }
}
