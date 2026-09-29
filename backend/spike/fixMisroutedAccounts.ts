// One-off repair (2026-09-29, SANDBOX ONLY): the operating-history seed posted
// lumber bills and nursery purchases to the INCOME accounts named "Job
// Materials" (46) and "Plants and Soil" (49). Moves those lines to the
// Expense accounts of the same names (63, 66) and updates the manifest.
import "dotenv/config";
import { readFileSync, writeFileSync } from "node:fs";
import { QboRawClient } from "./qboRawClient.js";
const MOVE: Record<string, string> = { "46": "63", "49": "66" };
const path = "spike/fixtures/seed-manifest.json";
const manifest = JSON.parse(readFileSync(path, "utf8"));
const client = new QboRawClient();
let fixed = 0;
for (const [kind, bucket] of [["bill", "bills"], ["purchase", "purchases"]] as const) {
  for (const [note, ref] of Object.entries(manifest[bucket] as Record<string, { id: string; syncToken: string }>)) {
    if (!note.startsWith("VL history")) continue;
    const read = await client.query(`select * from ${kind === "bill" ? "Bill" : "Purchase"} where Id = '${ref.id}'`);
    const entity = (read.body as any)?.QueryResponse?.[kind === "bill" ? "Bill" : "Purchase"]?.[0];
    if (!entity) continue;
    let changed = false;
    for (const line of entity.Line ?? []) {
      const acct = line.AccountBasedExpenseLineDetail?.AccountRef;
      if (acct && MOVE[acct.value]) { acct.value = MOVE[acct.value]; delete acct.name; changed = true; }
    }
    if (!changed) continue;
    const res = await client.post(kind === "bill" ? "bill" : "purchase", { ...entity, sparse: false });
    if (res.status !== 200) throw new Error(`${note}: HTTP ${res.status} ${JSON.stringify(res.body).slice(0, 300)}`);
    const updated = (res.body as any)[kind === "bill" ? "Bill" : "Purchase"];
    (manifest[bucket] as any)[note] = { id: updated.Id, syncToken: updated.SyncToken };
    fixed++;
    process.stdout.write(`  [moved] ${note}\n`);
  }
}
manifest.accounts["Job Materials"] = "63";
manifest.accounts["Plants and Soil"] = "66";
writeFileSync(path, JSON.stringify(manifest, null, 2));
console.log(`Fixed ${fixed} records.`);
