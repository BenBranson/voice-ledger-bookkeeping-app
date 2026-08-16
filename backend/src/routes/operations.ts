/**
 * POST /realms/:realmId/operations/:operationName — the generic catalog
 * dispatch endpoint. This route is the ENTIRE surface for every catalog
 * operation other than health (which has its own route for clarity, though
 * it calls the same underlying dispatch). An operation name not present in
 * `CATALOG_OPERATIONS` returns 404 here — not 403, 404 — because it isn't
 * merely forbidden, it doesn't exist as far as this server is concerned.
 * docs/phase-0/03_SECURITY_THREAT_MODEL.md §3.4 property A.
 */

import { Router, type RequestHandler } from "express";
import type { QBOClient } from "../qbo/client.js";
import { dispatch } from "../catalog/dispatcher.js";

export function operationsRoutes(
  client: QBOClient,
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
      const result = await dispatch(client, realmId, operationName, req.body);

      switch (result.kind) {
        case "success":
          res.json(result.data);
          return;
        case "unreachable":
          // Deliberately 404, not 403 — see file doc comment.
          res.status(404).json({ error: `No such operation: "${operationName}"` });
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

  return router;
}
