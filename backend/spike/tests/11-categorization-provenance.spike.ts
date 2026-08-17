/**
 * docs/phase-0/SPIKE_QUEUE.md Wave 5, item 49 — `testCategorizationProvenance`.
 * Source: docs/backlog/CLEANUP_MODE.md §2.7 — is QBO's rule-vs-AI-vs-human
 * categorization source exposed via any read API (transaction detail, CDC,
 * or report)? If yes, an enormous cleanup filter ("show me everything QBO
 * guessed with no history"). If no, record the negative — still useful,
 * per this project's standing rule that DISPROVEN is a valid outcome.
 *
 * Checked across three surfaces, not just one, before concluding absence:
 * a plain entity query, the CDC feed (which sometimes carries metadata a
 * plain query doesn't), and a report's column set (TransactionList).
 */

import { capabilityTest, confirmedAbsent, fail, pass } from "../capabilityTest.js";
import { QboRawClient } from "../qboRawClient.js";

// Names a categorization-provenance field would plausibly use, if QBO
// exposed one. Not exhaustive by construction — a genuinely undocumented
// field with a name outside this list could still exist — but this is the
// same "search the obvious candidates, report what was searched" approach
// §12.5's negative-capability tests use elsewhere in this project.
const CANDIDATE_FIELD_NAMES = [
  "Source",
  "TxnSource",
  "CategorizationSource",
  "CreatedBy",
  "CreatedVia",
  "SuggestedBy",
  "AISource",
  "RuleSource",
  "BankRuleId",
  "MatchedRuleId",
  "AutoCategorized",
  "IsAiSuggested"
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
    "testCategorizationProvenance",
    "Is QBO's rule-vs-AI-vs-human categorization source exposed via any read API?",
    async (capture) => {
      const client = new QboRawClient();

      const queryResult = await client.query("select * from Purchase MAXRESULTS 10");
      if (queryResult.status !== 200) return fail(`Purchase query failed: HTTP ${queryResult.status}`);
      const purchases = (queryResult.body as any)?.QueryResponse?.Purchase ?? [];
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
        {
          purchaseQueryKeyCount: queryKeys.size,
          cdcKeyCount: cdcKeys.size,
          reportColumns
        }
      );

      const foundInQuery = CANDIDATE_FIELD_NAMES.filter((name) => queryKeys.has(name));
      const foundInCdc = CANDIDATE_FIELD_NAMES.filter((name) => cdcKeys.has(name));
      const foundInReport = CANDIDATE_FIELD_NAMES.filter((name) =>
        reportColumns.some((col) => col.toLowerCase() === name.toLowerCase())
      );

      if (foundInQuery.length || foundInCdc.length || foundInReport.length) {
        return pass(
          `Found candidate provenance field(s) — query: [${foundInQuery.join(", ")}], ` +
            `CDC: [${foundInCdc.join(", ")}], report: [${foundInReport.join(", ")}]. Needs follow-up to confirm meaning.`
        );
      }

      const searched = [
        `Purchase entity query — ${purchases.length} records, ${queryKeys.size} distinct keys observed (full raw JSON checked, not just top level)`,
        `CDC feed for Purchase — ${cdcKeys.size} distinct keys observed`,
        `TransactionList report columns — ${reportColumns.join(", ")}`,
        `Candidate field names checked against all three: ${CANDIDATE_FIELD_NAMES.join(", ")}`
      ];
      return confirmedAbsent(searched);
    }
  );
}
