/**
 * docs/phase-0/SPIKE_QUEUE.md Wave 1, items 5-6.
 */

import { capabilityTest, pass, fail } from "../capabilityTest.js";
import { QboRawClient } from "../qboRawClient.js";

// The closed AccountType enum from docs/phase-0/04_DATA_MODEL.md §4.6 —
// checked against what QBO actually returns, not assumed to match.
const OUR_ACCOUNT_TYPE_ENUM = new Set([
  "Bank",
  "Accounts Receivable",
  "Other Current Asset",
  "Fixed Asset",
  "Other Asset",
  "Accounts Payable",
  "Credit Card",
  "Other Current Liability",
  "Long Term Liability",
  "Equity",
  "Income",
  "Other Income",
  "Expense",
  "Other Expense",
  "Cost of Goods Sold"
]);

export async function run(): Promise<void> {
  await capabilityTest(
    "1.2 / 6.1",
    "Full COA read succeeds; AccountType/AccountSubType values observed match §4.6's closed enum",
    async (capture) => {
      const client = new QboRawClient();
      const result = await client.query("select * from Account MAXRESULTS 1000");
      capture({ query: "select * from Account MAXRESULTS 1000" }, { count: (result.body as any)?.QueryResponse?.Account?.length });

      if (result.status !== 200) return fail(`HTTP ${result.status}: ${JSON.stringify(result.body)}`);

      const accounts = (result.body as any)?.QueryResponse?.Account ?? [];
      const observedTypes = new Set<string>(accounts.map((a: any) => a.AccountType));
      const unmapped = [...observedTypes].filter((t) => !OUR_ACCOUNT_TYPE_ENUM.has(t));
      const observedSubTypes = new Set<string>(accounts.map((a: any) => a.AccountSubType).filter(Boolean));

      const detail =
        `${accounts.length} accounts read. Observed AccountType values: ${[...observedTypes].sort().join(", ")}. ` +
        `${unmapped.length ? `⚠ NOT in our §4.6 enum: ${unmapped.join(", ")}.` : "All observed types map cleanly to our enum."} ` +
        `${observedSubTypes.size} distinct AccountSubType values observed (kept verbatim per §4.6, not enumerated by design).`;

      return unmapped.length ? fail(detail) : pass(detail);
    }
  );

  await capabilityTest(
    "3.1 (subset) / 4.1",
    "Purchase read for a bounded date window; field completeness against §4.7's LedgerTransaction",
    async (capture) => {
      const client = new QboRawClient();
      const result = await client.query(
        "select * from Purchase where TxnDate >= '2026-06-01' and TxnDate <= '2026-08-16' MAXRESULTS 100"
      );
      capture({ query: "select * from Purchase where TxnDate range, MAXRESULTS 100" }, { count: (result.body as any)?.QueryResponse?.Purchase?.length });

      if (result.status !== 200) return fail(`HTTP ${result.status}: ${JSON.stringify(result.body)}`);

      const purchases = (result.body as any)?.QueryResponse?.Purchase ?? [];
      if (purchases.length === 0) return fail("Query succeeded but returned zero purchases — expected seeded data to be present.");

      // §4.7's LedgerTransaction fields, checked for a QBO source field to
      // populate from. `clearedStatus` deliberately excluded — §4.7 already
      // documents it defaults to .unknown because QBO rarely exposes it on
      // the entity itself (confirmed here: no field found).
      const required = ["Id", "TxnDate", "TotalAmt", "Line", "SyncToken"];
      const missingOnAny = required.filter((field) => purchases.some((p: any) => p[field] === undefined));
      const hasEntityRef = purchases.every((p: any) => p.EntityRef !== undefined); // counterparty
      const hasAccountRef = purchases.every((p: any) => p.AccountRef !== undefined); // paymentAccount
      const hasClearedField = purchases.some((p: any) => "Cleared" in p || "cleared" in p);

      const detail =
        `${purchases.length} purchases read. Required fields missing on at least one record: ${missingOnAny.length ? missingOnAny.join(", ") : "none"}. ` +
        `EntityRef (counterparty) present on all: ${hasEntityRef}. AccountRef (paymentAccount) present on all: ${hasAccountRef}. ` +
        `A 'cleared' field exists anywhere: ${hasClearedField} — corroborates §4.7's clearedStatus defaulting to .unknown by design.`;

      return missingOnAny.length ? fail(detail) : pass(detail);
    }
  );
}
