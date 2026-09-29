/**
 * GET /connections — docs/VOICE_LEDGER_SPEC.md's Firm Cockpit: "every
 * connected client on one screen." Deliberately NOT realm-scoped (no
 * `requireRealmMatch`) — this is one of two places in the API surface
 * that intentionally cross realm boundaries, because listing every realm
 * IS the point. Still requires a valid session (any realm's), the same
 * "any authenticated session authorizes this app-wide read" posture
 * `routes/ai.ts`'s `/ai/status` already established — this app is a
 * single-operator tool (docs/VOICE_LEDGER_HANDOFF.md: "solo bookkeeper"),
 * so a session for realm A asking "what else have I connected" is not a
 * cross-tenant data leak the way it would be in a multi-operator product.
 *
 * Never returns anything derived from a refresh token — only the same
 * public-shape fields `TokenStore.getConnection` already exposes for a
 * single realm (§3.5's forbidden-log-fields discipline doesn't apply to
 * HTTP response bodies, but the same instinct — don't return more than
 * the caller needs — still governs what's in `StoredConnection`).
 *
 * POST /realms/:realmId/session — the Client Switcher's only new server
 * surface: mints a fresh session token for a DIFFERENT already-connected
 * realm than the caller's own session. This is the second deliberate
 * realm-boundary crossing in this file, and it's the more sensitive one
 * — same reasoning extended one step further: a session for realm A
 * requesting a session for realm B is not a privilege escalation for a
 * single-operator tool, since realm A's session already proves "this is
 * the same person who owns this backend instance." Mirrors
 * `backend/spike/mintDevSession.ts`'s own safety property exactly —
 * refuses to mint for a realm with no stored connection, so it can never
 * fabricate access to a company that was never authorized via the real
 * OAuth flow. Never accepts or needs a refresh token from the caller;
 * only `SessionStore.create`, the exact mechanism `/oauth/callback`
 * already uses for a brand-new connection.
 */

import { Router, type RequestHandler } from "express";
import type { TokenStore } from "../auth/tokenStore.js";
import type { SessionStore } from "../auth/session.js";
import type { QBOCredentials } from "../config.js";
import { revokeToken } from "../auth/oauth.js";
import { requireRealmMatch } from "../middleware/realmAuthorization.js";
import { logEvent } from "../logging/logger.js";

export function connectionsRoutes(
  tokenStore: TokenStore,
  sessionStore: SessionStore,
  requireSession: RequestHandler,
  credentials: QBOCredentials,
  revoke: typeof revokeToken = revokeToken
): Router {
  const router = Router();

  router.get("/connections", requireSession, (_req, res) => {
    res.json({ connections: tokenStore.listConnections() });
  });

  router.post("/realms/:realmId/session", requireSession, (req, res) => {
    const targetRealmId = req.params.realmId!;
    const connection = tokenStore.getConnection(targetRealmId);
    if (!connection) {
      res.status(404).json({ error: "No connection found for this realmId. Connect it via /oauth/authorize first." });
      return;
    }
    const sessionToken = sessionStore.create(targetRealmId);
    res.json({ realmId: targetRealmId, environment: connection.environment, sessionToken });
  });

  // Intuit-required disconnect: revoke the grant at Intuit, then delete
  // the stored tokens and every session for the realm. Local deletion
  // happens even if Intuit's revoke call fails, and the response says
  // which, so the UI never claims a revoke that didn't happen.
  router.post("/realms/:realmId/disconnect", requireSession, requireRealmMatch, async (req, res) => {
    const realmId = req.params.realmId!;
    const refreshToken = tokenStore.getRefreshToken(realmId);
    if (!refreshToken) {
      res.status(404).json({ error: "No connection found for this realmId." });
      return;
    }
    let revokedAtIntuit = true;
    try {
      await revoke(credentials, refreshToken);
    } catch (error) {
      revokedAtIntuit = false;
      logEvent("connection_disconnected", { realmId, outcome: "fault", error: error instanceof Error ? error.message : "UnknownError" });
    }
    tokenStore.deleteConnection(realmId);
    if (revokedAtIntuit) logEvent("connection_disconnected", { realmId, outcome: "success" });
    res.json({ realmId, revokedAtIntuit, localTokensDeleted: true });
  });

  return router;
}
