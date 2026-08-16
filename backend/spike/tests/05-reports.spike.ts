/**
 * docs/phase-0/SPIKE_QUEUE.md Wave 1, item 11.
 */

import { capabilityTest, pass, fail } from "../capabilityTest.js";
import { QboRawClient } from "../qboRawClient.js";

const REPORTS = ["BalanceSheet", "ProfitAndLoss", "TrialBalance", "GeneralLedger", "TransactionList"] as const;

export async function run(): Promise<void> {
  await capabilityTest(
    "1.3 / 8.1-8.3 / 12.1-12.4",
    "Baseline reports (BS, P&L, TB, GL, Transaction List) all read successfully with column metadata bindable by ColTitle/ColType",
    async (capture) => {
      const client = new QboRawClient();
      const results: Record<string, { status: number; hasColumns: boolean; columnKeys: string[]; hasRows: boolean }> = {};
      const rawBodies: Record<string, unknown> = {};

      for (const report of REPORTS) {
        const r = await client.get(`reports/${report}`, { start_date: "2026-06-01", end_date: "2026-08-16" });
        rawBodies[report] = r.body;
        const columns = (r.body as any)?.Columns?.Column ?? [];
        const columnKeys: string[] = columns.map((c: any) => `${c.ColTitle ?? "(no title)"}:${c.ColType ?? "(no type)"}`);
        const hasRows = Array.isArray((r.body as any)?.Rows?.Row);
        results[report] = { status: r.status, hasColumns: columns.length > 0, columnKeys, hasRows };
      }

      capture({ reports: REPORTS, params: { start_date: "2026-06-01", end_date: "2026-08-16" } }, rawBodies);

      // Non-null assertion is safe here: every key in REPORTS was populated
      // in the loop above before this point.
      const at = (r: (typeof REPORTS)[number]) => results[r]!;

      const failures = REPORTS.filter((r) => at(r).status !== 200);
      const noColumns = REPORTS.filter((r) => at(r).status === 200 && !at(r).hasColumns);
      const noColTitleOrType = REPORTS.filter(
        (r) => at(r).status === 200 && at(r).columnKeys.some((k) => k.includes("(no title)") || k.includes("(no type)"))
      );

      const detail =
        REPORTS.map((r) => `${r}: HTTP ${at(r).status}, ${at(r).columnKeys.length} columns, rows present: ${at(r).hasRows}`).join(" | ") +
        `. ${failures.length ? `⚠ FAILED: ${failures.join(", ")}. ` : ""}` +
        `${noColumns.length ? `⚠ No column metadata at all: ${noColumns.join(", ")}. ` : ""}` +
        `${noColTitleOrType.length ? `⚠ Missing ColTitle or ColType on some columns: ${noColTitleOrType.join(", ")} — binding by metadata (§4.9) would be incomplete for these. ` : ""}` +
        `${!failures.length && !noColumns.length && !noColTitleOrType.length ? "All 5 reports readable with complete ColTitle/ColType metadata on every column — supports §4.9's column-binding-by-metadata design as specified." : ""}`;

      return failures.length || noColumns.length ? fail(detail) : pass(detail);
    }
  );
}
