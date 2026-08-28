import { describe, it, expect, vi, afterEach } from "vitest";
import { OpenAIClient, OpenAIApiError } from "../src/ai/openaiClient.js";

describe("OpenAIClient", () => {
  afterEach(() => {
    vi.restoreAllMocks();
  });

  it("returns the completion text and model from a real-shaped success response", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue({
        ok: true,
        status: 200,
        json: async () => ({
          model: "gpt-4o-mini-2024-07-18",
          choices: [{ message: { content: "This finding means the same expense may have posted twice." } }]
        })
      })
    );
    const client = new OpenAIClient("test-key", "gpt-4o-mini");
    const result = await client.complete("system prompt", "user message");
    expect(result.text).toBe("This finding means the same expense may have posted twice.");
    expect(result.model).toBe("gpt-4o-mini-2024-07-18");
    expect(result.latencyMs).toBeGreaterThanOrEqual(0);
  });

  it("sends the API key as a Bearer header and the configured model", async () => {
    const fetchMock = vi.fn().mockResolvedValue({
      ok: true,
      status: 200,
      json: async () => ({ model: "gpt-4o-mini", choices: [{ message: { content: "ok" } }] })
    });
    vi.stubGlobal("fetch", fetchMock);
    const client = new OpenAIClient("secret-key-value", "gpt-4o-mini");
    await client.complete("sys", "user");
    const [, requestInit] = fetchMock.mock.calls[0]!;
    expect(requestInit.headers.Authorization).toBe("Bearer secret-key-value");
    const body = JSON.parse(requestInit.body);
    expect(body.model).toBe("gpt-4o-mini");
    expect(body.messages).toEqual([
      { role: "system", content: "sys" },
      { role: "user", content: "user" }
    ]);
  });

  it("throws OpenAIApiError on a non-2xx response, without reading the body", async () => {
    const textSpy = vi.fn();
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue({ ok: false, status: 401, text: textSpy })
    );
    const client = new OpenAIClient("bad-key", "gpt-4o-mini");
    await expect(client.complete("sys", "user")).rejects.toThrow(OpenAIApiError);
    expect(textSpy).not.toHaveBeenCalled();
  });

  it("throws OpenAIApiError when the response has no completion text", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue({ ok: true, status: 200, json: async () => ({ choices: [] }) })
    );
    const client = new OpenAIClient("test-key", "gpt-4o-mini");
    await expect(client.complete("sys", "user")).rejects.toThrow(OpenAIApiError);
  });

  it("OpenAIApiError carries the real HTTP status", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue({ ok: false, status: 429, text: vi.fn() }));
    const client = new OpenAIClient("test-key", "gpt-4o-mini");
    try {
      await client.complete("sys", "user");
      expect.unreachable("expected complete() to throw");
    } catch (error) {
      expect(error).toBeInstanceOf(OpenAIApiError);
      expect((error as OpenAIApiError).httpStatus).toBe(429);
    }
  });
});
