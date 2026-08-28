/**
 * One-off capability check, same convention as the rest of spike/*: is
 * `FullyQualifiedName` actually present on this sandbox's real `Account`
 * query response? `QBORawAccount.fullyQualifiedName`
 * (desktop/Sources/Integrations/QuickBooks/QBORawPurchase.swift) added the
 * field but flagged it as NOT spike-verified — this closes that gap.
 *
 * Usage: QBO_SPIKE_REALM_ID=<realmId> npx tsx spike/checkFullyQualifiedName.ts
 */
import "dotenv/config";
import { QboRawClient } from "./qboRawClient.js";

const client = new QboRawClient();
const result = await client.query("select Id, Name, FullyQualifiedName, AccountType, AccountSubType from Account MAXRESULTS 1000");

const accounts = (result.body as any)?.QueryResponse?.Account ?? [];
console.log(`status: ${result.status}`);
console.log(`accounts returned: ${accounts.length}`);
const withFQN = accounts.filter((a: any) => typeof a.FullyQualifiedName === "string" && a.FullyQualifiedName.length > 0);
console.log(`accounts with a real FullyQualifiedName: ${withFQN.length}`);
console.log("sample (first 5):");
for (const a of accounts.slice(0, 5)) {
  console.log(`  Id=${a.Id} Name=${JSON.stringify(a.Name)} FullyQualifiedName=${JSON.stringify(a.FullyQualifiedName)} Type=${a.AccountType}`);
}

// Find any leaf-Name collision to sanity-check the false-positive story
// VL-COA-DUPACCT-001 documented (same leaf Name, different FullyQualifiedName).
const byName: Record<string, any[]> = {};
for (const a of accounts) {
  const existing = byName[a.Name] ?? [];
  existing.push(a);
  byName[a.Name] = existing;
}
const collisions = Object.entries(byName).filter(([, list]) => list.length > 1);
console.log(`\nleaf-Name collisions in this sandbox: ${collisions.length}`);
for (const [name, list] of collisions.slice(0, 10)) {
  console.log(`  "${name}": ${list.map((a: any) => `${a.AccountType}/${JSON.stringify(a.FullyQualifiedName)}`).join(" vs ")}`);
}
