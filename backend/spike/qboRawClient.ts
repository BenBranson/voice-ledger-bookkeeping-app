/**
 * Raw QBO client for the CAPABILITY SPIKE ONLY.
 *
 * docs/phase-0/02_QBO_CAPABILITY_MATRIX.md §2.8, Wave 3 note (implicit in
 * the spec's framing): discovering what an endpoint does — including
 * writes and operations like void that aren't in the production catalog
 * yet — necessarily means calling QBO directly, before we know enough to
 * commit to a typed catalog operation. `src/qbo/client.ts` (the production
 * client) intentionally exposes ONLY `.get()` in Phase 1 step 1.2; this
 * file exists precisely so that restriction never gets loosened just to
 * make spike testing convenient.
 *
 * ⚠ This file must never be imported from `src/`. Nothing here is
 * reachable by the desktop client or subject to the operation catalog's
 * guarantees — it exists only for `npm run spike`, run by a developer
 * against a sandbox company, by hand.
 *
 * Reuses the same encrypted token store the backend already populated via
 * a normal /oauth/authorize -> /oauth/callback round trip, so there's only
 * one place a refresh token is ever stored.
 */

import { resolveQBOCredentials, resolveAppConfig } from "../src/config.js";
import { openDatabase } from "../src/db/sqlite.js";
import { TokenStore } from "../src/auth/tokenStore.js";
import { refreshAccessToken } from "../src/auth/oauth.js";
import { resolveApiBaseUrl } from "../src/qbo/environment.js";

export interface QboRawResponse {
  readonly status: number;
  readonly body: unknown;
  readonly headers: Readonly<Record<string, string>>;
  readonly latencyMs: number;
}

export class QboRawClient {
  private readonly credentials = resolveQBOCredentials();
  private readonly tokenStore: TokenStore;
  readonly realmId: string;

  constructor() {
    const realmId = process.env.QBO_SPIKE_REALM_ID;
    if (!realmId) {
      throw new Error("QBO_SPIKE_REALM_ID not set. Connect via /oauth/authorize first (see spike/README.md).");
    }
    this.realmId = realmId;
    const appConfig = resolveAppConfig();
    const db = openDatabase(appConfig.sqlitePath);
    this.tokenStore = new TokenStore(db, appConfig.tokenEncryptionKey);
  }

  private async accessToken(): Promise<string> {
    const cached = this.tokenStore.getCachedAccessToken(this.realmId);
    if (cached) return cached;
    const refreshToken = this.tokenStore.getRefreshToken(this.realmId);
    if (!refreshToken) {
      throw new Error(`No refresh token stored for realm ${this.realmId}. Reconnect via /oauth/authorize.`);
    }
    const result = await refreshAccessToken(this.credentials, refreshToken, this.realmId);
    this.tokenStore.cacheAccessToken(this.realmId, result.accessToken, result.expiresInSeconds);
    this.tokenStore.saveRefreshToken(this.realmId, this.credentials.environment, null, result.refreshToken);
    return result.accessToken;
  }

  private async request(
    method: string,
    path: string,
    body?: unknown,
    extraParams: Record<string, string> = {},
    overrideAccessToken?: string
  ): Promise<QboRawResponse> {
    const token = overrideAccessToken ?? (await this.accessToken());
    const base = resolveApiBaseUrl(this.credentials.environment);
    const url = new URL(`${base}/v3/company/${this.realmId}/${path}`);
    url.searchParams.set("minorversion", String(this.credentials.minorVersion));
    for (const [key, value] of Object.entries(extraParams)) {
      url.searchParams.set(key, value);
    }
    const startedAt = Date.now();
    const response = await fetch(url, {
      method,
      headers: {
        Authorization: `Bearer ${token}`,
        Accept: "application/json",
        ...(body ? { "Content-Type": "application/json" } : {})
      },
      // exactOptionalPropertyTypes forbids `body: undefined` — only include
      // the key at all when there's a body to send.
      ...(body ? { body: JSON.stringify(body) } : {})
    });
    const latencyMs = Date.now() - startedAt;
    const responseBody = await response.json().catch(() => null);
    const headers: Record<string, string> = {};
    response.headers.forEach((value, key) => {
      headers[key] = value;
    });
    return { status: response.status, body: responseBody, headers, latencyMs };
  }

  get(path: string, extraParams: Record<string, string> = {}): Promise<QboRawResponse> {
    return this.request("GET", path, undefined, extraParams);
  }

  post(path: string, body: unknown, extraParams: Record<string, string> = {}): Promise<QboRawResponse> {
    return this.request("POST", path, body, extraParams);
  }

  query(sql: string): Promise<QboRawResponse> {
    return this.get("query", { query: sql });
  }

  /** For testCompanyInfoHealthCheck's "error shape on an invalid token" probe only. */
  getWithOverrideToken(path: string, accessToken: string): Promise<QboRawResponse> {
    return this.request("GET", path, undefined, {}, accessToken);
  }
}
