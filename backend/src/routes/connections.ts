/**
 * GET /connections — docs/VOICE_LEDGER_SPEC.md's Firm Cockpit: "every
 * connected client on one screen." Deliberately NOT realm-scoped (no
 * `requireRealmMatch`) — this is the one place in the API surface that
 * intentionally crosses realm boundaries, because listing every realm
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
 */

import { Router, type RequestHandler } from "express";
import type { TokenStore } from "../auth/tokenStore.js";

export function connectionsRoutes(tokenStore: TokenStore, requireSession: RequestHandler): Router {
  const router = Router();

  router.get("/connections", requireSession, (_req, res) => {
    res.json({ connections: tokenStore.listConnections() });
  });

  return router;
}
