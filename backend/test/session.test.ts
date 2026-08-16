import { describe, it, expect, beforeEach, afterEach } from "vitest";
import { existsSync, unlinkSync } from "node:fs";
import { randomBytes } from "node:crypto";
import { openDatabase } from "../src/db/sqlite.js";
import { SessionStore } from "../src/auth/session.js";
import { TokenStore } from "../src/auth/tokenStore.js";
import type Database from "better-sqlite3";

const TEST_DB_PATH = "./test/.tmp/session-test.sqlite";

describe("SessionStore", () => {
  let db: Database.Database;
  let store: SessionStore;
  let tokenStore: TokenStore;

  // sessions.realm_id has a FOREIGN KEY on connections.realm_id (by
  // design — a session should never exist for a realm we never connected
  // to). Real usage always creates the connection row first (OAuth
  // callback calls tokenStore.saveRefreshToken before sessionStore.create,
  // see src/routes/oauth.ts) — these tests do the same.
  function seedConnection(realmId: string): void {
    tokenStore.saveRefreshToken(realmId, "sandbox", null, `refresh-token-for-${realmId}`);
  }

  beforeEach(() => {
    db = openDatabase(TEST_DB_PATH);
    store = new SessionStore(db);
    tokenStore = new TokenStore(db, randomBytes(32));
  });

  afterEach(() => {
    db.close();
    for (const suffix of ["", "-wal", "-shm"]) {
      const path = TEST_DB_PATH + suffix;
      if (existsSync(path)) unlinkSync(path);
    }
  });

  it("validates a freshly issued token and returns its bound realm", () => {
    seedConnection("123456789");
    const token = store.create("123456789");
    const session = store.validate(token);
    expect(session?.realmId).toBe("123456789");
  });

  it("rejects an unknown token", () => {
    expect(store.validate("not-a-real-token")).toBeNull();
  });

  it("rejects an expired token — §3.9, §7.4", () => {
    seedConnection("123456789");
    const token = store.create("123456789");
    // Manually backdate the session's expiry to simulate time passing,
    // rather than sleeping in the test.
    db.prepare("UPDATE sessions SET expires_at = @past WHERE token_hash = (SELECT token_hash FROM sessions LIMIT 1)").run({
      past: new Date(Date.now() - 1000).toISOString()
    });
    expect(store.validate(token)).toBeNull();
  });

  it("a token issued for realm A never validates for realm B — it simply names one realm", () => {
    seedConnection("realm-A");
    const tokenForA = store.create("realm-A");
    const session = store.validate(tokenForA);
    expect(session?.realmId).toBe("realm-A");
    expect(session?.realmId).not.toBe("realm-B");
  });
});
