/**
 * Local encrypted-at-rest storage for refresh tokens and app sessions.
 *
 * Deliberately simple for Phase 1 step 1.2 — a single SQLite file, not a
 * managed database. This is an explicit, temporary scope decision, not an
 * oversight: this step is sandbox-only, single-operator, tens of clients at
 * most (docs/phase-0/OPEN_QUESTIONS.md Q6). A managed Postgres instance (or
 * a Render persistent disk, since Render's default filesystem is ephemeral
 * across deploys) becomes worth provisioning once this moves past sandbox
 * testing — see backend/README.md.
 *
 * Refresh token VALUES are encrypted before they ever reach this file
 * (auth/tokenStore.ts calls crypto.ts first) — this module never sees or
 * stores plaintext tokens.
 */

import Database from "better-sqlite3";
import { mkdirSync } from "node:fs";
import { dirname } from "node:path";
import type { RealmCipher } from "../auth/realmCipher.js";

export function openDatabase(sqlitePath: string): Database.Database {
  mkdirSync(dirname(sqlitePath), { recursive: true });
  const db = new Database(sqlitePath);
  db.pragma("journal_mode = WAL");
  migrate(db);
  return db;
}

const REALM_ENCRYPTED_SCHEMA = `
    -- Access tokens are NOT persisted here, deliberately — per
    -- docs/phase-0/03_SECURITY_THREAT_MODEL.md §3.2, they live in backend
    -- memory only, TTL-bounded (see auth/tokenStore.ts's in-process cache).
    -- Only the long-lived refresh token is durable, and only encrypted.
    -- The realm ID itself is encrypted too; realm_key is a keyed HMAC of
    -- it (auth/realmCipher.ts) used only for exact lookup.
    CREATE TABLE IF NOT EXISTS connections (
      realm_key TEXT PRIMARY KEY,
      realm_id_iv TEXT NOT NULL,
      realm_id_auth_tag TEXT NOT NULL,
      realm_id_ciphertext TEXT NOT NULL,
      environment TEXT NOT NULL CHECK (environment IN ('sandbox', 'production')),
      company_name TEXT,
      refresh_token_iv TEXT NOT NULL,
      refresh_token_auth_tag TEXT NOT NULL,
      refresh_token_ciphertext TEXT NOT NULL,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      last_health_check_at TEXT,
      last_health_check_status TEXT,
      write_enabled INTEGER NOT NULL DEFAULT 0,
      refresh_token_expires_at TEXT
    );

    CREATE TABLE IF NOT EXISTS sessions (
      token_hash TEXT PRIMARY KEY,
      realm_key TEXT NOT NULL,
      created_at TEXT NOT NULL,
      expires_at TEXT NOT NULL,
      FOREIGN KEY (realm_key) REFERENCES connections(realm_key)
    );

    CREATE INDEX IF NOT EXISTS idx_sessions_realm_key ON sessions(realm_key);
`;

function columnNames(db: Database.Database, table: string): string[] {
  return (db.prepare(`PRAGMA table_info(${table})`).all() as { name: string }[]).map((col) => col.name);
}

/** True for a database written before realm IDs were encrypted. */
export function hasPlaintextRealmSchema(db: Database.Database): boolean {
  return columnNames(db, "connections").includes("realm_id");
}

function migrate(db: Database.Database): void {
  const connectionColumns = columnNames(db, "connections");
  if (connectionColumns.length === 0) {
    db.exec(REALM_ENCRYPTED_SCHEMA);
  } else if (connectionColumns.includes("realm_id")) {
    // Pre-encryption layout; converted by migrateRealmEncryption once a
    // key is available (TokenStore/SessionStore constructors).
    if (!connectionColumns.includes("write_enabled")) {
      db.exec("ALTER TABLE connections ADD COLUMN write_enabled INTEGER NOT NULL DEFAULT 0");
    }
    if (!connectionColumns.includes("refresh_token_expires_at")) {
      db.exec("ALTER TABLE connections ADD COLUMN refresh_token_expires_at TEXT");
    }
  }

  db.exec(`
    -- docs/VOICE_LEDGER_SPEC.md's AI kill switch: "a single toggle that
    -- disables all AI features app-wide." App-wide, not per-realm, on
    -- purpose (spec: "One app-level connection, unlike QBO's per-company
    -- model") -- a single-row table rather than a column on connections,
    -- so it doesn't imply per-client scoping it doesn't have.
    CREATE TABLE IF NOT EXISTS ai_settings (
      id INTEGER PRIMARY KEY CHECK (id = 1),
      enabled INTEGER NOT NULL DEFAULT 1
    );
  `);
}

interface LegacyConnectionRow {
  realm_id: string;
  environment: string;
  company_name: string | null;
  refresh_token_iv: string;
  refresh_token_auth_tag: string;
  refresh_token_ciphertext: string;
  created_at: string;
  updated_at: string;
  last_health_check_at: string | null;
  last_health_check_status: string | null;
  write_enabled: number;
  refresh_token_expires_at: string | null;
}

/** One-time, atomic conversion of a plaintext-realm database. Idempotent. */
export function migrateRealmEncryption(db: Database.Database, cipher: RealmCipher): void {
  if (!hasPlaintextRealmSchema(db)) return;
  db.transaction(() => {
    const connections = db.prepare("SELECT * FROM connections").all() as LegacyConnectionRow[];
    const sessions = db.prepare("SELECT token_hash, realm_id, created_at, expires_at FROM sessions").all() as
      { token_hash: string; realm_id: string; created_at: string; expires_at: string }[];
    db.exec("DROP INDEX IF EXISTS idx_sessions_realm; DROP TABLE sessions; DROP TABLE connections;");
    db.exec(REALM_ENCRYPTED_SCHEMA);
    const insertConnection = db.prepare(
      `INSERT INTO connections (realm_key, realm_id_iv, realm_id_auth_tag, realm_id_ciphertext, environment, company_name,
         refresh_token_iv, refresh_token_auth_tag, refresh_token_ciphertext, created_at, updated_at,
         last_health_check_at, last_health_check_status, write_enabled, refresh_token_expires_at)
       VALUES (@realmKey, @iv, @authTag, @ciphertext, @environment, @companyName, @refreshIv, @refreshAuthTag, @refreshCiphertext,
         @createdAt, @updatedAt, @lastHealthCheckAt, @lastHealthCheckStatus, @writeEnabled, @refreshTokenExpiresAt)`
    );
    for (const row of connections) {
      const sealed = cipher.seal(row.realm_id);
      insertConnection.run({
        realmKey: cipher.lookupKey(row.realm_id),
        iv: sealed.iv,
        authTag: sealed.authTag,
        ciphertext: sealed.ciphertext,
        environment: row.environment,
        companyName: row.company_name,
        refreshIv: row.refresh_token_iv,
        refreshAuthTag: row.refresh_token_auth_tag,
        refreshCiphertext: row.refresh_token_ciphertext,
        createdAt: row.created_at,
        updatedAt: row.updated_at,
        lastHealthCheckAt: row.last_health_check_at,
        lastHealthCheckStatus: row.last_health_check_status,
        writeEnabled: row.write_enabled,
        refreshTokenExpiresAt: row.refresh_token_expires_at
      });
    }
    const insertSession = db.prepare(
      "INSERT INTO sessions (token_hash, realm_key, created_at, expires_at) VALUES (@tokenHash, @realmKey, @createdAt, @expiresAt)"
    );
    const knownRealms = new Set(connections.map((row) => row.realm_id));
    for (const row of sessions) {
      if (!knownRealms.has(row.realm_id)) continue;
      insertSession.run({ tokenHash: row.token_hash, realmKey: cipher.lookupKey(row.realm_id), createdAt: row.created_at, expiresAt: row.expires_at });
    }
  })();
}
