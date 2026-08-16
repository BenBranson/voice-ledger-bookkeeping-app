/**
 * docs/phase-0/SPIKE_QUEUE.md — added 2026-08-16 per owner Decision 3:
 * "test ?operation=void against Bill, JournalEntry, and BillPayment. If any
 * support it, Branch B applies to the duplicate-expense slice specifically,
 * not to every TXN-profile entity."
 *
 * Explicitly testing only, per the owner's instruction — "do not build
 * against results yet." Nothing downstream (11_VERTICAL_SLICE.md,
 * 08_RULE_ENGINE.md) is touched based on what these return.
 *
 * Revised same session after the first run: Bill and JournalEntry both
 * returned HTTP 200 with an anomalous body (a Fault for Bill, an empty
 * BatchItemResponse for JournalEntry) instead of either a clean success
 * or a clean rejection. The original code assumed status 200 implied the
 * expected entity key would be present and crashed reading it. Fixed to
 * classify the response into one of three outcomes explicitly, because
 * the anomaly itself is the more important finding: status-code-only
 * success checking would be WRONG for these two entities.
 */

import { capabilityTest, pass } from "../capabilityTest.js";
import { QboRawClient } from "../qboRawClient.js";
import { findAccountId, findVendorId, shortUniqueDocNumber } from "../testHelpers.js";

type VoidOutcome =
  | { kind: "cleanReject"; detail: string }
  | { kind: "cleanSuccess"; detail: string }
  | { kind: "anomalous200"; detail: string };

function classifyVoidResponse(status: number, body: unknown, entityKey: string): VoidOutcome {
  const asAny = body as any;
  if (status !== 200) {
    return { kind: "cleanReject", detail: `HTTP ${status}: ${JSON.stringify(body)}` };
  }
  if (asAny?.Fault) {
    return {
      kind: "anomalous200",
      detail: `⚠ HTTP 200 but body contains a Fault: ${JSON.stringify(asAny.Fault)}. A status-code-only success check would WRONGLY treat this as a successful void.`
    };
  }
  if (asAny?.[entityKey]) {
    return { kind: "cleanSuccess", detail: `HTTP 200 with a valid ${entityKey} object: ${JSON.stringify(asAny[entityKey]).slice(0, 300)}` };
  }
  return {
    kind: "anomalous200",
    detail: `⚠ HTTP 200 but body has neither a Fault nor a ${entityKey} object: ${JSON.stringify(body)}. Ambiguous — cannot confirm success or failure from this response alone; a resolution probe (re-read the entity) would be required to know what actually happened.`
  };
}

export async function run(): Promise<void> {
  await capabilityTest("11.x (Bill)", "Does ?operation=void work on Bill?", async (capture) => {
    const client = new QboRawClient();
    const vendorId = await findVendorId(client, "VL Spike Permian Supply");
    const officeSuppliesId = await findAccountId(client, "VL Spike Office Supplies");

    const created = await client.post("bill", {
      VendorRef: { value: vendorId },
      TxnDate: "2026-08-16",
      DocNumber: shortUniqueDocNumber("W3VOIDBILL"),
      Line: [{ Amount: 30, DetailType: "AccountBasedExpenseLineDetail", AccountBasedExpenseLineDetail: { AccountRef: { value: officeSuppliesId } } }]
    });
    const bill = (created.body as any)?.Bill;
    if (created.status !== 200 || !bill) {
      capture({ step: "setup" }, created.body);
      return pass(`Setup (Bill create) failed, void not attempted: HTTP ${created.status}: ${JSON.stringify(created.body)}`);
    }

    const voided = await client.post("bill", { Id: bill.Id, SyncToken: bill.SyncToken }, { operation: "void" });
    const outcome = classifyVoidResponse(voided.status, voided.body, "Bill");
    capture({ billId: bill.Id }, { created: created.body, voidedStatus: voided.status, voided: voided.body, classification: outcome.kind });

    return pass(`Bill void → ${outcome.kind}. ${outcome.detail}`);
  });

  await capabilityTest("11.x (JournalEntry)", "Does ?operation=void work on JournalEntry?", async (capture) => {
    const client = new QboRawClient();
    const checkingId = await findAccountId(client, "VL Spike Checking");
    const officeSuppliesId = await findAccountId(client, "VL Spike Office Supplies");

    const created = await client.post("journalentry", {
      TxnDate: "2026-08-16",
      Line: [
        { Amount: 8, DetailType: "JournalEntryLineDetail", JournalEntryLineDetail: { PostingType: "Debit", AccountRef: { value: officeSuppliesId } } },
        { Amount: 8, DetailType: "JournalEntryLineDetail", JournalEntryLineDetail: { PostingType: "Credit", AccountRef: { value: checkingId } } }
      ]
    });
    const je = (created.body as any)?.JournalEntry;
    if (created.status !== 200 || !je) {
      capture({ step: "setup" }, created.body);
      return pass(`Setup (JournalEntry create) failed, void not attempted: HTTP ${created.status}: ${JSON.stringify(created.body)}`);
    }

    const voided = await client.post("journalentry", { Id: je.Id, SyncToken: je.SyncToken }, { operation: "void" });
    const outcome = classifyVoidResponse(voided.status, voided.body, "JournalEntry");
    capture({ journalEntryId: je.Id }, { created: created.body, voidedStatus: voided.status, voided: voided.body, classification: outcome.kind });

    // If anomalous, probe by re-reading the entity to see what actually happened.
    let probeNote = "";
    if (outcome.kind === "anomalous200") {
      const reread = await client.query(`select Id, SyncToken from JournalEntry where Id = '${je.Id}'`);
      const stillExists = !!(reread.body as any)?.QueryResponse?.JournalEntry?.[0];
      probeNote = ` Resolution probe: entity still exists in QBO: ${stillExists}.`;
    }

    return pass(`JournalEntry void → ${outcome.kind}. ${outcome.detail}${probeNote}`);
  });

  await capabilityTest("11.x (BillPayment)", "Does ?operation=void work on BillPayment?", async (capture) => {
    const client = new QboRawClient();
    const vendorId = await findVendorId(client, "VL Spike Permian Supply");
    const officeSuppliesId = await findAccountId(client, "VL Spike Office Supplies");
    const checkingId = await findAccountId(client, "VL Spike Checking");

    const billCreated = await client.post("bill", {
      VendorRef: { value: vendorId },
      TxnDate: "2026-08-16",
      DocNumber: shortUniqueDocNumber("W3BPBILL"),
      Line: [{ Amount: 12, DetailType: "AccountBasedExpenseLineDetail", AccountBasedExpenseLineDetail: { AccountRef: { value: officeSuppliesId } } }]
    });
    const bill = (billCreated.body as any)?.Bill;
    if (billCreated.status !== 200 || !bill) {
      capture({ step: "setup-bill" }, billCreated.body);
      return pass(`Setup (Bill for payment) failed, void not attempted: HTTP ${billCreated.status}: ${JSON.stringify(billCreated.body)}`);
    }

    const paymentCreated = await client.post("billpayment", {
      VendorRef: { value: vendorId },
      TotalAmt: 12,
      PayType: "Check",
      CheckPayment: { BankAccountRef: { value: checkingId } },
      Line: [{ Amount: 12, LinkedTxn: [{ TxnId: bill.Id, TxnType: "Bill" }] }]
    });
    const payment = (paymentCreated.body as any)?.BillPayment;
    if (paymentCreated.status !== 200 || !payment) {
      capture({ step: "setup-payment" }, paymentCreated.body);
      return pass(`Setup (BillPayment create) failed, void not attempted: HTTP ${paymentCreated.status}: ${JSON.stringify(paymentCreated.body)}`);
    }

    const voided = await client.post("billpayment", { Id: payment.Id, SyncToken: payment.SyncToken }, { operation: "void" });
    const outcome = classifyVoidResponse(voided.status, voided.body, "BillPayment");
    capture(
      { billId: bill.Id, billPaymentId: payment.Id },
      { billCreated: billCreated.body, paymentCreated: paymentCreated.body, voidedStatus: voided.status, voided: voided.body, classification: outcome.kind }
    );

    return pass(`BillPayment void → ${outcome.kind}. ${outcome.detail}`);
  });
}
