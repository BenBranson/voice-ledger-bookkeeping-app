/**
 * docs/phase-0/SPIKE_QUEUE.md Wave 3, items 20-21.
 */

import { capabilityTest, pass, fail } from "../capabilityTest.js";
import { QboRawClient } from "../qboRawClient.js";
import { findAccountId } from "../testHelpers.js";

export async function run(): Promise<void> {
  await capabilityTest("8.4", "JournalEntry create — balanced debit/credit", async (capture) => {
    const client = new QboRawClient();
    const checkingId = await findAccountId(client, "VL Spike Checking");
    const officeSuppliesId = await findAccountId(client, "VL Spike Office Supplies");

    const created = await client.post("journalentry", {
      TxnDate: "2026-08-16",
      Line: [
        {
          Amount: 25,
          DetailType: "JournalEntryLineDetail",
          JournalEntryLineDetail: { PostingType: "Debit", AccountRef: { value: officeSuppliesId } }
        },
        {
          Amount: 25,
          DetailType: "JournalEntryLineDetail",
          JournalEntryLineDetail: { PostingType: "Credit", AccountRef: { value: checkingId } }
        }
      ]
    });
    capture({ debit: officeSuppliesId, credit: checkingId, amount: 25 }, created.body);

    if (created.status !== 200) return fail(`HTTP ${created.status}: ${JSON.stringify(created.body)}`);
    const je = (created.body as any).JournalEntry;
    return pass(`JournalEntry created (Id ${je.Id}), 2 balanced lines, TotalAmt confirms balance: ${je.Line?.length === 2}.`);
  });

  await capabilityTest("8.6", "Transfer create between two accounts", async (capture) => {
    const client = new QboRawClient();
    const checkingId = await findAccountId(client, "VL Spike Checking");

    // Need a second bank-type account to transfer to — create one.
    const secondAccount = await client.post("account", {
      Name: `VL Spike Transfer Target ${Date.now().toString().slice(-6)}`,
      AccountType: "Bank"
    });
    if (secondAccount.status !== 200) return fail(`Setup (second bank account) failed: HTTP ${secondAccount.status}: ${JSON.stringify(secondAccount.body)}`);
    const targetAccountId = (secondAccount.body as any).Account.Id;

    const created = await client.post("transfer", {
      TxnDate: "2026-08-16",
      Amount: 15,
      FromAccountRef: { value: checkingId },
      ToAccountRef: { value: targetAccountId }
    });
    capture({ from: checkingId, to: targetAccountId, amount: 15 }, { secondAccount: secondAccount.body, created: created.body });

    if (created.status !== 200) return fail(`HTTP ${created.status}: ${JSON.stringify(created.body)}`);
    const transfer = (created.body as any).Transfer;
    return pass(`Transfer created (Id ${transfer.Id}), $15 from ${checkingId} to ${targetAccountId}.`);
  });
}
