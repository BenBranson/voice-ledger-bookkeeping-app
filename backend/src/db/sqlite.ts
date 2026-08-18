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

export function openDatabase(sqlitePath: string): Database.Database {
  mkdirSync(dirname(sqlitePath), { recursive: true });
  const db = new Database(sqlitePath);
  db.pragma("journal_mode = WAL");
  migrate(db);
  return db;
}

function migrate(db: Database.Database): void {
  db.exec(`
    -- Access tokens are NOT persisted here, deliberately — per
    -- docs/phase-0/03_SECURITY_THREAT_MODEL.md §3.2, they live in backend
    -- memory only, TTL-bounded (see auth/tokenStore.ts's in-process cache).
    -- Only the long-lived refresh token is durable, and only encrypted.
    CREATE TABLE IF NOT EXISTS connections (
      realm_id TEXT PRIMARY KEY,
      environment TEXT NOT NULL CHECK (environment IN ('sandbox', 'production')),
      company_name TEXT,
      refresh_token_iv TEXT NOT NULL,
      refresh_token_auth_tag TEXT NOT NULL,
      refresh_token_ciphertext TEXT NOT NULL,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      last_health_check_at TEXT,
      last_health_check_status TEXT,
      write_enabled INTEGER NOT NULL DEFAULT 0
    );

    CREATE TABLE IF NOT EXISTS sessions (
      token_hash TEXT PRIMARY KEY,
      realm_id TEXT NOT NULL,
      created_at TEXT NOT NULL,
      expires_at TEXT NOT NULL,
      FOREIGN KEY (realm_id) REFERENCES connections(realm_id)
    );

    CREATE INDEX IF NOT EXISTS idx_sessions_realm ON sessions(realm_id);
  `);

  // `CREATE TABLE IF NOT EXISTS` above only defines the shape for a FRESH
  // database — an existing `connections` table (every realm connected
  // before this column was added) needs an explicit ALTER. SQLite has no
  // `ADD COLUMN IF NOT EXISTS`, so check `table_info` first rather than
  // risking a "duplicate column" error on a database that already has it.
  const existingColumns = db.prepare("PRAGMA table_info(connections)").all() as { name: string }[];
  if (!existingColumns.some((col) => col.name === "write_enabled")) {
    // Every realm defaults to read-only (CLAUDE.md rule 4: "Every new
    // client connection starts in Read-Only Mode") — the DEFAULT 0 on a
    // fresh table and this explicit backfill for existing rows both say
    // the same thing the same way.
    db.exec("ALTER TABLE connections ADD COLUMN write_enabled INTEGER NOT NULL DEFAULT 0");
  }
}
