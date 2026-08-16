/**
 * Dev-only helper: mint a fresh app session for an ALREADY-CONNECTED realm.
 *
 * Why this exists: `/oauth/callback` returns the session token exactly once,
 * in a browser response. `SessionStore` only ever persists a SHA-256 hash
 * (src/auth/session.ts), so a token that's been lost cannot be recovered —
 * that's the intended design, not a gap. Re-running the whole OAuth consent
 * flow just to get a new bearer token is disproportionate when the realm's
 * refresh token is already stored and valid.
 *
 * This calls the SAME `SessionStore.create()` the OAuth callback uses. It
 * does not bypass a security control: it refuses to run for a realm that
 * has no stored connection, so it cannot mint a session for a company the
 * user never authorized.
 *
 * Writes the token to a file (mode 600) rather than stdout, so it doesn't
 * land in terminal scrollback or a log.
 *
 * Usage:  npx tsx spike/mintDevSession.ts <realmId> <outputPath>
 */

import "dotenv/config";
import { writeFileSync } from "node:fs";
import { resolveAppConfig } from "../src/config.js";
import { openDatabase } from "../src/db/sqlite.js";
import { SessionStore } from "../src/auth/session.js";
import { TokenStore } from "../src/auth/tokenStore.js";

const [, , realmId, outputPath] = process.argv;

if (!realmId || !outputPath) {
  process.stderr.write("Usage: npx tsx spike/mintDevSession.ts <realmId> <outputPath>\n");
  process.exit(64);
}

const appConfig = resolveAppConfig();
const db = openDatabase(appConfig.sqlitePath);
const tokenStore = new TokenStore(db, appConfig.tokenEncryptionKey);

// Refuse to mint a session for a realm that was never authorized. Without
// this check the helper would be a way to fabricate a session for an
// arbitrary realm id, which is exactly what §3.3 item 11 exists to prevent.
const connection = tokenStore.getConnection(realmId);
if (!connection) {
  process.stderr.write(
    `No stored connection for realm ${realmId}. Connect it via /oauth/authorize first — ` +
      `this helper only re-issues a session for an already-authorized company.\n`
  );
  process.exit(1);
}

const sessionStore = new SessionStore(db);
const token = sessionStore.create(realmId);
writeFileSync(outputPath, token, { mode: 0o600 });

process.stdout.write(
  `Session minted for realm ${realmId} (environment: ${connection.environment}).\n` +
    `Token written to ${outputPath} (mode 600, ${token.length} chars). Not printed here by design.\n`
);

db.close();
