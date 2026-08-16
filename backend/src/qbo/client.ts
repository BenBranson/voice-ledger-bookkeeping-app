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

export class QBOClient {
  constructor(
    private readonly credentials: QBOCredentials,
    private readonly tokenStore: TokenStore
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
      this.tokenStore.saveRefreshToken(realmId, this.credentials.environment, null, result.refreshToken);
      return result.accessToken;
    });
  }

  /**
   * Performs a GET against the QBO Accounting API for a given realm, with
   * the pinned minor version attached. This is intentionally the ONLY verb
   * exposed in Phase 1 step 1.2 — no write method exists on this class yet.
   * Per the owner's Phase 1 approval: "No write operation enters the
   * catalog until its spike test has passed."
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
    const response = await fetch(url, {
      method: "GET",
      headers: {
        Authorization: `Bearer ${token}`,
        Accept: "application/json"
      }
    });
    const latencyMs = Date.now() - startedAt;

    if (response.status === 429) {
      logEvent("rate_limited", { realmId, httpStatus: 429, latencyMs });
      throw new QBOApiError("QBO rate limit hit", 429, realmId);
    }

    if (!response.ok) {
      logEvent("operation_failed", { realmId, httpStatus: response.status, latencyMs });
      throw new QBOApiError(`QBO returned HTTP ${response.status} for ${path}`, response.status, realmId);
    }

    logEvent("operation_succeeded", { realmId, httpStatus: response.status, latencyMs, minorVersion: this.credentials.minorVersion });
    return response.json();
  }
}
