/**
 * docs/phase-0/SPIKE_QUEUE.md Wave 3, items 12-15 (account writes).
 * Approved 2026-08-16 alongside the rest of Wave 3.
 */

import { capabilityTest, pass, fail } from "../capabilityTest.js";
import { QboRawClient } from "../qboRawClient.js";
import { findAccountId, findVendorId, shortUniqueDocNumber } from "../testHelpers.js";

export async function run(): Promise<void> {
  await capabilityTest("6.2", "Account create succeeds", async (capture) => {
    const client = new QboRawClient();
    const name = `VL Spike Wave3 Test ${Date.now().toString().slice(-6)}`;
    const created = await client.post("account", { Name: name, AccountType: "Expense" });
    capture({ name }, created.body);
    if (created.status !== 200) return fail(`HTTP ${created.status}: ${JSON.stringify(created.body)}`);
    const account = (created.body as any).Account;
    return pass(`Created Account Id ${account.Id}, Name "${account.Name}", AccountType "${account.AccountType}".`);
  });

  await capabilityTest("6.3", "Account rename (sparse update, Name field only)", async (capture) => {
    const client = new QboRawClient();
    // Create a throwaway account to rename, so we don't touch baseline fixtures.
    const originalName = `VL Spike Rename Test ${Date.now().toString().slice(-6)}`;
    const created = await client.post("account", { Name: originalName, AccountType: "Expense" });
    if (created.status !== 200) return fail(`Setup failed: HTTP ${created.status}: ${JSON.stringify(created.body)}`);
    const account = (created.body as any).Account;

    const newName = `${originalName} RENAMED`;
    const updated = await client.post("account", { Id: account.Id, SyncToken: account.SyncToken, sparse: true, Name: newName });
    capture({ accountId: account.Id, originalName, newName }, { created: created.body, updated: updated.body });

    if (updated.status !== 200) return fail(`Rename failed: HTTP ${updated.status}: ${JSON.stringify(updated.body)}`);
    const renamed = (updated.body as any).Account;
    const nameChanged = renamed.Name === newName;
    const typeUnchanged = renamed.AccountType === "Expense";
    return pass(
      `Sparse rename succeeded. Name changed: ${nameChanged}. AccountType survived unchanged: ${typeUnchanged} (${renamed.AccountType}). SyncToken: ${account.SyncToken} -> ${renamed.SyncToken}.`
    );
  });

  await capabilityTest("6.4 (zero balance)", "Account deactivate with zero balance", async (capture) => {
    const client = new QboRawClient();
    const name = `VL Spike Deactivate Zero ${Date.now().toString().slice(-6)}`;
    const created = await client.post("account", { Name: name, AccountType: "Expense" });
    if (created.status !== 200) return fail(`Setup failed: HTTP ${created.status}: ${JSON.stringify(created.body)}`);
    const account = (created.body as any).Account;

    const deactivated = await client.post("account", { Id: account.Id, SyncToken: account.SyncToken, sparse: true, Active: false });
    capture({ accountId: account.Id }, { created: created.body, deactivated: deactivated.body });

    if (deactivated.status !== 200) return fail(`Deactivate failed: HTTP ${deactivated.status}: ${JSON.stringify(deactivated.body)}`);
    const result = (deactivated.body as any).Account;
    return pass(`Zero-balance deactivate succeeded. Active: ${result.Active}. No adjusting entry expected or observed (no transactions ever posted to this account).`);
  });

  await capabilityTest(
    "6.4 (non-zero balance)",
    "Account deactivate with a non-zero balance — does QBO create an adjusting entry, refuse, or strand the balance?",
    async (capture) => {
      const client = new QboRawClient();
      const checkingId = await findAccountId(client, "VL Spike Checking");
      const vendorId = await findVendorId(client, "VL Spike Permian Supply");

      // Create a dedicated expense account with a real posted balance.
      const name = `VL Spike Deactivate NonZero ${Date.now().toString().slice(-6)}`;
      const accountCreated = await client.post("account", { Name: name, AccountType: "Expense" });
      if (accountCreated.status !== 200) return fail(`Setup (account) failed: HTTP ${accountCreated.status}: ${JSON.stringify(accountCreated.body)}`);
      const account = (accountCreated.body as any).Account;

      const purchaseCreated = await client.post("purchase", {
        AccountRef: { value: checkingId },
        EntityRef: { value: vendorId, type: "Vendor" },
        TxnDate: "2026-08-16",
        DocNumber: shortUniqueDocNumber("W3DEACT"),
        PaymentType: "Check",
        Line: [{ Amount: 42, DetailType: "AccountBasedExpenseLineDetail", AccountBasedExpenseLineDetail: { AccountRef: { value: account.Id } } }]
      });
      if (purchaseCreated.status !== 200) return fail(`Setup (purchase) failed: HTTP ${purchaseCreated.status}: ${JSON.stringify(purchaseCreated.body)}`);

      // Re-read the account for a fresh SyncToken before deactivating.
      const reread = await client.query(`select Id, SyncToken, Active from Account where Id = '${account.Id}'`);
      const freshAccount = (reread.body as any)?.QueryResponse?.Account?.[0];
      if (!freshAccount) return fail(`Could not re-read account ${account.Id} before deactivate attempt.`);

      const deactivated = await client.post("account", { Id: freshAccount.Id, SyncToken: freshAccount.SyncToken, sparse: true, Active: false });
      capture(
        { accountId: account.Id, purchaseAmount: 42 },
        { accountCreated: accountCreated.body, purchaseCreated: purchaseCreated.body, deactivated: deactivated.body }
      );

      if (deactivated.status !== 200) {
        return pass(
          `Deactivate REFUSED for a non-zero-balance account: HTTP ${deactivated.status}: ${JSON.stringify(deactivated.body)}. ` +
            `This is a definitive, useful answer — Page 6's deactivate path must check balance first and route to a different flow (or block) rather than attempt it.`
        );
      }
      const result = (deactivated.body as any).Account;
      // Check whether an adjusting Journal Entry appeared.
      const jeCheck = await client.query(
        `select Id, TxnDate, PrivateNote from JournalEntry where TxnDate = '${new Date().toISOString().slice(0, 10)}' MAXRESULTS 10`
      );
      return pass(
        `Deactivate SUCCEEDED for a non-zero-balance account ($42 posted). Active: ${result.Active}. ` +
          `Recent same-day JournalEntry count (checking for an auto-created adjusting entry): ${(jeCheck.body as any)?.QueryResponse?.JournalEntry?.length ?? 0}. ` +
          `⚠ The $42 balance's fate needs manual verification in the sandbox UI — this test detected no error, which could mean the balance was silently stranded rather than adjusted. Do not treat "no error" as "handled correctly."`
      );
    }
  );
}
