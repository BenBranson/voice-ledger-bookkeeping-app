/**
 * GET /realms/:realmId/health — the exact call
 * docs/phase-0/02_QBO_CAPABILITY_MATRIX.md row C1 and
 * docs/phase-0/00_OVERVIEW.md's Phase 1 step 1.2 exit gate ("health check
 * green from the desktop") are both about. A LIVE call, timestamped, never
 * a cached assumption — per docs/VOICE_LEDGER_SPEC.md's Connection Pages
 * section: "Health check must be a real request, not a cached assumption."
 *
 * Internally this is just `readCompanyInfo` — there is exactly one
 * implementation of "is this connection actually alive," reused here
 * rather than duplicated.
 */

import { Router, type RequestHandler } from "express";
import type { QBOClient } from "../qbo/client.js";
import type { TokenStore } from "../auth/tokenStore.js";
import { dispatch } from "../catalog/dispatcher.js";

export function healthRoutes(
  client: QBOClient,
  tokenStore: TokenStore,
  requireSession: RequestHandler,
  requireRealmMatch: RequestHandler,
  rateLimitByRealm: RequestHandler
): Router {
  const router = Router();

  router.get("/realms/:realmId/health", requireSession, requireRealmMatch, rateLimitByRealm, async (req, res) => {
    const realmId = req.params.realmId!;
    const startedAt = Date.now();
    const checkedAt = new Date().toISOString();

    const result = await dispatch(client, realmId, "readCompanyInfo", {});
    const latencyMs = Date.now() - startedAt;
    // 2026-09-11: real data QBO already hands back on every token
    // exchange/refresh (`x_refresh_token_expires_in`) — the Connection
    // page reads this off the SAME call it already makes to check health,
    // no new request needed.
    const refreshTokenExpiresAt = tokenStore.getConnection(realmId)?.refreshTokenExpiresAt ?? null;

    if (result.kind === "success") {
      tokenStore.recordHealthCheck(realmId, "green", checkedAt);
      res.json({ realmId, status: "green", checkedAt, latencyMs, detail: null, refreshTokenExpiresAt });
      return;
    }

    if (result.kind === "operationError" && result.httpStatus === 401) {
      // Token revoked or invalid — exactly the failure this page exists to
      // catch (docs/VOICE_LEDGER_SPEC.md, Connection Pages: "A token that
      // looks structurally valid but was revoked on Intuit's side is
      // exactly the failure this page exists to catch.")
      tokenStore.recordHealthCheck(realmId, "red", checkedAt);
      res.json({ realmId, status: "red", checkedAt, latencyMs, detail: "Authorization failed — reconnect required.", refreshTokenExpiresAt });
      return;
    }

    tokenStore.recordHealthCheck(realmId, "red", checkedAt);
    const detail = result.kind === "operationError" ? result.message : "Health check could not complete.";
    res.json({ realmId, status: "red", checkedAt, latencyMs, detail, refreshTokenExpiresAt });
  });

  return router;
}

/** Plain liveness probe — no auth, no QBO call. For Render's health check config. */
export function livenessRoute(): Router {
  const router = Router();
  router.get("/healthz", (_req, res) => {
    res.json({ status: "ok", timestamp: new Date().toISOString() });
  });
  return router;
}
