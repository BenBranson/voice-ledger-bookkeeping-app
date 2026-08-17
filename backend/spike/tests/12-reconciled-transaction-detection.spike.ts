/**
 * docs/phase-0/SPIKE_QUEUE.md Wave 5, item 50 — `testReconciledTransactionDetection`.
 * Source: docs/backlog/REDDIT_FEEDBACK_ASSESSMENT.md item 6 (sensitive-write
 * preflight risk tiers) — can we tell from the API whether a transaction has
 * already been reconciled? A write against an already-reconciled transaction
 * breaks that reconciliation, and §10.3's five preflight checks don't
 * currently check for this.
 *
 * Note: 02-entity-reads.spike.ts already found no "cleared" field on
 * Purchase specifically (matrix row 3.1/4.1's detail card). This test
 * broadens that check deliberately — across the full raw JSON (not just a
 * `cleared` substring), across CDC, and across the TransactionList report's
 * columns — since "reconciled" status could plausibly live under a
 * differently-named field even if `Cleared` itself is absent.
 */

import { capabilityTest, confirmedAbsent, pass } from "../capabilityTest.js";
import { QboRawClient } from "../qboRawClient.js";

const CANDIDATE_FIELD_NAMES = [
  "Cleared",
  "cleared",
  "Reconciled",
  "ReconcileStatus",
  "ReconciliationStatus",
  "BankReconciliationStatus",
  "ClearedStatus",
  "TxnStatus"
];

function collectAllKeys(obj: unknown, keys: Set<string> = new Set()): Set<string> {
  if (obj === null || typeof obj !== "object") return keys;
  for (const [k, v] of Object.entries(obj as Record<string, unknown>)) {
    keys.add(k);
    if (v && typeof v === "object") collectAllKeys(v, keys);
  }
  return keys;
}

export async function run(): Promise<void> {
  await capabilityTest(
    "testReconciledTransactionDetection",
    "Can the API tell us whether a transaction has already been reconciled?",
    async (capture) => {
      const client = new QboRawClient();

      const queryResult = await client.query("select * from Purchase MAXRESULTS 10");
      const purchases =
        queryResult.status === 200 ? (queryResult.body as any)?.QueryResponse?.Purchase ?? [] : [];
      const queryKeys = purchases.reduce(
        (acc: Set<string>, p: unknown) => collectAllKeys(p, acc),
        new Set<string>()
      );

      const since = new Date(Date.now() - 30 * 24 * 3600 * 1000).toISOString();
      const cdcResult = await client.get("cdc", { entities: "Purchase", changedSince: since });
      const cdcKeys =
        cdcResult.status === 200
          ? collectAllKeys((cdcResult.body as any)?.CDCResponse ?? {}, new Set<string>())
          : new Set<string>();

      const reportResult = await client.get("reports/TransactionList", {
        start_date: "2026-07-01",
        end_date: "2026-07-31"
      });
      const reportColumns: string[] =
        reportResult.status === 200
          ? ((reportResult.body as any)?.Columns?.Column ?? []).map((c: any) => String(c.ColTitle))
          : [];

      capture(
        { queries: ["select * from Purchase MAXRESULTS 10", "cdc?entities=Purchase", "reports/TransactionList"] },
        { purchaseQueryKeyCount: queryKeys.size, cdcKeyCount: cdcKeys.size, reportColumns }
      );

      const foundInQuery = CANDIDATE_FIELD_NAMES.filter((name) => queryKeys.has(name));
      const foundInCdc = CANDIDATE_FIELD_NAMES.filter((name) => cdcKeys.has(name));
      const foundInReport = CANDIDATE_FIELD_NAMES.filter((name) =>
        reportColumns.some((col) => col.toLowerCase() === name.toLowerCase())
      );

      if (foundInQuery.length || foundInCdc.length || foundInReport.length) {
        return pass(
          `Found candidate reconciliation-status field(s) — query: [${foundInQuery.join(", ")}], ` +
            `CDC: [${foundInCdc.join(", ")}], report: [${foundInReport.join(", ")}]. Needs follow-up to confirm ` +
            `this is populated (none of this project's seed data has ever been through a real QBO reconciliation, ` +
            `so a field that only appears once set could still be missed here).`
        );
      }

      const searched = [
        `Purchase entity query — ${purchases.length} records, ${queryKeys.size} distinct keys observed`,
        `CDC feed for Purchase — ${cdcKeys.size} distinct keys observed`,
        `TransactionList report columns — ${reportColumns.join(", ")}`,
        `Candidate field names checked against all three: ${CANDIDATE_FIELD_NAMES.join(", ")}`,
        `Caveat, recorded rather than hidden: no seed data in this sandbox has ever been through a real ` +
          `Finish Reconciliation in the QBO UI, so this confirms the field doesn't exist in an UNRECONCILED ` +
          `transaction's shape — it does not rule out a field that only appears once a transaction actually ` +
          `is reconciled. That would need a follow-up test against a manually-reconciled account (Wave 4's ` +
          `awkward-setup category, item 44's reconciliation.json fixture already exists for this).`
      ];
      return confirmedAbsent(searched);
    }
  );
}
