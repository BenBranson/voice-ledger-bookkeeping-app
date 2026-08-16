/**
 * Per-realm token storage. Refresh tokens are durable and encrypted
 * (SQLite); access tokens are cache-only, in process memory, TTL-bounded —
 * per docs/phase-0/03_SECURITY_THREAT_MODEL.md §3.2's table.
 *
 * §3.9: "Refresh-token rotation is a correctness hazard, not just a
 * security one... refresh is serialized per realmId, the new token is
 * persisted before the old is discarded." This module's `refreshSerializer`
 * map is that serialization.
 */

import type Database from "better-sqlite3";
import { encrypt, decrypt, type EncryptedPayload } from "./crypto.js";
import type { Environment } from "../config.js";

export interface StoredConnection {
  readonly realmId: string;
  readonly environment: Environment;
  readonly companyName: string | null;
  readonly createdAt: string;
  readonly updatedAt: string;
}

interface CachedAccessToken {
  readonly value: string;
  readonly expiresAt: number; // epoch ms
}

interface ConnectionRow {
  realm_id: string;
  environment: Environment;
  company_name: string | null;
  refresh_token_iv: string;
  refresh_token_auth_tag: string;
  refresh_token_ciphertext: string;
  created_at: string;
  updated_at: string;
}

export class TokenStore {
  private readonly accessTokenCache = new Map<string, CachedAccessToken>();
  // §3.9: refresh must be serialized per realmId so a crash between "wrote
  // the new token" and "discarded the old" can't race with a second
  // concurrent refresh attempt for the same realm.
  private readonly refreshLocks = new Map<string, Promise<unknown>>();

  constructor(
    private readonly db: Database.Database,
    private readonly encryptionKey: Buffer
  ) {}

  saveRefreshToken(realmId: string, environment: Environment, companyName: string | null, refreshToken: string): void {
    const encrypted = encrypt(refreshToken, this.encryptionKey);
    const now = new Date().toISOString();
    this.db
      .prepare(
        `INSERT INTO connections (realm_id, environment, company_name, refresh_token_iv, refresh_token_auth_tag, refresh_token_ciphertext, created_at, updated_at)
         VALUES (@realmId, @environment, @companyName, @iv, @authTag, @ciphertext, @now, @now)
         ON CONFLICT(realm_id) DO UPDATE SET
           refresh_token_iv = @iv,
           refresh_token_auth_tag = @authTag,
           refresh_token_ciphertext = @ciphertext,
           updated_at = @now`
      )
      .run({
        realmId,
        environment,
        companyName,
        iv: encrypted.iv,
        authTag: encrypted.authTag,
        ciphertext: encrypted.ciphertext,
        now
      });
  }

  getRefreshToken(realmId: string): string | null {
    const row = this.db
      .prepare<{ realmId: string }, ConnectionRow>(
        "SELECT * FROM connections WHERE realm_id = @realmId"
      )
      .get({ realmId });
    if (!row) return null;
    const payload: EncryptedPayload = {
      iv: row.refresh_token_iv,
      authTag: row.refresh_token_auth_tag,
      ciphertext: row.refresh_token_ciphertext
    };
    return decrypt(payload, this.encryptionKey);
  }

  getConnection(realmId: string): StoredConnection | null {
    const row = this.db
      .prepare<{ realmId: string }, ConnectionRow>(
        "SELECT * FROM connections WHERE realm_id = @realmId"
      )
      .get({ realmId });
    if (!row) return null;
    return {
      realmId: row.realm_id,
      environment: row.environment,
      companyName: row.company_name,
      createdAt: row.created_at,
      updatedAt: row.updated_at
    };
  }

  cacheAccessToken(realmId: string, accessToken: string, expiresInSeconds: number): void {
    // Refresh 60s before actual expiry so a request in flight doesn't race
    // the token's real deadline.
    const safetyMarginMs = 60_000;
    this.accessTokenCache.set(realmId, {
      value: accessToken,
      expiresAt: Date.now() + expiresInSeconds * 1000 - safetyMarginMs
    });
  }

  getCachedAccessToken(realmId: string): string | null {
    const cached = this.accessTokenCache.get(realmId);
    if (!cached) return null;
    if (Date.now() >= cached.expiresAt) {
      this.accessTokenCache.delete(realmId);
      return null;
    }
    return cached.value;
  }

  /** Serializes refresh attempts per realm — see the class doc comment. */
  async withRefreshLock<T>(realmId: string, work: () => Promise<T>): Promise<T> {
    const previous = this.refreshLocks.get(realmId) ?? Promise.resolve();
    const current = previous.then(work, work);
    // Store a settle-agnostic promise so a failed refresh doesn't wedge the
    // lock for subsequent attempts.
    this.refreshLocks.set(
      realmId,
      current.catch(() => undefined)
    );
    return current;
  }

  recordHealthCheck(realmId: string, status: string, at: string): void {
    this.db
      .prepare(
        "UPDATE connections SET last_health_check_at = @at, last_health_check_status = @status WHERE realm_id = @realmId"
      )
      .run({ realmId, status, at });
  }
}
