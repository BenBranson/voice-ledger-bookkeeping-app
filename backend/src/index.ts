/**
 * Voice Ledger thin backend — entry point.
 * docs/phase-0/03_SECURITY_THREAT_MODEL.md §3.3 lists everything this
 * process is responsible for; nothing outside that list belongs here.
 *
 * Phase 1 step 1.2 scope: OAuth, session, the fixed operation catalog,
 * READ operations only. See catalog/operations.ts's assertReadOnlyCatalog().
 */

import "dotenv/config"; // local dev convenience only — loads .env if present; on Render, real env vars are set directly and this is a silent no-op
import express from "express";
import { resolveAppConfig, resolveQBOCredentials, ConfigError } from "./config.js";
import { openDatabase } from "./db/sqlite.js";
import { TokenStore } from "./auth/tokenStore.js";
import { SessionStore } from "./auth/session.js";
import { QBOClient } from "./qbo/client.js";
import { requireSession } from "./middleware/requireSession.js";
import { requireRealmMatch } from "./middleware/realmAuthorization.js";
import { RateLimiter, rateLimitByRealm } from "./middleware/rateLimiter.js";
import { healthRoutes, livenessRoute } from "./routes/health.js";
import { oauthRoutes } from "./routes/oauth.js";
import { operationsRoutes } from "./routes/operations.js";
import { assertReadOnlyCatalog } from "./catalog/operations.js";
import { logEvent } from "./logging/logger.js";

function main(): void {
  assertReadOnlyCatalog();

  let appConfig;
  let qboCredentials;
  try {
    appConfig = resolveAppConfig();
    qboCredentials = resolveQBOCredentials();
  } catch (error) {
    if (error instanceof ConfigError) {
      logEvent("config_error", { error: error.message });
      process.stderr.write(`Configuration error: ${error.message}\n`);
      process.exit(1);
    }
    throw error;
  }

  const db = openDatabase(appConfig.sqlitePath);
  const tokenStore = new TokenStore(db, appConfig.tokenEncryptionKey);
  const sessionStore = new SessionStore(db);
  const qboClient = new QBOClient(qboCredentials, tokenStore);
  const limiter = new RateLimiter();

  const sessionMiddleware = requireSession(sessionStore);
  const rateLimitMiddleware = rateLimitByRealm(limiter);

  const app = express();
  app.use(express.json());

  app.use(livenessRoute());
  app.use(oauthRoutes(qboCredentials, tokenStore, sessionStore));
  app.use(healthRoutes(qboClient, tokenStore, sessionMiddleware, requireRealmMatch, rateLimitMiddleware));
  app.use(operationsRoutes(qboClient, sessionMiddleware, requireRealmMatch, rateLimitMiddleware));

  app.listen(appConfig.port, () => {
    logEvent("server_started");
    process.stdout.write(
      `Voice Ledger backend listening on :${appConfig.port} (QBO environment: ${qboCredentials.environment})\n`
    );
    if (qboCredentials.environment === "production") {
      process.stdout.write(
        "*** PRODUCTION QBO CREDENTIALS ARE ACTIVE. Per CLAUDE.md rule 7, this should not happen during development. ***\n"
      );
    }
  });
}

main();
