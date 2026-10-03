import { describe, it, expect, beforeEach, vi } from "vitest";
import { resolveOAuthEndpoints, clearOAuthDiscoveryCache, FALLBACK_OAUTH_ENDPOINTS } from "../src/auth/oauth.js";
import { intuitTid } from "../src/qbo/client.js";

// Intuit app assessment: endpoints come from Intuit's discovery document
// (Authorization Q5) and every QBO response's intuit_tid is logged (Error Q2).

const liveShape = {
  authorization_endpoint: "https://appcenter.intuit.com/connect/oauth2",
  token_endpoint: "https://oauth.platform.intuit.com/oauth2/v1/tokens/bearer",
  revocation_endpoint: "https://developer.api.intuit.com/v2/oauth2/tokens/revoke"
};

describe("OAuth discovery document", () => {
  beforeEach(() => clearOAuthDiscoveryCache());

  it("reads the endpoints from the environment's discovery document", async () => {
    const fetcher = vi.fn(async (_url: unknown) => new Response(JSON.stringify({ ...liveShape, token_endpoint: "https://oauth.platform.intuit.com/oauth2/v2/tokens/bearer" })));
    const endpoints = await resolveOAuthEndpoints("sandbox", fetcher as typeof fetch);
    expect(fetcher.mock.calls[0]?.[0]).toBe("https://developer.api.intuit.com/.well-known/openid_sandbox_configuration");
    expect(endpoints.tokenEndpoint).toBe("https://oauth.platform.intuit.com/oauth2/v2/tokens/bearer");
  });

  it("uses the production document for production", async () => {
    const fetcher = vi.fn(async (_url: unknown) => new Response(JSON.stringify(liveShape)));
    await resolveOAuthEndpoints("production", fetcher as typeof fetch);
    expect(fetcher.mock.calls[0]?.[0]).toBe("https://developer.api.intuit.com/.well-known/openid_configuration");
  });

  it("caches for 24 hours, then fetches again", async () => {
    const fetcher = vi.fn(async () => new Response(JSON.stringify(liveShape)));
    await resolveOAuthEndpoints("sandbox", fetcher as typeof fetch, 0);
    await resolveOAuthEndpoints("sandbox", fetcher as typeof fetch, 60_000);
    expect(fetcher).toHaveBeenCalledTimes(1);
    await resolveOAuthEndpoints("sandbox", fetcher as typeof fetch, 24 * 60 * 60 * 1000 + 1);
    expect(fetcher).toHaveBeenCalledTimes(2);
  });

  it("falls back to the documented endpoints when Intuit is unreachable", async () => {
    const fetcher = vi.fn(async () => { throw new Error("offline"); });
    expect(await resolveOAuthEndpoints("sandbox", fetcher as typeof fetch)).toEqual(FALLBACK_OAUTH_ENDPOINTS);
  });

  it("refuses an endpoint that is not https on an intuit.com host", async () => {
    for (const bad of ["http://oauth.platform.intuit.com/x", "https://evil.example.com/token", "https://intuit.com.evil.net/t"]) {
      clearOAuthDiscoveryCache();
      const fetcher = vi.fn(async () => new Response(JSON.stringify({ ...liveShape, token_endpoint: bad })));
      expect(await resolveOAuthEndpoints("sandbox", fetcher as typeof fetch)).toEqual(FALLBACK_OAUTH_ENDPOINTS);
    }
  });

  it("does not cache a fallback, so the next call tries Intuit again", async () => {
    const failing = vi.fn(async () => new Response("", { status: 503 }));
    await resolveOAuthEndpoints("sandbox", failing as typeof fetch);
    const working = vi.fn(async () => new Response(JSON.stringify(liveShape)));
    await resolveOAuthEndpoints("sandbox", working as typeof fetch);
    expect(working).toHaveBeenCalledTimes(1);
  });
});

describe("intuit_tid capture", () => {
  it("reads the header when Intuit sends it, and is absent otherwise", () => {
    expect(intuitTid(new Response("{}", { headers: { intuit_tid: "1-66fe1a2b-3c4d5e6f7a8b9c0d1e2f3a4b" } }))).toBe("1-66fe1a2b-3c4d5e6f7a8b9c0d1e2f3a4b");
    expect(intuitTid(new Response("{}"))).toBeUndefined();
  });
});
