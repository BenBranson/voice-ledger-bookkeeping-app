import { describe, expect, it, vi } from "vitest";
import { QBOClient } from "../src/qbo/client.js";
import type { TokenStore } from "../src/auth/tokenStore.js";
import type { QBOCredentials } from "../src/config.js";

const credentials: QBOCredentials = { environment: "sandbox", clientId: "test", clientSecret: "test", redirectUri: "https://example.test", minorVersion: 75 };
const tokens = { getCachedAccessToken: () => "test-access" } as unknown as TokenStore;

describe("QBO request liveness", () => {
  it("times out stalled writes without retrying and releases all realm slots", async () => {
    const fetcher = vi.fn((_url: unknown, init?: RequestInit) => new Promise<Response>((_resolve, reject) => {
      const signal = init!.signal!;
      const abort = () => reject(signal.reason);
      if (signal.aborted) abort();
      else signal.addEventListener("abort", abort, { once: true });
    }));
    const client = new QBOClient(credentials, tokens, fetcher as typeof fetch, async () => {}, 20);
    const results = await Promise.allSettled(Array.from({ length: 11 }, () => client.post("realm", "purchase", {})));
    expect(results.every((result) => result.status === "rejected")).toBe(true);
    expect(fetcher).toHaveBeenCalledTimes(11);
    fetcher.mockImplementationOnce(async () => new Response('{"ok":true}'));
    expect(await client.get("realm", "query")).toEqual({ ok: true });
  });

  it("disposes retry bodies and caps server-specified retry delays", async () => {
    let canceled = false;
    const body = new ReadableStream({ cancel() { canceled = true; } });
    const fetcher = vi.fn()
      .mockResolvedValueOnce(new Response(body, { status: 429, headers: { "retry-after": "999999" } }))
      .mockResolvedValueOnce(new Response('{"ok":true}'));
    const sleep = vi.fn(async (_ms: number) => {});
    const client = new QBOClient(credentials, tokens, fetcher as typeof fetch, sleep);
    expect(await client.get("realm", "query")).toEqual({ ok: true });
    expect(canceled).toBe(true);
    expect(sleep).toHaveBeenCalledWith(30_000);
  });
});
