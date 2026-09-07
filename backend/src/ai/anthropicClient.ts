/**
 * The ONLY place in this backend that calls the Claude API. Mirrors
 * `OllamaClient`/`OpenAIClient`'s shape exactly (`AICompletionClient`), so
 * `routes/ai.ts` doesn't know or care which provider it's talking to.
 *
 * Owner directive (2026-09-07): "connect Claude API... for the tool loop" —
 * added as a selectable model override for Voice Ledger's own voice
 * assistant (`VoiceToolLoop.swift`), alongside the existing free/local
 * `gemma4:12b` default. Requires its own `ANTHROPIC_API_KEY` — CLAUDE.md
 * rule 3 ("no secrets in the desktop binary") applies here exactly as it
 * does to the OpenAI key: the key lives only in this process, and the
 * desktop client only ever calls `/realms/:realmId/ask-ai` with a model
 * NAME, never the key itself.
 *
 * Tool definitions arrive from `VoiceToolDefinitions.swift` in this app's
 * existing OpenAI-shaped form (`{type: "function", function: {name,
 * description, parameters}}`) — the same shape `OllamaClient` already
 * accepts as-is, since Ollama's own tool-calling API is OpenAI-shaped.
 * The Claude Messages API's tool shape is different (`{name, description,
 * input_schema}`, no wrapper) — `toAnthropicTools` below does that one
 * conversion so `VoiceToolDefinitions.swift` never needs to know or care
 * which provider is actually running.
 */

import Anthropic from "@anthropic-ai/sdk";
import type { AIChatTurn, AICompletionClient, AICompletionResult, AIToolCall } from "./aiClient.js";

export class AnthropicApiError extends Error {
  constructor(
    message: string,
    readonly httpStatus: number
  ) {
    super(message);
    this.name = "AnthropicApiError";
  }
}

interface OpenAIShapedTool {
  readonly type?: string;
  readonly function?: {
    readonly name: string;
    readonly description?: string;
    readonly parameters?: Record<string, unknown>;
  };
}

/** Converts this app's existing OpenAI-shaped tool definitions into
 * Claude's `{name, description, input_schema}` shape. Passes through
 * unrecognized shapes as-is (defensive — `routes/ai.ts` already validates
 * `tools` is an array before this is ever called; this is not a second
 * validation layer, just a shape adapter). */
function toAnthropicTools(tools: unknown[] | undefined): Anthropic.Tool[] | undefined {
  if (!tools || tools.length === 0) return undefined;
  return tools.map((raw) => {
    const tool = raw as OpenAIShapedTool;
    const fn = tool.function;
    // `exactOptionalPropertyTypes: true` treats an explicit `description:
    // undefined` as different from the key being absent — spread it in
    // only when a real description string exists, rather than always
    // assigning the key.
    return {
      name: fn?.name ?? "",
      ...(fn?.description !== undefined ? { description: fn.description } : {}),
      input_schema: (fn?.parameters as Anthropic.Tool.InputSchema | undefined) ?? { type: "object", properties: {} }
    };
  });
}

export class AnthropicClient implements AICompletionClient {
  private readonly client: Anthropic;

  constructor(
    apiKey: string,
    private readonly model: string
  ) {
    this.client = new Anthropic({ apiKey });
  }

  /** `history`/`tools` — see `AIChatTurn`/`AIToolCall`'s own doc comments
   * in `aiClient.ts`; identical contract to `OllamaClient.complete`. This
   * app never needs extended thinking here (CLAUDE.md rule 1: the model
   * only narrates numbers already computed, it never reasons its way to
   * one) — `thinking` is omitted entirely, which runs Haiku 4.5 without
   * it, the cheaper and faster path. */
  async complete(systemPrompt: string, userMessage: string, history: AIChatTurn[] = [], tools?: unknown[]): Promise<AICompletionResult> {
    const startedAt = Date.now();
    const anthropicTools = toAnthropicTools(tools);
    let response: Anthropic.Message;
    try {
      response = await this.client.messages.create(
        {
          model: this.model,
          max_tokens: 1024,
          system: systemPrompt,
          messages: [...history, { role: "user", content: userMessage }],
          // Same `exactOptionalPropertyTypes` reasoning as `toAnthropicTools`
          // above — omit the key entirely rather than assign `undefined`.
          ...(anthropicTools !== undefined ? { tools: anthropicTools } : {}),
          // Deterministic-leaning, not creative — same reasoning
          // `OpenAIClient`/`OllamaClient` already give for this setting:
          // this explains an already-computed finding, it doesn't draft
          // creative copy.
          temperature: 0.2
        },
        // Voice Ledger's own voice assistant is a spoken interaction —
        // same bounded-wait reasoning `OpenAIClient` already gives for its
        // 30s timeout, not copied blindly: a hosted API call, so held to
        // the shorter of the two timeouts in this file, not Ollama's
        // local-hardware-tolerant 180s.
        { timeout: 30_000 }
      );
    } catch (error) {
      if (error instanceof Anthropic.APIError) {
        // Same posture as OpenAIClient/OllamaClient: never read/log
        // request or response content, which can echo prompt/completion
        // text back — the HTTP status alone is enough to classify.
        throw new AnthropicApiError(`Anthropic request failed (${error.status ?? 0})`, error.status ?? 502);
      }
      throw error;
    }
    const latencyMs = Date.now() - startedAt;

    const textParts: string[] = [];
    const toolCalls: AIToolCall[] = [];
    for (const block of response.content) {
      if (block.type === "text") {
        textParts.push(block.text);
      } else if (block.type === "tool_use") {
        toolCalls.push({ id: block.id, name: block.name, arguments: block.input as Record<string, unknown> });
      }
    }
    const text = textParts.join("\n").trim();

    // A tool-call response legitimately has empty text — same rule
    // `OllamaClient` already applies for the identical reason.
    if (toolCalls.length === 0 && text === "") {
      throw new AnthropicApiError("Anthropic response had no completion text", 502);
    }

    return { text, model: response.model, latencyMs, toolCalls: toolCalls.length > 0 ? toolCalls : undefined };
  }
}
