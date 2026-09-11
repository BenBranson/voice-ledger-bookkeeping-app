// Spike (2026-09-11): does this sandbox have any real "suspense" or
// "clearing" account, the way it has a genuine "Ask My Accountant" gap
// (checkAskMyAccountant.ts, 2026-08-31)? Checking before building
// VL-BS-SUSPENSE-001 / a stale-clearing-account rule, per CLAUDE.md rule 6
// — a rule that can never fire against real data isn't worth shipping.
import "dotenv/config";
import { QboRawClient } from "./qboRawClient.js";

const client = new QboRawClient();

const allAccounts = await client.query("SELECT Id, Name, AccountType, AccountSubType, CurrentBalance, Active FROM Account MAXRESULTS 1000");
const body = allAccounts.body as { QueryResponse?: { Account?: Array<{ Id: string; Name: string; AccountType: string; AccountSubType?: string; CurrentBalance?: number; Active: boolean }> } };
const accounts = body.QueryResponse?.Account ?? [];

console.log(`Total accounts in this sandbox: ${accounts.length}`);
console.log("");

const suspenseMatch = accounts.filter(a => a.Name.toLowerCase().includes("suspense"));
console.log("Accounts matching 'suspense':", JSON.stringify(suspenseMatch, null, 2));

const clearingMatch = accounts.filter(a => a.Name.toLowerCase().includes("clearing"));
console.log("Accounts matching 'clearing':", JSON.stringify(clearingMatch, null, 2));

console.log("");
console.log("Full account name list (Name / Type / SubType / Balance):");
for (const a of accounts) {
  console.log(`- ${a.Name} (${a.AccountType}${a.AccountSubType ? ` / ${a.AccountSubType}` : ""}) balance=${a.CurrentBalance ?? "n/a"} active=${a.Active}`);
}
