/**
 * App session issuance and validation.
 *
 * Opaque, random, bearer tokens — not JWTs. A JWT would let a compromised
 * signing key or a parsing bug forge a session; an opaque token looked up
 * against a server-side store cannot be forged no matter what the client
 * sends, only guessed (infeasible at 256 bits) or stolen. Given this
 * backend already needs a database for refresh tokens, the "stateless JWT"
 * benefit doesn't apply here.
 *
 * Only the SHA-256 hash of the token is stored — matches how the refresh
 * token itself is protected (encrypted, never plaintext at rest) in spirit,
 * though a session token additionally doesn't need to be *recoverable*
 * (unlike the refresh token, which must be decrypted to call QBO), so a
 * one-way hash is the right primitive here rather than reversible
 * encryption.
 */

import { randomBytes, createHash, timingSafeEqual } from "node:crypto";
import type Database from "better-sqlite3";
import { logEvent } from "../logging/logger.js";
import { RealmCipher } from "./realmCipher.js";
import { migrateRealmEncryption } from "../db/sqlite.js";

const SESSION_TOKEN_BYTES = 32;
const SESSION_TTL_MS = 12 * 60 * 60 * 1000; // 12 hours — Phase 1 dev-flow value; revisit for real usage patterns

export interface Session {
  readonly realmId: string;
  readonly expiresAt: Date;
}

function hashToken(token: string): string {
  return createHash("sha256").update(token, "utf8").digest("hex");
}

export class SessionStore {
  private readonly realmCipher: RealmCipher;

  constructor(
    private readonly db: Database.Database,
    encryptionKey: Buffer
  ) {
    this.realmCipher = new RealmCipher(encryptionKey);
    migrateRealmEncryption(db, this.realmCipher);
  }

  /**
   * Issues a session bound to exactly one realm.
   * docs/phase-0/03_SECURITY_THREAT_MODEL.md §3.3 item 11: "Refuse any
   * request whose realmId is not bound to the caller's session." This
   * binding is where that starts — a session cannot later be widened to
   * cover a second realm; a new realm means a new session.
   */
  create(realmId: string): string {
    const token = randomBytes(SESSION_TOKEN_BYTES).toString("hex");
    const now = new Date();
    const expiresAt = new Date(now.getTime() + SESSION_TTL_MS);
    this.db
      .prepare(
        "INSERT INTO sessions (token_hash, realm_key, created_at, expires_at) VALUES (@tokenHash, @realmKey, @createdAt, @expiresAt)"
      )
      .run({
        tokenHash: hashToken(token),
        realmKey: this.realmCipher.lookupKey(realmId),
        createdAt: now.toISOString(),
        expiresAt: expiresAt.toISOString()
      });
    logEvent("session_created", { realmId });
    return token;
  }

  /**
   * Validates a bearer token and returns the realm it's bound to, or null.
   * Uses a timing-safe comparison on the stored hash lookup result to avoid
   * a timing side channel on the (already-hashed, already-indexed) value —
   * cheap insurance even though SQLite's lookup itself isn't constant-time.
   */
  validate(token: string): Session | null {
    const tokenHash = hashToken(token);
    const row = this.db
      .prepare<{ tokenHash: string }, { realm_id_iv: string; realm_id_auth_tag: string; realm_id_ciphertext: string; expires_at: string }>(
        `SELECT c.realm_id_iv, c.realm_id_auth_tag, c.realm_id_ciphertext, s.expires_at
         FROM sessions s JOIN connections c ON c.realm_key = s.realm_key
         WHERE s.token_hash = @tokenHash`
      )
      .get({ tokenHash });

    if (!row) {
      logEvent("session_rejected");
      return null;
    }

    const realmId = this.realmCipher.open({ iv: row.realm_id_iv, authTag: row.realm_id_auth_tag, ciphertext: row.realm_id_ciphertext });
    const expiresAt = new Date(row.expires_at);
    if (expiresAt.getTime() <= Date.now()) {
      logEvent("session_rejected", { realmId });
      return null;
    }

    return { realmId, expiresAt };
  }
}

/** Constant-time string comparison, exported for reuse where needed. */
export function constantTimeEquals(a: string, b: string): boolean {
  const bufferA = Buffer.from(a, "utf8");
  const bufferB = Buffer.from(b, "utf8");
  if (bufferA.length !== bufferB.length) return false;
  return timingSafeEqual(bufferA, bufferB);
}
