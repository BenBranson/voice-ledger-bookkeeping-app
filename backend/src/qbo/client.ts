/**
 * The ONLY place in this backend that makes an HTTP request to QBO itself.
 * Everything in src/catalog/operations.ts calls through here — never
 * `fetch` directly — so token refresh, minor-version pinning, and rate-
 * limit backoff are guaranteed to apply uniformly.
 *
 * docs/phase-0/02_QBO_CAPABILITY_MATRIX.md §2.7: "Pin one minor version
 * app-wide, recorded in config, asserted in every request." Enforced here.
 */

import type { QBOCredentials } from "../config.js";
import type { TokenStore } from "../auth/tokenStore.js";
import { refreshAccessToken } from "../auth/oauth.js";
import { resolveApiBaseUrl } from "./environment.js";
import { logEvent } from "../logging/logger.js";

export class QBOApiError extends Error {
  constructor(
    message: string,
    readonly httpStatus: number,
    readonly realmId: string
  ) {
    super(message);
    this.name = "QBOApiError";
  }
}

const MAX_CONCURRENT_PER_REALM = 10;
const MAX_429_RETRIES = 4;
const BASE_BACKOFF_MS = 1000;

export class QBOClient {
  private readonly activeRequests = new Map<string, number>();
  private readonly waiting = new Map<string, Array<() => void>>();

  constructor(
    private readonly credentials: QBOCredentials,
    private readonly tokenStore: TokenStore,
    private readonly fetchImpl: typeof fetch = fetch,
    private readonly sleep: (ms: number) => Promise<void> = (ms) => new Promise((r) => setTimeout(r, ms)),
    private readonly requestTimeoutMs = 30_000
  ) {}

  /**
   * Returns a valid access token for `realmId`, refreshing via the stored
   * refresh token if the cached one is absent or near expiry.
   * §3.9: refresh is serialized per realm via `tokenStore.withRefreshLock`.
   */
  private async accessToken(realmId: string): Promise<string> {
    const cached = this.tokenStore.getCachedAccessToken(realmId);
    if (cached) return cached;

    return this.tokenStore.withRefreshLock(realmId, async () => {
      // Re-check inside the lock — another caller may have refreshed while
      // we were waiting for the lock.
      const stillCached = this.tokenStore.getCachedAccessToken(realmId);
      if (stillCached) return stillCached;

      const refreshToken = this.tokenStore.getRefreshToken(realmId);
      if (!refreshToken) {
        throw new QBOApiError(`No refresh token stored for realm ${realmId}. Reconnect via /oauth/authorize.`, 401, realmId);
      }
      const result = await refreshAccessToken(this.credentials, refreshToken, realmId);
      this.tokenStore.cacheAccessToken(realmId, result.accessToken, result.expiresInSeconds);
      // Intuit rotates the refresh token on every use — persist the new one
      // immediately. §3.9: "the new token is persisted before the old is
      // discarded."
      this.tokenStore.saveRefreshToken(realmId, this.credentials.environment, null, result.refreshToken, result.refreshTokenExpiresInSeconds);
      return result.accessToken;
    });
  }

  /**
   * Performs a GET against the QBO Accounting API for a given realm, with
   * the pinned minor version attached.
   */
  async get(realmId: string, path: string, searchParams: Record<string, string> = {}): Promise<unknown> {
    const token = await this.accessToken(realmId);
    const base = resolveApiBaseUrl(this.credentials.environment);
    const url = new URL(`${base}/v3/company/${encodeURIComponent(realmId)}/${path}`);
    url.searchParams.set("minorversion", String(this.credentials.minorVersion));
    for (const [key, value] of Object.entries(searchParams)) {
      url.searchParams.set(key, value);
    }

    const startedAt = Date.now();
    const response = await this.send(realmId, url, {
      method: "GET",
      headers: {
        Authorization: `Bearer ${token}`,
        Accept: "application/json"
      }
    });
    const latencyMs = Date.now() - startedAt;

    if (!response.ok) {
      logEvent("operation_failed", { realmId, httpStatus: response.status, latencyMs });
      throw new QBOApiError(`QBO returned HTTP ${response.status} for ${path}`, response.status, realmId);
    }

    logEvent("operation_succeeded", { realmId, httpStatus: response.status, latencyMs, minorVersion: this.credentials.minorVersion });
    return response.json();
  }

  /**
   * Performs a POST against the QBO Accounting API for a given realm.
   * Added 2026-08-17, once the first write-classified catalog operation's
   * capability spike passed (full-entity Purchase-line reclassification,
   * round-trip verified live — no data loss across DocNumber, PrivateNote,
   * or untouched lines) and the owner explicitly approved crossing this
   * threshold. Callers of `.post()` — i.e. write-classified operations in
   * `catalog/operations.ts` — are responsible for their own round-trip
   * verification; this method itself does not know what "correct" looks
   * like for any given entity, only how to make the request safely.
   */
  async post(realmId: string, path: string, body: unknown, searchParams: Record<string, string> = {}): Promise<unknown> {
    const token = await this.accessToken(realmId);
    const base = resolveApiBaseUrl(this.credentials.environment);
    const url = new URL(`${base}/v3/company/${encodeURIComponent(realmId)}/${path}`);
    url.searchParams.set("minorversion", String(this.credentials.minorVersion));
    for (const [key, value] of Object.entries(searchParams)) {
      url.searchParams.set(key, value);
    }

    const startedAt = Date.now();
    const response = await this.send(realmId, url, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${token}`,
        Accept: "application/json",
        "Content-Type": "application/json"
      },
      body: JSON.stringify(body)
    });
    const latencyMs = Date.now() - startedAt;

    if (!response.ok) {
      logEvent("operation_failed", { realmId, httpStatus: response.status, latencyMs });
      throw new QBOApiError(`QBO returned HTTP ${response.status} for ${path}`, response.status, realmId);
    }

    logEvent("operation_succeeded", { realmId, httpStatus: response.status, latencyMs, minorVersion: this.credentials.minorVersion });
    return response.json();
  }

  /**
   * Intuit allows at most 10 concurrent requests per realm and answers
   * overload with 429. A 429 means the request was NOT processed, so
   * retrying is safe even for a POST. Backoff honors Retry-After when sent.
   */
  private async send(realmId: string, url: URL, init: RequestInit): Promise<Response> {
    await this.acquireSlot(realmId);
    try {
      for (let attempt = 0; ; attempt++) {
        // A stalled request must release its realm slot. Never automatically
        // retry a timeout: for writes, the remote outcome may be unknown.
        const response = await this.fetchImpl(url, { ...init, signal: AbortSignal.timeout(this.requestTimeoutMs) });
        if (response.status !== 429) return response;
        await response.body?.cancel();
        logEvent("rate_limited", { realmId, httpStatus: 429 });
        if (attempt >= MAX_429_RETRIES) {
          throw new QBOApiError("QBO rate limit hit", 429, realmId);
        }
        const retryAfterSeconds = Number(response.headers.get("retry-after"));
        const delayMs = Number.isFinite(retryAfterSeconds) && retryAfterSeconds > 0
          ? Math.min(retryAfterSeconds * 1000, 30_000)
          : BASE_BACKOFF_MS * 2 ** attempt + Math.floor(Math.random() * 250);
        await this.sleep(delayMs);
      }
    } finally {
      this.releaseSlot(realmId);
    }
  }

  private acquireSlot(realmId: string): Promise<void> {
    const active = this.activeRequests.get(realmId) ?? 0;
    if (active < MAX_CONCURRENT_PER_REALM) {
      this.activeRequests.set(realmId, active + 1);
      return Promise.resolve();
    }
    return new Promise((resolve) => {
      const queue = this.waiting.get(realmId) ?? [];
      queue.push(resolve);
      this.waiting.set(realmId, queue);
    });
  }

  private releaseSlot(realmId: string): void {
    const next = this.waiting.get(realmId)?.shift();
    if (next) {
      next(); // hand the slot straight to the next waiter; count unchanged
      return;
    }
    this.activeRequests.set(realmId, (this.activeRequests.get(realmId) ?? 1) - 1);
  }
}
