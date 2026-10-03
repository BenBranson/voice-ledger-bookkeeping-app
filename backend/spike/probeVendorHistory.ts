// One-off probe (2026-10-02): existing vendor patterns to plant price-jump and anomaly cases against. Read-only.
import "dotenv/config";
import { QboRawClient } from "./qboRawClient.js";
const c = new QboRawClient();
const r: any = (await c.query("select Id, TxnDate, TotalAmt, EntityRef from Purchase where TxnDate >= '2026-05-01' maxresults 1000")).body;
const by: Record<string, { d: string; a: number }[]> = {};
for (const p of r.QueryResponse.Purchase ?? []) { const n = p.EntityRef?.name ?? "(none)"; (by[n] ??= []).push({ d: p.TxnDate, a: p.TotalAmt }); }
for (const [n, xs] of Object.entries(by).sort()) console.log(n.padEnd(40), xs.sort((a, b) => a.d.localeCompare(b.d)).map(x => `${x.d.slice(5)}:${x.a}`).join(" "));
const latest: any = (await c.query("select Id, TxnDate from Purchase where TxnDate >= '2026-09-01' maxresults 50")).body;
console.log("\nSeptember purchases already:", (latest.QueryResponse.Purchase ?? []).length);
