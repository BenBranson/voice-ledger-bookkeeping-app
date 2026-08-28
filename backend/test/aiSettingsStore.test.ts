import { describe, it, expect, beforeEach, afterEach } from "vitest";
import { unlinkSync, existsSync } from "node:fs";
import { openDatabase } from "../src/db/sqlite.js";
import { AISettingsStore } from "../src/ai/aiSettingsStore.js";
import type Database from "better-sqlite3";

const TEST_DB_PATH = "./test/.tmp/ai-settings-test.sqlite";

describe("AISettingsStore", () => {
  let db: Database.Database;
  let store: AISettingsStore;

  beforeEach(() => {
    db = openDatabase(TEST_DB_PATH);
    store = new AISettingsStore(db);
  });

  afterEach(() => {
    db.close();
    for (const suffix of ["", "-wal", "-shm"]) {
      const path = TEST_DB_PATH + suffix;
      if (existsSync(path)) unlinkSync(path);
    }
  });

  it("defaults to enabled with no row present — a fresh install is not silently off", () => {
    expect(store.isEnabled()).toBe(true);
  });

  it("setEnabled(false) then isEnabled() reflects it", () => {
    store.setEnabled(false);
    expect(store.isEnabled()).toBe(false);
  });

  it("setEnabled is idempotent across repeated calls — no duplicate rows, no crash", () => {
    store.setEnabled(false);
    store.setEnabled(true);
    store.setEnabled(false);
    expect(store.isEnabled()).toBe(false);
    const rowCount = (db.prepare("SELECT COUNT(*) as n FROM ai_settings").get() as { n: number }).n;
    expect(rowCount).toBe(1);
  });
});
