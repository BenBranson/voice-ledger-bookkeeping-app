/**
 * Intuit OAuth2 authorization-code exchange and refresh.
 *
 * Implemented as direct calls to Intuit's documented OAuth2 endpoints
 * rather than via a wrapper package — deliberately, so the exact request
 * and response shape is inspectable and testable rather than hidden behind
 * a dependency. docs/phase-0/02_QBO_CAPABILITY_MATRIX.md row C2 marks this
 * ASSUMED (DOC-HIGH) until the Wave 0 OAuth round trip in
 * docs/phase-0/SPIKE_QUEUE.md actually runs against a live sandbox app.
 */

import type { QBOCredentials } from "../config.js";
import { logEvent } from "../logging/logger.js";

// Intuit's discovery documents are the source of truth for the OAuth endpoints
// (Intuit app assessment, Authorization Q5). Checked live 2026-10-03: both
// documents list exactly the fallback values below.
const DISCOVERY_URLS: Record<QBOCredentials["environment"], string> = {
  sandbox: "https://developer.api.intuit.com/.well-known/openid_sandbox_configuration",
  production: "https://developer.api.intuit.com/.well-known/openid_configuration"
};
const DISCOVERY_TTL_MS = 24 * 60 * 60 * 1000;

export interface OAuthEndpoints {
  readonly authorizationEndpoint: string;
  readonly tokenEndpoint: string;
  readonly revocationEndpoint: string;
}

/** Used only when the discovery document can't be fetched or fails validation. */
export const FALLBACK_OAUTH_ENDPOINTS: OAuthEndpoints = {
  authorizationEndpoint: "https://appcenter.intuit.com/connect/oauth2",
  tokenEndpoint: "https://oauth.platform.intuit.com/oauth2/v1/tokens/bearer",
  revocationEndpoint: "https://developer.api.intuit.com/v2/oauth2/tokens/revoke"
};

const discoveryCache = new Map<string, { endpoints: OAuthEndpoints; fetchedAt: number }>();

/** An endpoint is accepted only if it is https on an intuit.com host. */
function isIntuitHttpsUrl(value: unknown): value is string {
  if (typeof value !== "string") return false;
  try {
    const url = new URL(value);
    return url.protocol === "https:" && (url.hostname === "intuit.com" || url.hostname.endsWith(".intuit.com"));
  } catch {
    return false;
  }
}

/**
 * Reads the OAuth endpoints from Intuit's discovery document for this
 * environment, cached for 24 hours. Falls back to the documented endpoints
 * (and logs it) rather than blocking a connection if Intuit's document is
 * unreachable or malformed.
 */
export async function resolveOAuthEndpoints(
  environment: QBOCredentials["environment"],
  fetcher: typeof fetch = fetch,
  now: number = Date.now()
): Promise<OAuthEndpoints> {
  const cached = discoveryCache.get(environment);
  if (cached && now - cached.fetchedAt < DISCOVERY_TTL_MS) return cached.endpoints;
  try {
    const response = await fetcher(DISCOVERY_URLS[environment], {
      headers: { Accept: "application/json" },
      signal: AbortSignal.timeout(10_000)
    });
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    const doc = (await response.json()) as Record<string, unknown>;
    const { authorization_endpoint, token_endpoint, revocation_endpoint } = doc;
    if (!isIntuitHttpsUrl(authorization_endpoint) || !isIntuitHttpsUrl(token_endpoint) || !isIntuitHttpsUrl(revocation_endpoint)) {
      throw new Error("DiscoveryDocumentInvalid");
    }
    const endpoints = {
      authorizationEndpoint: authorization_endpoint,
      tokenEndpoint: token_endpoint,
      revocationEndpoint: revocation_endpoint
    };
    discoveryCache.set(environment, { endpoints, fetchedAt: now });
    return endpoints;
  } catch (error) {
    logEvent("oauth_discovery_failed", { outcome: "fault", error: error instanceof Error ? error.message : "UnknownError" });
    return FALLBACK_OAUTH_ENDPOINTS;
  }
}

/** Test hook: forget cached discovery results. */
export function clearOAuthDiscoveryCache(): void {
  discoveryCache.clear();
}

// The only scope QBO's accounting API offers. It grants read AND write
// together — there is no read-only scope. Self-enforcement (the operation
// catalog, realm access-mode gate) is the entire safety story.
// docs/VOICE_LEDGER_SPEC.md, "QBO has no read-only mode."
const ACCOUNTING_SCOPE = "com.intuit.quickbooks.accounting";

export interface TokenResponse {
  readonly accessToken: string;
  readonly refreshToken: string;
  readonly expiresInSeconds: number;
  readonly refreshTokenExpiresInSeconds: number;
}

export async function buildAuthorizationUrl(credentials: QBOCredentials, state: string): Promise<string> {
  const { authorizationEndpoint } = await resolveOAuthEndpoints(credentials.environment);
  const url = new URL(authorizationEndpoint);
  url.searchParams.set("client_id", credentials.clientId);
  url.searchParams.set("redirect_uri", credentials.redirectUri);
  url.searchParams.set("response_type", "code");
  url.searchParams.set("scope", ACCOUNTING_SCOPE);
  url.searchParams.set("state", state);
  return url.toString();
}

function basicAuthHeader(clientId: string, clientSecret: string): string {
  return "Basic " + Buffer.from(`${clientId}:${clientSecret}`).toString("base64");
}

async function postTokenRequest(
  credentials: QBOCredentials,
  body: URLSearchParams
): Promise<TokenResponse> {
  const { tokenEndpoint } = await resolveOAuthEndpoints(credentials.environment);
  const response = await fetch(tokenEndpoint, {
    method: "POST",
    headers: {
      Authorization: basicAuthHeader(credentials.clientId, credentials.clientSecret),
      "Content-Type": "application/x-www-form-urlencoded",
      Accept: "application/json"
    },
    body,
    signal: AbortSignal.timeout(30_000)
  });

  if (!response.ok) {
    // Deliberately not logging the response body — it can contain
    // token-shaped values, and §3.5 forbids that regardless of context.
    throw new OAuthError(`Token endpoint returned HTTP ${response.status}`, response.status);
  }

  const json = (await response.json()) as {
    access_token: string;
    refresh_token: string;
    expires_in: number;
    x_refresh_token_expires_in: number;
  };

  return {
    accessToken: json.access_token,
    refreshToken: json.refresh_token,
    expiresInSeconds: json.expires_in,
    refreshTokenExpiresInSeconds: json.x_refresh_token_expires_in
  };
}

export async function exchangeAuthorizationCode(
  credentials: QBOCredentials,
  code: string
): Promise<TokenResponse> {
  const body = new URLSearchParams({
    grant_type: "authorization_code",
    code,
    redirect_uri: credentials.redirectUri
  });
  const result = await postTokenRequest(credentials, body);
  logEvent("oauth_exchange", { outcome: "success" });
  return result;
}

export async function refreshAccessToken(
  credentials: QBOCredentials,
  refreshToken: string,
  realmId: string
): Promise<TokenResponse> {
  const body = new URLSearchParams({
    grant_type: "refresh_token",
    refresh_token: refreshToken
  });
  try {
    const result = await postTokenRequest(credentials, body);
    logEvent("oauth_refresh", { realmId, outcome: "success" });
    return result;
  } catch (error) {
    // §3.9: "a refresh failure is surfaced on the Connection Page as red
    // with the specific cause, not as a generic sync error." This backend
    // event is what a future Connection Page reads to render that.
    logEvent("oauth_refresh_failed", {
      realmId,
      outcome: "fault",
      error: error instanceof Error ? error.name : "UnknownError"
    });
    throw error;
  }
}

/** Revoking the refresh token ends the app's whole grant for that company. */
export async function revokeToken(credentials: QBOCredentials, refreshToken: string): Promise<void> {
  const { revocationEndpoint } = await resolveOAuthEndpoints(credentials.environment);
  const response = await fetch(revocationEndpoint, {
    method: "POST",
    headers: {
      Authorization: basicAuthHeader(credentials.clientId, credentials.clientSecret),
      "Content-Type": "application/json",
      Accept: "application/json"
    },
    body: JSON.stringify({ token: refreshToken }),
    signal: AbortSignal.timeout(30_000)
  });
  if (!response.ok) {
    throw new OAuthError(`Revoke endpoint returned HTTP ${response.status}`, response.status);
  }
}

export class OAuthError extends Error {
  constructor(
    message: string,
    readonly httpStatus: number
  ) {
    super(message);
    this.name = "OAuthError";
  }
}
