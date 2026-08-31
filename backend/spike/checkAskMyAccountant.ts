// Spike (2026-08-31): does "Ask My Accountant" exist as a real account in
// this sandbox, the way "Uncategorized Expense"/"Uncategorized Income"/
// "Uncategorized Asset" do (UncategorizedTransactionRule, live-verified
// 2026-08-18)? Checking before adding any rule/report coverage for it,
// per CLAUDE.md rule 6 — a name existing in QBO's documentation isn't
// evidence it exists in THIS company's real chart of accounts.
import "dotenv/config";
import { QboRawClient } from "./qboRawClient.js";

const client = new QboRawClient();

const allAccounts = await client.query("SELECT Id, Name, AccountType, AccountSubType, Active FROM Account MAXRESULTS 1000");
const body = allAccounts.body as { QueryResponse?: { Account?: Array<{ Id: string; Name: string; AccountType: string; AccountSubType?: string; Active: boolean }> } };
const accounts = body.QueryResponse?.Account ?? [];

console.log(`Total accounts in this sandbox: ${accounts.length}`);
console.log("");

const match = accounts.filter(a => a.Name.toLowerCase().includes("ask my accountant") || a.Name.toLowerCase().includes("accountant"));
console.log("Accounts matching 'accountant':", JSON.stringify(match, null, 2));

console.log("");
console.log("Full account name list:");
for (const a of accounts) {
  console.log(`- ${a.Name} (${a.AccountType}${a.AccountSubType ? ` / ${a.AccountSubType}` : ""}) active=${a.Active}`);
}
