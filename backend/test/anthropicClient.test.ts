import { describe, it, expect, vi, afterEach, beforeEach } from "vitest";

const createMock = vi.fn();

vi.mock("@anthropic-ai/sdk", () => {
  class MockAnthropic {
    messages = { create: createMock };
  }
  class APIError extends Error {
    status?: number;
    constructor(status: number | undefined, message: string) {
      super(message);
      this.status = status;
    }
  }
  return { default: Object.assign(MockAnthropic, { APIError }) };
});

const { AnthropicClient, AnthropicApiError } = await import("../src/ai/anthropicClient.js");

describe("AnthropicClient", () => {
  beforeEach(() => {
    createMock.mockReset();
  });
  afterEach(() => {
    vi.restoreAllMocks();
  });

  it("returns the completion text and model from a plain text response", async () => {
    createMock.mockResolvedValue({
      model: "claude-haiku-4-5",
      content: [{ type: "text", text: "This finding means the same expense may have posted twice." }]
    });
    const client = new AnthropicClient("test-key", "claude-haiku-4-5");
    const result = await client.complete("system prompt", "user message");
    expect(result.text).toBe("This finding means the same expense may have posted twice.");
    expect(result.model).toBe("claude-haiku-4-5");
    expect(result.toolCalls).toBeUndefined();
  });

  it("passes systemPrompt/history/userMessage through as system + messages", async () => {
    createMock.mockResolvedValue({ model: "claude-haiku-4-5", content: [{ type: "text", text: "ok" }] });
    const client = new AnthropicClient("test-key", "claude-haiku-4-5");
    await client.complete("sys", "user", [{ role: "assistant", content: "prior reply" }]);
    const params = createMock.mock.calls[0]![0];
    expect(params.system).toBe("sys");
    expect(params.messages).toEqual([
      { role: "assistant", content: "prior reply" },
      { role: "user", content: "user" }
    ]);
    expect(params.tools).toBeUndefined();
  });

  it("converts this app's OpenAI-shaped tool definitions into Claude's {name, description, input_schema} shape", async () => {
    createMock.mockResolvedValue({ model: "claude-haiku-4-5", content: [{ type: "text", text: "ok" }] });
    const client = new AnthropicClient("test-key", "claude-haiku-4-5");
    await client.complete("sys", "user", [], [
      { type: "function", function: { name: "navigate", description: "Go to a page.", parameters: { type: "object", properties: {} } } }
    ]);
    const params = createMock.mock.calls[0]![0];
    expect(params.tools).toEqual([{ name: "navigate", description: "Go to a page.", input_schema: { type: "object", properties: {} } }]);
  });

  it("converts a tool_use content block into an AIToolCall", async () => {
    createMock.mockResolvedValue({
      model: "claude-haiku-4-5",
      content: [{ type: "tool_use", id: "call_1", name: "navigate", input: { page: "findingsList" } }]
    });
    const client = new AnthropicClient("test-key", "claude-haiku-4-5");
    const result = await client.complete("sys", "user", [], [{ type: "function", function: { name: "navigate" } }]);
    expect(result.text).toBe("");
    expect(result.toolCalls).toEqual([{ id: "call_1", name: "navigate", arguments: { page: "findingsList" } }]);
  });

  it("throws AnthropicApiError on an SDK APIError", async () => {
    const Anthropic = (await import("@anthropic-ai/sdk")).default as unknown as { APIError: new (status: number, message: string) => Error };
    createMock.mockRejectedValue(new Anthropic.APIError(500, "server error"));
    const client = new AnthropicClient("test-key", "claude-haiku-4-5");
    await expect(client.complete("sys", "user")).rejects.toThrow(AnthropicApiError);
  });

  it("throws AnthropicApiError when the response has no text and no tool calls", async () => {
    createMock.mockResolvedValue({ model: "claude-haiku-4-5", content: [] });
    const client = new AnthropicClient("test-key", "claude-haiku-4-5");
    await expect(client.complete("sys", "user")).rejects.toThrow(AnthropicApiError);
  });
});
