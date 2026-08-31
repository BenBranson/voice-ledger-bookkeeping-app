import { describe, it, expect, vi, afterEach } from "vitest";
import { OllamaClient, OllamaApiError } from "../src/ai/ollamaClient.js";

describe("OllamaClient", () => {
  afterEach(() => {
    vi.restoreAllMocks();
  });

  it("returns the completion text and model from a real-shaped success response (confirmed live 2026-08-29 against gemma4:e4b)", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue({
        ok: true,
        status: 200,
        json: async () => ({
          model: "gemma4:e4b",
          message: { role: "assistant", content: "This finding means the same expense may have posted twice." },
          done: true
        })
      })
    );
    const client = new OllamaClient("http://localhost:11434", "gemma4:e4b");
    const result = await client.complete("system prompt", "user message");
    expect(result.text).toBe("This finding means the same expense may have posted twice.");
    expect(result.model).toBe("gemma4:e4b");
    expect(result.latencyMs).toBeGreaterThanOrEqual(0);
  });

  it("posts to {baseUrl}/api/chat with no API key, stream:false, and the configured model", async () => {
    const fetchMock = vi.fn().mockResolvedValue({
      ok: true,
      status: 200,
      json: async () => ({ model: "gemma4:e4b", message: { content: "ok" } })
    });
    vi.stubGlobal("fetch", fetchMock);
    const client = new OllamaClient("http://localhost:11434", "gemma4:e4b");
    await client.complete("sys", "user");
    const [url, requestInit] = fetchMock.mock.calls[0]!;
    expect(url).toBe("http://localhost:11434/api/chat");
    expect(requestInit.headers.Authorization).toBeUndefined();
    const body = JSON.parse(requestInit.body);
    expect(body.model).toBe("gemma4:e4b");
    expect(body.stream).toBe(false);
    expect(body.messages).toEqual([
      { role: "system", content: "sys" },
      { role: "user", content: "user" }
    ]);
  });

  it("sends think:false — live-verified 2026-08-31: gemma4:12b's hidden reasoning pass, not model speed, was the actual cause of report-generation requests approaching the timeout", async () => {
    const fetchMock = vi.fn().mockResolvedValue({
      ok: true,
      status: 200,
      json: async () => ({ model: "gemma4:12b", message: { content: "ok" } })
    });
    vi.stubGlobal("fetch", fetchMock);
    const client = new OllamaClient("http://localhost:11434", "gemma4:12b");
    await client.complete("sys", "user");
    const [, requestInit] = fetchMock.mock.calls[0]!;
    const body = JSON.parse(requestInit.body);
    expect(body.think).toBe(false);
  });

  it("throws OllamaApiError on a non-2xx response", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue({ ok: false, status: 500 }));
    const client = new OllamaClient("http://localhost:11434", "gemma4:e4b");
    await expect(client.complete("sys", "user")).rejects.toThrow(OllamaApiError);
  });

  it("throws OllamaApiError when the response has no completion text", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue({ ok: true, status: 200, json: async () => ({ message: {} }) })
    );
    const client = new OllamaClient("http://localhost:11434", "gemma4:e4b");
    await expect(client.complete("sys", "user")).rejects.toThrow(OllamaApiError);
  });
});
