/**
 * docs/phase-0/12_TEST_STRATEGY.md §12.5: "the matrix is generated from test
 * results. It is not hand-edited."
 *
 * This script is the mechanical half of that promise: it reads every
 * spike/fixtures/results-*.json, keeps the LATEST result per matrixRow (by
 * verifiedAt), and writes docs/phase-0/VERIFICATION_LEDGER.json — the
 * canonical, generated record of what has actually been verified.
 *
 * Coverage mapping (matrixRow -> which summary-table row IDs it verifies,
 * and whether fully or partially) is declared explicitly below rather than
 * inferred, because several fixture rows verify only PART of a table row's
 * claim (e.g. row 3.1 covers 8 transaction types; the spike only exercised
 * Purchase). An honest partial-coverage note is safer than a bare VERIFIED
 * that overclaims. This mapping is reviewable code, not prose typed into
 * the matrix by feel — the actual status/date/evidence text is 100% pulled
 * from the fixture JSON, never hand-typed.
 *
 * docs/phase-0/02_QBO_CAPABILITY_MATRIX.md itself is patched by a human
 * (me) reading this ledger and applying the exact status/date/evidence it
 * contains — the ledger is what "generated" refers to; the surrounding
 * ~650 lines of architectural prose are not regenerated from scratch, only
 * the ASSUMED/VERIFIED/DISPROVEN markers are.
 */

import { readdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";

interface FixtureResult {
  matrixRow: string;
  claim: string;
  status: "VERIFIED" | "DISPROVEN" | "SKIPPED_NO_SANDBOX";
  verifiedAt: string | null;
  detail: string;
}

interface RowCoverage {
  rowId: string;
  coverage: "full" | "partial";
  note?: string;
}

interface MappingEntry {
  matrixRowKey: string; // exact string used in capabilityTest() calls
  rows: RowCoverage[]; // summary-table row IDs this result speaks to
  isNewRow?: { id: string; page: string; capability: string; endpoint: string };
}

// The coverage mapping. See file header for why this is explicit rather
// than inferred.
const MAPPING: MappingEntry[] = [
  { matrixRowKey: "C1", rows: [{ rowId: "C1", coverage: "full" }] },
  { matrixRowKey: "C3 / 2.1", rows: [{ rowId: "C3", coverage: "full" }] },
  {
    matrixRowKey: "C5",
    rows: [
      {
        rowId: "C5",
        coverage: "partial",
        note: "endpoint + near-term (1hr) window confirmed reachable and correctly shaped; the 30-day lookback boundary and tombstone shape were NOT tested (require real elapsed calendar time) and remain ASSUMED"
      }
    ]
  },
  { matrixRowKey: "1.2 / 6.1", rows: [{ rowId: "1.2", coverage: "full" }, { rowId: "6.1", coverage: "full" }] },
  {
    matrixRowKey: "3.1 (subset) / 4.1",
    rows: [
      {
        rowId: "3.1",
        coverage: "partial",
        note: "verified for Purchase only, of the TXN ×8 profile this row covers (Bill, BillPayment, JournalEntry, Deposit, Transfer, Payment, Invoice remain ASSUMED)"
      },
      {
        rowId: "4.1",
        coverage: "partial",
        note: "verified for Purchase only, of the TXN ×4 profile this row covers"
      }
    ]
  },
  {
    matrixRowKey: "§2.6 (pagination offset integrity)",
    rows: [] // prose-section finding, not a table row — handled separately in the write-up
  },
  { matrixRowKey: "§2.6 (pagination checksum)", rows: [] },
  { matrixRowKey: "§2.5", rows: [] },
  {
    matrixRowKey: "1.3 / 8.1-8.3 / 12.1-12.4",
    rows: [
      { rowId: "1.3", coverage: "full" },
      { rowId: "8.1", coverage: "full" },
      { rowId: "8.2", coverage: "full" },
      { rowId: "8.3", coverage: "full" },
      { rowId: "3.2", coverage: "full" }, // TransactionList, tested as part of the same 5-report sweep
      { rowId: "12.1", coverage: "full" },
      { rowId: "12.2", coverage: "full" }
      // 12.3 (CashFlow) and 12.4 (Aged*) NOT in this test's REPORTS list — left untouched.
    ]
  },
  {
    matrixRowKey: "11.x (slice gate)",
    rows: [],
    isNewRow: {
      id: "11.x",
      page: "11 / slice gate",
      capability: "Void a Purchase (`?operation=void`)",
      endpoint: "`Purchase`"
    }
  },

  // --- Wave 3 (writes) + Decision 3's void-on-other-entities tests, 2026-08-16 ---
  { matrixRowKey: "6.2", rows: [{ rowId: "6.2", coverage: "full" }] },
  { matrixRowKey: "6.3", rows: [{ rowId: "6.3", coverage: "full" }] },
  {
    matrixRowKey: "6.4 (zero balance)",
    rows: [{ rowId: "6.4", coverage: "partial", note: "zero-balance case verified; see also the non-zero-balance result from the same session, both folded into this row's detail card" }]
  },
  {
    matrixRowKey: "6.4 (non-zero balance)",
    rows: [{ rowId: "6.4", coverage: "partial", note: "non-zero-balance case verified — deactivate succeeded, no error, no adjusting JournalEntry found, account's own CurrentBalance reports 0 afterward, but the original posted Purchase transactions remain unchanged and still reference the (renamed, inactive) account" }]
  },
  { matrixRowKey: "7.1", rows: [{ rowId: "7.1", coverage: "full" }] },
  { matrixRowKey: "7.2", rows: [{ rowId: "7.2", coverage: "full" }] },
  { matrixRowKey: "C6", rows: [{ rowId: "C6", coverage: "full" }] },
  {
    matrixRowKey: "C7",
    rows: [{ rowId: "C7", coverage: "partial", note: "JSON-metadata Attachable creation + entity linkage verified; binary file upload via the multipart endpoint NOT tested" }]
  },
  { matrixRowKey: "8.4", rows: [{ rowId: "8.4", coverage: "full" }] },
  { matrixRowKey: "8.6", rows: [{ rowId: "8.6", coverage: "full" }] },
  {
    matrixRowKey: "11.x (Bill)",
    rows: [],
    isNewRow: { id: "11.x-bill", page: "11 / slice gate (Decision 3)", capability: "Void a Bill (`?operation=void`)", endpoint: "`Bill`" }
  },
  {
    matrixRowKey: "11.x (JournalEntry)",
    rows: [],
    isNewRow: { id: "11.x-je", page: "11 / slice gate (Decision 3)", capability: "Void a JournalEntry (`?operation=void`)", endpoint: "`JournalEntry`" }
  },
  {
    matrixRowKey: "11.x (BillPayment)",
    rows: [],
    isNewRow: { id: "11.x-bp", page: "11 / slice gate (Decision 3)", capability: "Void a BillPayment (`?operation=void`)", endpoint: "`BillPayment`" }
  },

  // --- Wave 5, items 49-50, run 2026-08-17 ---
  {
    matrixRowKey: "testCategorizationProvenance",
    rows: [],
    isNewRow: {
      id: "13.1",
      page: "Backlog — Cleanup Assessment",
      capability: "QBO's rule-vs-AI-vs-human categorization source, exposed via any read API",
      endpoint: "`Purchase` query, `cdc`, `reports/TransactionList`"
    }
  },
  {
    matrixRowKey: "testReconciledTransactionDetection",
    rows: [],
    isNewRow: {
      id: "13.2",
      page: "Backlog — sensitive-write preflight risk tiers",
      capability: "Whether a transaction is already reconciled, exposed via any read API",
      endpoint: "`Purchase` query, `cdc`, `reports/TransactionList`"
    }
  }
];

function loadLatestResultsPerRow(): Map<string, FixtureResult> {
  const fixturesDir = join(process.cwd(), "spike", "fixtures");
  const files = readdirSync(fixturesDir).filter((f) => f.startsWith("results-") && f.endsWith(".json"));
  const latest = new Map<string, FixtureResult>();

  for (const file of files) {
    const results = JSON.parse(readFileSync(join(fixturesDir, file), "utf8")) as FixtureResult[];
    for (const r of results) {
      if (r.status === "SKIPPED_NO_SANDBOX") continue;
      const existing = latest.get(r.matrixRow);
      if (!existing || (r.verifiedAt && (!existing.verifiedAt || r.verifiedAt > existing.verifiedAt))) {
        latest.set(r.matrixRow, r);
      }
    }
  }
  return latest;
}

function main(): void {
  const latestByFixtureRow = loadLatestResultsPerRow();
  const ledger: Array<{
    tableRowId: string;
    status: "VERIFIED" | "DISPROVEN";
    coverage: "full" | "partial";
    verifiedAt: string;
    sourceMatrixRowKey: string;
    detail: string;
    note?: string;
    isNewRow?: MappingEntry["isNewRow"];
  }> = [];

  for (const entry of MAPPING) {
    const result = latestByFixtureRow.get(entry.matrixRowKey);
    if (!result || !result.verifiedAt) continue;

    if (entry.isNewRow) {
      ledger.push({
        tableRowId: entry.isNewRow.id,
        status: result.status === "DISPROVEN" ? "DISPROVEN" : "VERIFIED",
        coverage: "full",
        verifiedAt: result.verifiedAt,
        sourceMatrixRowKey: entry.matrixRowKey,
        detail: result.detail,
        isNewRow: entry.isNewRow
      });
      continue;
    }

    for (const row of entry.rows) {
      ledger.push({
        tableRowId: row.rowId,
        status: result.status === "DISPROVEN" ? "DISPROVEN" : "VERIFIED",
        coverage: row.coverage,
        verifiedAt: result.verifiedAt,
        sourceMatrixRowKey: entry.matrixRowKey,
        detail: result.detail,
        ...(row.note ? { note: row.note } : {})
      });
    }
  }

  // Also surface the prose-section findings (not table rows) for the
  // write-up to consume.
  const proseFindings = ["§2.6 (pagination offset integrity)", "§2.6 (pagination checksum)", "§2.5", "§10.5 (idempotency)"]
    .map((key) => latestByFixtureRow.get(key))
    .filter((r): r is FixtureResult => !!r);

  const outPath = join(process.cwd(), "..", "docs", "phase-0", "VERIFICATION_LEDGER.json");
  writeFileSync(
    outPath,
    JSON.stringify(
      {
        generatedAt: new Date().toISOString(),
        generatedBy: "backend/spike/regenerateMatrix.ts — see file header for the coverage-mapping methodology",
        tableRowUpdates: ledger,
        proseSectionFindings: proseFindings
      },
      null,
      2
    )
  );

  process.stdout.write(`Ledger written to ${outPath}\n`);
  process.stdout.write(`Table row updates: ${ledger.length}\n`);
  process.stdout.write(`Prose-section findings: ${proseFindings.length}\n`);
}

main();
