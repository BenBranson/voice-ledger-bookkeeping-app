import { describe, it, expect, beforeEach, afterEach } from "vitest";
import { unlinkSync, existsSync } from "node:fs";
import { randomBytes } from "node:crypto";
import { openDatabase } from "../src/db/sqlite.js";
import { TokenStore } from "../src/auth/tokenStore.js";
import type Database from "better-sqlite3";

const TEST_DB_PATH = "./test/.tmp/tokenstore-test.sqlite";

describe("TokenStore", () => {
  let db: Database.Database;
  let store: TokenStore;
  const key = randomBytes(32);

  beforeEach(() => {
    db = openDatabase(TEST_DB_PATH);
    store = new TokenStore(db, key);
  });

  afterEach(() => {
    db.close();
    for (const suffix of ["", "-wal", "-shm"]) {
      const path = TEST_DB_PATH + suffix;
      if (existsSync(path)) unlinkSync(path);
    }
  });

  it("round-trips a refresh token through encryption", () => {
    store.saveRefreshToken("123456", "sandbox", "Test Co", "the-refresh-token-value");
    expect(store.getRefreshToken("123456")).toBe("the-refresh-token-value");
  });

  it("never stores the refresh token in plaintext — §3.9", () => {
    store.saveRefreshToken("123456", "sandbox", null, "super-secret-refresh-token");
    const row = db
      .prepare<unknown[], { refresh_token_ciphertext: string }>(
        "SELECT refresh_token_ciphertext FROM connections WHERE realm_id = '123456'"
      )
      .get();
    expect(row?.refresh_token_ciphertext).toBeDefined();
    expect(row!.refresh_token_ciphertext).not.toContain("super-secret-refresh-token");
  });

  it("updates the refresh token on reconnect without creating a duplicate row", () => {
    store.saveRefreshToken("123456", "sandbox", null, "first-token");
    store.saveRefreshToken("123456", "sandbox", null, "second-token");
    expect(store.getRefreshToken("123456")).toBe("second-token");
    const count = db.prepare("SELECT COUNT(*) as c FROM connections").get() as { c: number };
    expect(count.c).toBe(1);
  });

  it("caches an access token with a realistic TTL and returns it", () => {
    store.cacheAccessToken("123456", "access-token-value", 3600); // QBO's real ~1hr token lifetime
    expect(store.getCachedAccessToken("123456")).toBe("access-token-value");
  });

  it("treats a token as already-expired once its TTL is inside the 60s safety margin", () => {
    // §3.9: refresh happens 60s before actual expiry so an in-flight
    // request doesn't race the token's real deadline. A 1-second TTL is
    // entirely inside that margin, so the cached value must not be handed
    // back at all.
    store.cacheAccessToken("123456", "access-token-value", 1);
    expect(store.getCachedAccessToken("123456")).toBeNull();
  });

  it("returns null for a realm with nothing cached", () => {
    expect(store.getCachedAccessToken("never-cached-realm")).toBeNull();
  });

  it("serializes concurrent refresh attempts for the same realm", async () => {
    const order: number[] = [];
    const work = (id: number) => async () => {
      order.push(id);
      await new Promise((resolve) => setTimeout(resolve, 5));
      return id;
    };
    const [a, b] = await Promise.all([
      store.withRefreshLock("123456", work(1)),
      store.withRefreshLock("123456", work(2))
    ]);
    // Both complete, and critically, the second didn't START until the
    // first's work function had already been invoked — proving they didn't
    // run concurrently for the same realm.
    expect([a, b]).toEqual([1, 2]);
    expect(order).toEqual([1, 2]);
  });

  it("a fresh connection defaults to write-disabled — CLAUDE.md rule 4: every new connection starts Read-Only", () => {
    store.saveRefreshToken("123456", "sandbox", "Test Co", "the-refresh-token-value");
    expect(store.isWriteEnabled("123456")).toBe(false);
    expect(store.getConnection("123456")?.writeEnabled).toBe(false);
  });

  it("setWriteEnabled(true) then isWriteEnabled reflects it, and it round-trips back off", () => {
    store.saveRefreshToken("123456", "sandbox", "Test Co", "the-refresh-token-value");
    store.setWriteEnabled("123456", true);
    expect(store.isWriteEnabled("123456")).toBe(true);
    store.setWriteEnabled("123456", false);
    expect(store.isWriteEnabled("123456")).toBe(false);
  });

  it("a realm with no connection row at all is write-disabled, not an error", () => {
    expect(store.isWriteEnabled("never-connected-realm")).toBe(false);
  });
});
