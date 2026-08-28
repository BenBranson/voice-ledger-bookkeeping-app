import type Database from "better-sqlite3";

/**
 * The AI kill switch's storage — app-wide (see `db/sqlite.ts`'s
 * `ai_settings` table comment), not per-realm. Defaults to enabled: a
 * fresh install with no row yet is treated as "on," matching every other
 * feature in this app (nothing requires an explicit opt-in to work).
 */
export class AISettingsStore {
  constructor(private readonly db: Database.Database) {}

  isEnabled(): boolean {
    const row = this.db.prepare<[], { enabled: number }>("SELECT enabled FROM ai_settings WHERE id = 1").get();
    return row ? row.enabled === 1 : true;
  }

  setEnabled(enabled: boolean): void {
    this.db
      .prepare(
        `INSERT INTO ai_settings (id, enabled) VALUES (1, @value)
         ON CONFLICT(id) DO UPDATE SET enabled = @value`
      )
      .run({ value: enabled ? 1 : 0 });
  }
}
