/**
 * docs/phase-0/SPIKE_QUEUE.md Wave 3, items 18-19.
 */

import { capabilityTest, pass, fail } from "../capabilityTest.js";
import { QboRawClient } from "../qboRawClient.js";
import { findAccountId, findVendorId, shortUniqueDocNumber } from "../testHelpers.js";

export async function run(): Promise<void> {
  await capabilityTest(
    "C6",
    "Batch request: 10-item batch with one deliberately invalid item — is fault isolation per-item?",
    async (capture) => {
      const client = new QboRawClient();
      const checkingId = await findAccountId(client, "VL Spike Checking");
      const vendorId = await findVendorId(client, "VL Spike Permian Supply");

      const items = Array.from({ length: 10 }, (_, i) => {
        const isInvalid = i === 5; // one deliberately broken item, middle of the batch
        return {
          bId: `item-${i}`,
          operation: "create",
          Purchase: isInvalid
            ? {
                // Invalid: missing PaymentType (§2 finding, 2026-08-16) — deliberately
                AccountRef: { value: checkingId },
                EntityRef: { value: vendorId, type: "Vendor" },
                TxnDate: "2026-08-16",
                DocNumber: shortUniqueDocNumber(`W3BATCHBAD${i}`),
                Line: [{ Amount: 1, DetailType: "AccountBasedExpenseLineDetail", AccountBasedExpenseLineDetail: { AccountRef: { value: checkingId } } }]
              }
            : {
                AccountRef: { value: checkingId },
                EntityRef: { value: vendorId, type: "Vendor" },
                TxnDate: "2026-08-16",
                DocNumber: shortUniqueDocNumber(`W3BATCH${i}`),
                PaymentType: "Check",
                Line: [{ Amount: 1, DetailType: "AccountBasedExpenseLineDetail", AccountBasedExpenseLineDetail: { AccountRef: { value: checkingId } } }]
              }
        };
      });

      const result = await client.post("batch", { BatchItemRequest: items });
      capture({ itemCount: items.length, deliberatelyInvalidIndex: 5 }, result.body);

      if (result.status !== 200) return fail(`Batch request itself failed: HTTP ${result.status}: ${JSON.stringify(result.body)}`);

      const responses = (result.body as any)?.BatchItemResponse ?? [];
      const successes = responses.filter((r: any) => r.Purchase && !r.Fault);
      const faults = responses.filter((r: any) => r.Fault);

      const isolated = successes.length === 9 && faults.length === 1;
      const detail =
        `${responses.length} responses for 10 requests. ${successes.length} succeeded, ${faults.length} faulted. ` +
        `${isolated ? "Fault isolation is per-item as expected — a batch of 30 that fails on item 8 can be trusted to have succeeded on items 1-7 and 9-30." : `⚠ UNEXPECTED SHAPE — expected exactly 9 successes / 1 fault. Response: ${JSON.stringify(responses.map((r: any) => ({ bId: r.bId, hasFault: !!r.Fault })))}`}`;

      return isolated ? pass(detail) : fail(detail);
    }
  );

  await capabilityTest("C7", "Attachable upload against a Purchase", async (capture) => {
    const client = new QboRawClient();
    const checkingId = await findAccountId(client, "VL Spike Checking");
    const vendorId = await findVendorId(client, "VL Spike Permian Supply");

    const purchaseCreated = await client.post("purchase", {
      AccountRef: { value: checkingId },
      EntityRef: { value: vendorId, type: "Vendor" },
      TxnDate: "2026-08-16",
      DocNumber: shortUniqueDocNumber("W3ATTACH"),
      PaymentType: "Check",
      Line: [{ Amount: 5, DetailType: "AccountBasedExpenseLineDetail", AccountBasedExpenseLineDetail: { AccountRef: { value: checkingId } } }]
    });
    if (purchaseCreated.status !== 200) return fail(`Setup failed: HTTP ${purchaseCreated.status}: ${JSON.stringify(purchaseCreated.body)}`);
    const purchase = (purchaseCreated.body as any).Purchase;

    // FIRST ATTEMPT (same session, revised): FileName + ContentType +
    // EntityRef alone, no actual content, failed with "You must have at
    // least a note string or file attachment" (fault 6000) — a genuine
    // finding: Attachable metadata cannot exist as a bare pointer, it needs
    // either a Note or real file content. Added Note to get a complete
    // answer about whether the ENTITY LINKAGE half works, which is the
    // actual capability question.
    const attachableCreated = await client.post("attachable", {
      FileName: "vl-spike-test-receipt.txt",
      ContentType: "text/plain",
      Note: "VL spike capability test — Attachable linked to a Purchase via EntityRef",
      AttachableRef: [{ EntityRef: { value: purchase.Id, type: "Purchase" } }]
    });
    capture(
      { purchaseId: purchase.Id, note: "Note field added because metadata-only (no Note, no content) failed with fault 6000 on the first attempt this session" },
      { purchaseCreated: purchaseCreated.body, attachableCreated: attachableCreated.body }
    );

    if (attachableCreated.status !== 200) {
      return fail(
        `Attachable create failed even with a Note field: HTTP ${attachableCreated.status}: ${JSON.stringify(attachableCreated.body)}. ` +
          `Note: this only tests JSON-metadata Attachable creation with an EntityRef link, not binary file upload (that's a separate multipart endpoint, not exercised here).`
      );
    }
    const attachable = (attachableCreated.body as any).Attachable;
    return pass(
      `Attachable metadata created (Id ${attachable.Id}) and linked to Purchase ${purchase.Id}. ` +
        `NOT tested: actual binary file upload via the multipart /upload endpoint — this only confirms the entity-linkage half works.`
    );
  });
}
