/**
 * Shared lookups for Wave 3+ spike tests, factored out once several test
 * files needed the same "find the seeded baseline account/vendor" logic
 * that lived duplicated in tests/00-purchase-void.spike.ts.
 */

import { QboRawClient } from "./qboRawClient.js";

export async function findAccountId(client: QboRawClient, name: string): Promise<string> {
  const result = await client.query(`select Id from Account where Name = '${name}'`);
  const account = (result.body as any)?.QueryResponse?.Account?.[0];
  if (!account) throw new Error(`Seed account "${name}" not found — run: npx tsx spike/seed.ts apply baseline`);
  return account.Id;
}

export async function findVendorId(client: QboRawClient, name: string): Promise<string> {
  const result = await client.query(`select Id from Vendor where DisplayName = '${name}'`);
  const vendor = (result.body as any)?.QueryResponse?.Vendor?.[0];
  if (!vendor) throw new Error(`Seed vendor "${name}" not found — run: npx tsx spike/seed.ts apply baseline`);
  return vendor.Id;
}

/** Short unique DocNumber generator — QBO caps DocNumber at 21 chars (§ finding, 2026-08-16). */
export function shortUniqueDocNumber(prefix: string): string {
  return `${prefix}${Date.now().toString().slice(-8)}`.slice(0, 21);
}
