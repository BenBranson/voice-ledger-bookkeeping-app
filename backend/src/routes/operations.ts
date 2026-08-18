/**
 * POST /realms/:realmId/operations/:operationName — the generic catalog
 * dispatch endpoint. This route is the ENTIRE surface for every catalog
 * operation other than health (which has its own route for clarity, though
 * it calls the same underlying dispatch). An operation name not present in
 * `CATALOG_OPERATIONS` returns 404 here — not 403, 404 — because it isn't
 * merely forbidden, it doesn't exist as far as this server is concerned.
 * docs/phase-0/03_SECURITY_THREAT_MODEL.md §3.4 property A.
 *
 * Also carries CLAUDE.md rule 4's access-mode gate: this route is the
 * caller that supplies `dispatch`'s `realmWriteEnabled` argument, read
 * fresh from `TokenStore` on every call — never cached, never assumed from
 * a prior request, so flipping write access off takes effect on the very
 * next call.
 */

import { Router, type RequestHandler } from "express";
import type { QBOClient } from "../qbo/client.js";
import type { TokenStore } from "../auth/tokenStore.js";
import { dispatch } from "../catalog/dispatcher.js";

export function operationsRoutes(
  client: QBOClient,
  tokenStore: TokenStore,
  requireSession: RequestHandler,
  requireRealmMatch: RequestHandler,
  rateLimitByRealm: RequestHandler
): Router {
  const router = Router();

  router.post(
    "/realms/:realmId/operations/:operationName",
    requireSession,
    requireRealmMatch,
    rateLimitByRealm,
    async (req, res) => {
      const realmId = req.params.realmId!;
      const operationName = req.params.operationName!;
      const writeEnabled = tokenStore.isWriteEnabled(realmId);
      const result = await dispatch(client, realmId, operationName, req.body, writeEnabled);

      switch (result.kind) {
        case "success":
          res.json(result.data);
          return;
        case "unreachable":
          // Deliberately 404, not 403 — see file doc comment.
          res.status(404).json({ error: `No such operation: "${operationName}"` });
          return;
        case "writeDisabled":
          res.status(403).json({ error: `"${operationName}" is a write operation and this realm is in Read-Only Mode. Enable write access first.` });
          return;
        case "invalidParams":
          res.status(400).json({ error: "Invalid parameters.", issues: result.issues });
          return;
        case "operationError":
          res.status(result.httpStatus).json({ error: result.message });
          return;
      }
    }
  );

  // GET/PUT the realm's write-access flag — separate from the operations
  // dispatch path since this is a control-plane action, not a QBO call.
  router.get(
    "/realms/:realmId/write-access",
    requireSession,
    requireRealmMatch,
    (req, res) => {
      const realmId = req.params.realmId!;
      res.json({ writeEnabled: tokenStore.isWriteEnabled(realmId) });
    }
  );

  router.put(
    "/realms/:realmId/write-access",
    requireSession,
    requireRealmMatch,
    (req, res) => {
      const realmId = req.params.realmId!;
      const body = req.body as { enabled?: unknown };
      if (typeof body.enabled !== "boolean") {
        res.status(400).json({ error: "Body must be { \"enabled\": boolean }." });
        return;
      }
      tokenStore.setWriteEnabled(realmId, body.enabled);
      res.json({ writeEnabled: body.enabled });
    }
  );

  return router;
}
