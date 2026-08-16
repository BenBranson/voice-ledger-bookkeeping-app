/**
 * docs/phase-0/SPIKE_QUEUE.md Wave 3, items 16-17.
 * The real assertion here is NOT "did the update succeed" — it's whether
 * unrelated fields survive. A sparse update that silently isn't sparse is
 * how §2 row 7.1's data-loss constraint bites in production.
 */

import { capabilityTest, pass, fail } from "../capabilityTest.js";
import { QboRawClient } from "../qboRawClient.js";
import { findAccountId, findVendorId, shortUniqueDocNumber } from "../testHelpers.js";

export async function run(): Promise<void> {
  await capabilityTest(
    "7.1",
    "Sparse update of Purchase line AccountRef — do PrivateNote, DocNumber, and Memo survive untouched?",
    async (capture) => {
      const client = new QboRawClient();
      const checkingId = await findAccountId(client, "VL Spike Checking");
      const officeSuppliesId = await findAccountId(client, "VL Spike Office Supplies");
      const utilitiesId = await findAccountId(client, "VL Spike Utilities");
      const vendorId = await findVendorId(client, "VL Spike Permian Supply");

      const docNumber = shortUniqueDocNumber("W3SPARSE");
      const memo = "This memo must survive a sparse AccountRef update untouched.";
      const privateNote = "VL-SPIKE-W3-SPARSE-TEST";

      const created = await client.post("purchase", {
        AccountRef: { value: checkingId },
        EntityRef: { value: vendorId, type: "Vendor" },
        TxnDate: "2026-08-16",
        DocNumber: docNumber,
        PrivateNote: privateNote,
        PaymentType: "Check",
        Line: [
          {
            Amount: 77,
            DetailType: "AccountBasedExpenseLineDetail",
            Description: memo,
            AccountBasedExpenseLineDetail: { AccountRef: { value: officeSuppliesId } }
          }
        ]
      });
      if (created.status !== 200) return fail(`Setup failed: HTTP ${created.status}: ${JSON.stringify(created.body)}`);
      const purchase = (created.body as any).Purchase;

      // FIRST ATTEMPT (same session, revised): a sparse update touching ONLY
      // the line's AccountRef — nothing else in the payload — failed with
      // "Required parameter PaymentType is missing" (fault 2020). That is
      // itself the finding: PaymentType is required on EVERY Purchase write,
      // sparse or not — sparse does not mean "existing values are inherited
      // for required fields." Recorded in the matrix's TXN profile notes.
      //
      // To isolate the actual question (do UNRELATED fields survive), this
      // resends PaymentType with its EXISTING value (not a change) alongside
      // the real change (AccountRef) — the minimum payload sparse actually
      // accepts for this entity.
      const sparseUpdate = await client.post("purchase", {
        Id: purchase.Id,
        SyncToken: purchase.SyncToken,
        sparse: true,
        PaymentType: "Check", // required even in sparse mode — see comment above
        Line: [
          {
            Id: purchase.Line[0].Id,
            Amount: 77,
            DetailType: "AccountBasedExpenseLineDetail",
            AccountBasedExpenseLineDetail: { AccountRef: { value: utilitiesId } }
          }
        ]
      });
      capture(
        { purchaseId: purchase.Id, docNumber, privateNote, memo, note: "PaymentType resent because omitting it entirely failed with fault 2020 on the first attempt this session" },
        { created: created.body, sparseUpdate: sparseUpdate.body }
      );

      if (sparseUpdate.status !== 200) return fail(`Sparse update failed even with PaymentType resent: HTTP ${sparseUpdate.status}: ${JSON.stringify(sparseUpdate.body)}`);
      const updated = (sparseUpdate.body as any).Purchase;

      const accountRefChanged = updated.Line[0]?.AccountBasedExpenseLineDetail?.AccountRef?.value === utilitiesId;
      const docNumberSurvived = updated.DocNumber === docNumber;
      const privateNoteSurvived = updated.PrivateNote === privateNote;
      const memoSurvived = updated.Line[0]?.Description === memo;
      const allSurvived = docNumberSurvived && privateNoteSurvived && memoSurvived;

      const detail =
        `AccountRef changed as requested: ${accountRefChanged}. ` +
        `DocNumber survived: ${docNumberSurvived}. PrivateNote survived: ${privateNoteSurvived}. Line memo (Description) survived: ${memoSurvived}. ` +
        `${allSurvived ? "Sparse update is genuinely sparse for this field combination — safe to build the batch-fix machinery on this pattern." : "⚠ SPARSE UPDATE LOST DATA — at least one unrelated field was cleared. This is exactly the data-loss hazard §2 row 7.1 warned about. Do NOT build batch reclassification on this exact payload shape without further isolation of which field caused the loss."}`;

      return allSurvived ? pass(detail) : fail(detail);
    }
  );

  await capabilityTest(
    "7.2",
    "Sparse update of Bill line — does it require resending the full Line array, or does a single-line patch work?",
    async (capture) => {
      const client = new QboRawClient();
      const vendorId = await findVendorId(client, "VL Spike Permian Supply");
      const officeSuppliesId = await findAccountId(client, "VL Spike Office Supplies");
      const utilitiesId = await findAccountId(client, "VL Spike Utilities");

      const docNumber = shortUniqueDocNumber("W3BILL");

      // Bill with TWO lines, so we can test whether omitting one in the
      // sparse update loses it — the specific constraint §2 row 7.1 flags.
      const created = await client.post("bill", {
        VendorRef: { value: vendorId },
        TxnDate: "2026-08-16",
        DocNumber: docNumber,
        Line: [
          { Amount: 10, DetailType: "AccountBasedExpenseLineDetail", AccountBasedExpenseLineDetail: { AccountRef: { value: officeSuppliesId } } },
          { Amount: 20, DetailType: "AccountBasedExpenseLineDetail", AccountBasedExpenseLineDetail: { AccountRef: { value: utilitiesId } } }
        ]
      });

      if (created.status !== 200) {
        capture({ docNumber }, created.body);
        return fail(`Bill create failed: HTTP ${created.status}: ${JSON.stringify(created.body)} — this itself is a finding: Bill's required-field shape differs from Purchase's.`);
      }
      const bill = (created.body as any).Bill;
      const line1Id = bill.Line[0]?.Id;
      const line2Id = bill.Line[1]?.Id;

      // FIRST ATTEMPT (same session, revised): sending only line 1 without
      // VendorRef failed with "Required parameter VendorRef is missing"
      // (fault 2020) — a DIFFERENT question than the one being tested here.
      // That's a real finding too (VendorRef required on every Bill write,
      // sparse or not — matches Purchase's PaymentType requirement, same
      // pattern) but it doesn't answer whether the Line array itself must
      // be complete. Resending VendorRef with its existing value isolates
      // that question.
      const sparseUpdate = await client.post("bill", {
        Id: bill.Id,
        SyncToken: bill.SyncToken,
        sparse: true,
        VendorRef: { value: vendorId }, // required even in sparse mode — see comment above
        Line: [{ Id: line1Id, Amount: 15, DetailType: "AccountBasedExpenseLineDetail", AccountBasedExpenseLineDetail: { AccountRef: { value: officeSuppliesId } } }]
      });

      const updateSucceeded = sparseUpdate.status === 200;
      const updated = updateSucceeded ? (sparseUpdate.body as any).Bill : null;
      const line2Survived = updated ? updated.Line?.some((l: any) => l.Id === line2Id) : null;

      capture(
        { billId: bill.Id, line1Id, line2Id, note: "VendorRef resent because omitting it failed with fault 2020 on the first attempt this session" },
        { created: created.body, sparseUpdate: sparseUpdate.body }
      );

      const detail = !updateSucceeded
        ? `Sending only 1 of 2 lines (with VendorRef resent) was REJECTED: HTTP ${sparseUpdate.status}: ${JSON.stringify(sparseUpdate.body)}. This confirms §2 row 7.1 constraint 2: a "sparse" update at the entity level requires the FULL Line array. Any batch-reclassification code must always resend every line, never a subset.`
        : `Sending only 1 of 2 lines (with VendorRef resent) SUCCEEDED (HTTP 200). Line 2 (Id ${line2Id}) survived in the response: ${line2Survived}. ${line2Survived ? "Genuinely sparse at the line level for this entity." : "⚠ Line 2 was SILENTLY DROPPED — a subset Line array truncates the transaction. Confirms the constraint the hard way."}`;

      return updateSucceeded && line2Survived ? pass(detail) : fail(detail);
    }
  );
}
