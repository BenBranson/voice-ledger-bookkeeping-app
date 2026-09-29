/**
 * Dev-only helper for the desktop launcher (Voice Ledger Launcher.app):
 * prints the most recently updated connection's realmId and environment,
 * one per line, so the launcher can hand them to the desktop app without
 * needing to read the sqlite file itself.
 *
 * Reuses the same openDatabase/TokenStore path the backend's own running
 * process already uses successfully — confirmed live 2026-08-28 that the
 * system `sqlite3` CLI hits a permission wall reading this exact file from
 * this exact launch context (`Error: unable to open database ...:
 * authorization denied`) even though `node` reading the identical file via
 * `better-sqlite3` does not. Rather than chase why one system binary is
 * treated differently from another, this sidesteps the question entirely
 * by using the binary (node) already proven to work.
 *
 * Usage:  npx tsx spike/latestConnection.ts
 */
import "dotenv/config";
import { resolveAppConfig } from "../src/config.js";
import { openDatabase } from "../src/db/sqlite.js";
import { TokenStore } from "../src/auth/tokenStore.js";

const appConfig = resolveAppConfig();
const db = openDatabase(appConfig.sqlitePath);

const latest = new TokenStore(db, appConfig.tokenEncryptionKey).listConnections()[0];

if (!latest) {
  process.stderr.write("No connected company found.\n");
  process.exit(1);
}

process.stdout.write(`${latest.realmId}\n${latest.environment}\n`);
db.close();
