/**
 * GET /oauth/authorize — starts Intuit's authorization flow.
 * GET /oauth/callback — exchanges the code, stores the refresh token
 * (encrypted), issues an app session.
 *
 * Phase 1 step 1.2 has no Connection Page UI yet (that's step 1.3). This
 * endpoint's callback response is deliberately a plain JSON blob containing
 * the session token, meant to be copied by hand into
 * VOICE_LEDGER_SESSION_TOKEN for `voiceledger-devtool` during Wave 0 setup
 * (docs/phase-0/SPIKE_QUEUE.md). It is a development convenience, not the
 * product UI.
 */

import { Router } from "express";
import { randomBytes } from "node:crypto";
import type { QBOCredentials } from "../config.js";
import type { TokenStore } from "../auth/tokenStore.js";
import type { SessionStore } from "../auth/session.js";
import { buildAuthorizationUrl, exchangeAuthorizationCode, OAuthError } from "../auth/oauth.js";

// CSRF protection on the OAuth callback (state parameter), per standard
// OAuth2 practice. In-memory with a short TTL — a lost server process
// mid-flow simply means the user restarts the connect flow, which is an
// acceptable Phase 1 tradeoff for a single-operator tool.
const pendingStates = new Map<string, number>();
const STATE_TTL_MS = 10 * 60 * 1000;

function issueState(): string {
  const state = randomBytes(16).toString("hex");
  pendingStates.set(state, Date.now() + STATE_TTL_MS);
  return state;
}

function consumeState(state: string | undefined): boolean {
  if (!state) return false;
  const expiresAt = pendingStates.get(state);
  pendingStates.delete(state);
  if (!expiresAt) return false;
  return Date.now() < expiresAt;
}

export function oauthRoutes(
  credentials: QBOCredentials,
  tokenStore: TokenStore,
  sessionStore: SessionStore
): Router {
  const router = Router();

  router.get("/oauth/authorize", (_req, res) => {
    const state = issueState();
    res.redirect(buildAuthorizationUrl(credentials, state));
  });

  router.get("/oauth/callback", async (req, res) => {
    const { code, state, realmId } = req.query;

    if (!consumeState(typeof state === "string" ? state : undefined)) {
      res.status(400).json({ error: "Invalid or expired OAuth state. Restart the connect flow at /oauth/authorize." });
      return;
    }
    if (typeof code !== "string" || typeof realmId !== "string") {
      res.status(400).json({ error: "Missing code or realmId in callback." });
      return;
    }

    try {
      const tokenResponse = await exchangeAuthorizationCode(credentials, code);
      tokenStore.saveRefreshToken(realmId, credentials.environment, null, tokenResponse.refreshToken);
      tokenStore.cacheAccessToken(realmId, tokenResponse.accessToken, tokenResponse.expiresInSeconds);

      const sessionToken = sessionStore.create(realmId);

      res.json({
        message: "Connected. This JSON response is a Phase 1 development convenience — the Connection Page (step 1.3) will replace it.",
        realmId,
        environment: credentials.environment,
        sessionToken,
        nextSteps: [
          "export VOICE_LEDGER_BACKEND_URL=<this backend's base URL>",
          `export VOICE_LEDGER_SESSION_TOKEN=${sessionToken}`,
          `export VOICE_LEDGER_REALM_ID=${realmId}`,
          "swift run voiceledger-devtool health   # from desktop/"
        ]
      });
    } catch (error) {
      const status = error instanceof OAuthError ? error.httpStatus : 502;
      res.status(status).json({ error: "OAuth token exchange failed." });
    }
  });

  return router;
}
