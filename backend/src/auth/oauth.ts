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

const AUTHORIZATION_BASE_URL = "https://appcenter.intuit.com/connect/oauth2";
const TOKEN_URL = "https://oauth.platform.intuit.com/oauth2/v1/tokens/bearer";

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

export function buildAuthorizationUrl(credentials: QBOCredentials, state: string): string {
  const url = new URL(AUTHORIZATION_BASE_URL);
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
  const response = await fetch(TOKEN_URL, {
    method: "POST",
    headers: {
      Authorization: basicAuthHeader(credentials.clientId, credentials.clientSecret),
      "Content-Type": "application/x-www-form-urlencoded",
      Accept: "application/json"
    },
    body
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

export class OAuthError extends Error {
  constructor(
    message: string,
    readonly httpStatus: number
  ) {
    super(message);
    this.name = "OAuthError";
  }
}
