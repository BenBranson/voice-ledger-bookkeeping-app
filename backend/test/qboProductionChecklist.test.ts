import { describe, it, expect, beforeEach, afterEach } from "vitest";
import { unlinkSync, existsSync } from "node:fs";
import { randomBytes } from "node:crypto";
import type { AddressInfo } from "node:net";
import type { Server } from "node:http";
import express from "express";
import type Database from "better-sqlite3";
import { openDatabase } from "../src/db/sqlite.js";
import { TokenStore } from "../src/auth/tokenStore.js";
import { SessionStore } from "../src/auth/session.js";
import { QBOClient } from "../src/qbo/client.js";
import { connectionsRoutes } from "../src/routes/connections.js";
import { requireSession } from "../src/middleware/requireSession.js";
import type { QBOCredentials } from "../src/config.js";

const TEST_DB_PATH = "./test/.tmp/qbo-checklist-test.sqlite";
const credentials: QBOCredentials = {
  environment: "sandbox",
  clientId: "test-client",
  clientSecret: "test-secret",
  redirectUri: "http://localhost/callback",
  minorVersion: 75
};

describe("QBO production checklist", () => {
  let db: Database.Database;
  let tokenStore: TokenStore;
  let sessionStore: SessionStore;

  beforeEach(() => {
    db = openDatabase(TEST_DB_PATH);
    const key = randomBytes(32);
    tokenStore = new TokenStore(db, key);
    sessionStore = new SessionStore(db, key);
    tokenStore.saveRefreshToken("realm-a", "sandbox", "A Co", "refresh-a", 8_640_000);
    tokenStore.saveRefreshToken("realm-b", "sandbox", "B Co", "refresh-b", 8_640_000);
    tokenStore.cacheAccessToken("realm-a", "access-a", 3600);
  });

  afterEach(() => {
    db.close();
    for (const suffix of ["", "-wal", "-shm"]) {
      if (existsSync(TEST_DB_PATH + suffix)) unlinkSync(TEST_DB_PATH + suffix);
    }
  });

  describe("429 backoff", () => {
    it("retries a 429 with backoff and returns the eventual success", async () => {
      const statuses = [429, 429, 200];
      const sleeps: number[] = [];
      const fakeFetch = (async () =>
        new Response(JSON.stringify({ ok: true }), { status: statuses.shift()! })) as typeof fetch;
      const client = new QBOClient(credentials, tokenStore, fakeFetch, async (ms) => { sleeps.push(ms); });

      await expect(client.get("realm-a", "companyinfo/realm-a")).resolves.toEqual({ ok: true });
      expect(sleeps).toHaveLength(2);
      expect(sleeps[1]!).toBeGreaterThan(sleeps[0]!);
    });

    it("honors Retry-After", async () => {
      const responses = [
        new Response("", { status: 429, headers: { "Retry-After": "7" } }),
        new Response("{}", { status: 200 })
      ];
      const sleeps: number[] = [];
      const client = new QBOClient(credentials, tokenStore, (async () => responses.shift()!) as typeof fetch, async (ms) => { sleeps.push(ms); });
      await client.get("realm-a", "x");
      expect(sleeps).toEqual([7000]);
    });

    it("gives up with a 429 error after the retry budget", async () => {
      let calls = 0;
      const client = new QBOClient(credentials, tokenStore, (async () => { calls++; return new Response("", { status: 429 }); }) as typeof fetch, async () => {});
      await expect(client.get("realm-a", "x")).rejects.toMatchObject({ httpStatus: 429 });
      expect(calls).toBe(5);
    });
  });

  describe("concurrency", () => {
    it("never runs more than 10 requests at once for one realm", async () => {
      let inFlight = 0;
      let peak = 0;
      const fakeFetch = (async () => {
        inFlight++;
        peak = Math.max(peak, inFlight);
        await new Promise((r) => setTimeout(r, 5));
        inFlight--;
        return new Response("{}", { status: 200 });
      }) as typeof fetch;
      const client = new QBOClient(credentials, tokenStore, fakeFetch);
      await Promise.all(Array.from({ length: 25 }, () => client.get("realm-a", "x")));
      expect(peak).toBe(10);
    });
  });

  describe("disconnect", () => {
    let server: Server;
    let baseUrl: string;
    let revoked: string[];
    let revokeShouldFail: boolean;

    beforeEach(async () => {
      revoked = [];
      revokeShouldFail = false;
      const app = express();
      app.use(express.json());
      app.use(connectionsRoutes(tokenStore, sessionStore, requireSession(sessionStore), credentials, async (_c, token) => {
        if (revokeShouldFail) throw new Error("intuit down");
        revoked.push(token);
      }));
      server = app.listen(0);
      await new Promise((r) => server.once("listening", r));
      baseUrl = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
    });

    afterEach(() => new Promise<void>((r) => server.close(() => r())));

    const disconnect = (realmId: string, session: string) =>
      fetch(`${baseUrl}/realms/${realmId}/disconnect`, { method: "POST", headers: { Authorization: `Bearer ${session}` } });

    it("revokes at Intuit, deletes tokens and sessions, and leaves other realms alone", async () => {
      const session = sessionStore.create("realm-a");
      const response = await disconnect("realm-a", session);
      expect(response.status).toBe(200);
      expect(await response.json()).toEqual({ realmId: "realm-a", revokedAtIntuit: true, localTokensDeleted: true });
      expect(revoked).toEqual(["refresh-a"]);
      expect(tokenStore.getRefreshToken("realm-a")).toBeNull();
      expect(tokenStore.getCachedAccessToken("realm-a")).toBeNull();
      expect(sessionStore.validate(session)).toBeNull();
      expect(tokenStore.getRefreshToken("realm-b")).toBe("refresh-b");
    });

    it("refuses to disconnect a realm the session isn't bound to", async () => {
      const session = sessionStore.create("realm-a");
      const response = await disconnect("realm-b", session);
      expect(response.status).toBe(403);
      expect(tokenStore.getRefreshToken("realm-b")).toBe("refresh-b");
    });

    it("still deletes local tokens when Intuit's revoke fails, and says so", async () => {
      revokeShouldFail = true;
      const response = await disconnect("realm-a", sessionStore.create("realm-a"));
      expect(await response.json()).toMatchObject({ revokedAtIntuit: false, localTokensDeleted: true });
      expect(tokenStore.getRefreshToken("realm-a")).toBeNull();
    });
  });
});

