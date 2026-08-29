/**
 * Voice Ledger thin backend — entry point.
 * docs/phase-0/03_SECURITY_THREAT_MODEL.md §3.3 lists everything this
 * process is responsible for; nothing outside that list belongs here.
 *
 * Phase 1 step 1.2 scope: OAuth, session, the fixed operation catalog. As
 * of 2026-08-17 the catalog has exactly one write-classified operation
 * (`updatePurchaseLineAccount`, spike-verified and owner-approved) — see
 * catalog/operations.ts's `assertCatalogWriteOpsAreApproved()`.
 */

import "dotenv/config"; // local dev convenience only — loads .env if present; on Render, real env vars are set directly and this is a silent no-op
import express from "express";
import { resolveAppConfig, resolveQBOCredentials, resolveAIConfig, ConfigError } from "./config.js";
import { openDatabase } from "./db/sqlite.js";
import { TokenStore } from "./auth/tokenStore.js";
import { SessionStore } from "./auth/session.js";
import { QBOClient } from "./qbo/client.js";
import { AISettingsStore } from "./ai/aiSettingsStore.js";
import { requireSession } from "./middleware/requireSession.js";
import { requireRealmMatch } from "./middleware/realmAuthorization.js";
import { RateLimiter, rateLimitByRealm } from "./middleware/rateLimiter.js";
import { healthRoutes, livenessRoute } from "./routes/health.js";
import { oauthRoutes } from "./routes/oauth.js";
import { operationsRoutes } from "./routes/operations.js";
import { aiRoutes } from "./routes/ai.js";
import { connectionsRoutes } from "./routes/connections.js";
import { assertCatalogWriteOpsAreApproved } from "./catalog/operations.js";
import { logEvent } from "./logging/logger.js";

function main(): void {
  assertCatalogWriteOpsAreApproved();

  let appConfig;
  let qboCredentials;
  let aiConfig;
  try {
    appConfig = resolveAppConfig();
    qboCredentials = resolveQBOCredentials();
    // Never throws — a missing OPENAI_API_KEY just means AI features stay
    // off (`/ai/status` reports `configured: false`), not a startup
    // failure. Unlike QBO, this app has to run fully without it.
    aiConfig = resolveAIConfig();
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
  const aiSettingsStore = new AISettingsStore(db);
  const limiter = new RateLimiter();

  const sessionMiddleware = requireSession(sessionStore);
  const rateLimitMiddleware = rateLimitByRealm(limiter);

  const app = express();
  app.use(express.json());

  app.use(livenessRoute());
  app.use(oauthRoutes(qboCredentials, tokenStore, sessionStore));
  app.use(healthRoutes(qboClient, tokenStore, sessionMiddleware, requireRealmMatch, rateLimitMiddleware));
  app.use(operationsRoutes(qboClient, tokenStore, sessionMiddleware, requireRealmMatch, rateLimitMiddleware));
  app.use(aiRoutes(aiConfig, aiSettingsStore, sessionMiddleware, requireRealmMatch, rateLimitMiddleware));
  app.use(connectionsRoutes(tokenStore, sessionStore, sessionMiddleware));

  app.listen(appConfig.port, () => {
    logEvent("server_started");
    process.stdout.write(
      `Voice Ledger backend listening on :${appConfig.port} (QBO environment: ${qboCredentials.environment}, AI: ${aiConfig ? "configured" : "not configured"})\n`
    );
    if (qboCredentials.environment === "production") {
      process.stdout.write(
        "*** PRODUCTION QBO CREDENTIALS ARE ACTIVE. Per CLAUDE.md rule 7, this should not happen during development. ***\n"
      );
    }
  });
}

main();
