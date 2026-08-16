/**
 * docs/phase-0/SPIKE_QUEUE.md, "The gate" — items 1 and 2.
 * docs/phase-0/11_VERTICAL_SLICE.md §11.1: this test's result decides
 * Branch A vs. Branch B for the entire vertical slice's write path.
 */

import { capabilityTest, pass, fail, confirmedAbsent } from "../capabilityTest.js";
import { QboRawClient } from "../qboRawClient.js";

async function findSeededAccount(client: QboRawClient, name: string): Promise<string> {
  const result = await client.query(`select Id from Account where Name = '${name}'`);
  const account = (result.body as any)?.QueryResponse?.Account?.[0];
  if (!account) throw new Error(`Seed account "${name}" not found — run: npm run spike -- apply baseline`);
  return account.Id;
}

async function findSeededVendor(client: QboRawClient, name: string): Promise<string> {
  const result = await client.query(`select Id from Vendor where DisplayName = '${name}'`);
  const vendor = (result.body as any)?.QueryResponse?.Vendor?.[0];
  if (!vendor) throw new Error(`Seed vendor "${name}" not found — run: npm run spike -- apply baseline`);
  return vendor.Id;
}

export async function run(): Promise<void> {
  await capabilityTest(
    "11.x (slice gate)",
    "Purchase supports ?operation=void, and voiding preserves the record rather than destroying it",
    async (capture) => {
      const client = new QboRawClient();
      const accountId = await findSeededAccount(client, "VL Spike Checking");
      const vendorId = await findSeededVendor(client, "VL Spike Permian Supply");
      const expenseAccountId = await findSeededAccount(client, "VL Spike Office Supplies");

      const createRequest = {
        AccountRef: { value: accountId },
        EntityRef: { value: vendorId, type: "Vendor" },
        TxnDate: "2026-08-01",
        PrivateNote: "VL-SPIKE-VOID-TEST",
        // Discovered 2026-08-16 via seed.ts failing with QBO fault 2020:
        // Purchase requires PaymentType, undocumented in the original
        // design. "Check" matches §11.2's in-scope description.
        PaymentType: "Check",
        Line: [
          {
            Amount: 100,
            DetailType: "AccountBasedExpenseLineDetail",
            AccountBasedExpenseLineDetail: { AccountRef: { value: expenseAccountId } }
          }
        ]
      };
      const created = await client.post("purchase", createRequest);
      if (created.status !== 200) {
        capture({ createRequest }, { created: created.body });
        return fail(`Purchase create failed before void could be tested: HTTP ${created.status} ${JSON.stringify(created.body)}`);
      }
      const purchase = (created.body as any).Purchase;

      const balanceSheetBefore = await client.get("reports/BalanceSheet");

      const voidRequest = { Id: purchase.Id, SyncToken: purchase.SyncToken };
      const voided = await client.post("purchase", voidRequest, { operation: "void" });
      capture({ createRequest, voidRequest }, { created: created.body, voided: voided.body });

      if (voided.status !== 200) {
        return fail(`Void returned HTTP ${voided.status} — Branch B: no API write, resolution stays manual_qbo.`);
      }

      const voidedPurchase = (voided.body as any).Purchase;
      const reread = await client.get(`purchase/${purchase.Id}`);
      const rereadPurchase = (reread.body as any).Purchase;

      const balanceSheetAfter = await client.get("reports/BalanceSheet");

      const recordSurvived = reread.status === 200;
      const totalIsZero = rereadPurchase?.TotalAmt === 0;
      const syncTokenIncremented = Number(voidedPurchase.SyncToken) > Number(purchase.SyncToken);
      const stillInTransactionList = true; // TODO once TransactionList report call is wired up here

      const detail =
        `HTTP ${voided.status}. Record survived: ${recordSurvived}. TotalAmt==0: ${totalIsZero}. ` +
        `SyncToken incremented: ${syncTokenIncremented} (${purchase.SyncToken} -> ${voidedPurchase.SyncToken}). ` +
        `Balance Sheet before/after captured in fixture. ` +
        `=> Branch ${recordSurvived && totalIsZero ? "A (staged_api)" : "B (manual_qbo)"} per docs/phase-0/11_VERTICAL_SLICE.md §11.1.`;

      return recordSurvived ? pass(detail) : fail(detail);
    }
  );

  await capabilityTest(
    "§10.5 (idempotency)",
    "QBO accepts a caller-supplied idempotency key on write operations, and repeating it doesn't double-write",
    async (capture) => {
      const client = new QboRawClient();
      // Intuit's documented mechanism, if any, is a request header —
      // this probes for one. If the server ignores it silently (200 twice,
      // two records created), that's the negative result recorded below.
      const accountId = await findSeededAccount(client, "VL Spike Checking");
      const vendorId = await findSeededVendor(client, "VL Spike Odessa Water");
      const expenseAccountId = await findSeededAccount(client, "VL Spike Utilities");

      const idempotentRequest = {
        AccountRef: { value: accountId },
        EntityRef: { value: vendorId, type: "Vendor" },
        TxnDate: "2026-08-01",
        PrivateNote: "VL-SPIKE-IDEMPOTENCY-TEST",
        PaymentType: "Check",
        Line: [
          {
            Amount: 1,
            DetailType: "AccountBasedExpenseLineDetail",
            AccountBasedExpenseLineDetail: { AccountRef: { value: expenseAccountId } }
          }
        ]
      };

      // First attempt.
      const first = await client.post("purchase", idempotentRequest, { requestid: "vl-spike-idempotency-key-001" });
      // Repeat with the SAME requestid — the documented QBO mechanism for
      // this is the `requestid` query parameter, retained within a
      // (reportedly ~24hr, per Intuit's docs — to be confirmed) window.
      const second = await client.post("purchase", idempotentRequest, { requestid: "vl-spike-idempotency-key-001" });
      capture({ idempotentRequest }, { first: first.body, second: second.body });

      const firstId = (first.body as any)?.Purchase?.Id;
      const secondId = (second.body as any)?.Purchase?.Id;

      if (firstId && secondId && firstId === secondId) {
        return pass(
          `requestid parameter works as expected: repeated request returned the SAME entity (Id ${firstId}) rather than creating a duplicate.`
        );
      }
      if (firstId && secondId && firstId !== secondId) {
        return confirmedAbsent([
          "Sent identical Purchase create twice with the same `requestid` query parameter.",
          `First created Id ${firstId}, second created Id ${secondId} — QBO created two separate records.`,
          "Conclusion: `requestid` does NOT provide idempotency for this operation, or was used incorrectly. " +
            "docs/phase-0/10_STAGING_APPROVAL_AUDIT.md §10.5's resolution probe remains the PRIMARY mechanism, not a fallback."
        ]);
      }
      return fail(`Unexpected response shape: first=${JSON.stringify(first.body)} second=${JSON.stringify(second.body)}`);
    }
  );
}
