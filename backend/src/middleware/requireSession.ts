import type { Request, Response, NextFunction } from "express";
import type { SessionStore } from "../auth/session.js";

declare module "express-serve-static-core" {
  interface Request {
    sessionRealmId?: string;
  }
}

/**
 * Requires a valid `Authorization: Bearer <token>` header, resolves it to a
 * realm, and attaches it to the request. Every route touching QBO data sits
 * behind this. docs/phase-0/03_SECURITY_THREAT_MODEL.md §3.3 item 5:
 * "Issue and validate app sessions for the desktop client."
 */
export function requireSession(sessionStore: SessionStore) {
  return (req: Request, res: Response, next: NextFunction): void => {
    const header = req.header("Authorization");
    if (!header?.startsWith("Bearer ")) {
      res.status(401).json({ error: "Missing or malformed Authorization header." });
      return;
    }
    const token = header.slice("Bearer ".length);
    const session = sessionStore.validate(token);
    if (!session) {
      res.status(401).json({ error: "Session invalid or expired." });
      return;
    }
    req.sessionRealmId = session.realmId;
    next();
  };
}
