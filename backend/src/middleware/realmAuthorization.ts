import type { Request, Response, NextFunction } from "express";
import { logEvent } from "../logging/logger.js";

/**
 * docs/phase-0/03_SECURITY_THREAT_MODEL.md §3.3 item 11 / §7.4 mechanism 2:
 * "Refuse any request whose realmId is not bound to the caller's session...
 * the backend independently verifies the session is authorized for that
 * realm." `requireSession` establishes WHO is asking; this establishes
 * whether they're allowed to ask about THIS realm — a session for realm A
 * requesting realm B's data is refused here regardless of what the desktop
 * client sent, because the desktop client's claim about which realm it
 * wants is not itself authorization (§7.4 item 2: two independent checks on
 * opposite sides of the network boundary, so neither alone is trusted).
 */
export function requireRealmMatch(req: Request, res: Response, next: NextFunction): void {
  const requestedRealmId = req.params.realmId;
  if (!requestedRealmId) {
    res.status(400).json({ error: "realmId path parameter is required." });
    return;
  }
  if (req.sessionRealmId !== requestedRealmId) {
    logEvent("realm_authorization_denied", { realmId: requestedRealmId });
    res.status(403).json({ error: "Session is not authorized for this realm." });
    return;
  }
  next();
}
