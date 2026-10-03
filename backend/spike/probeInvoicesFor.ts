// One-off probe (2026-10-02): did a timed-out invoice create land? Read-only.
import "dotenv/config";
import { QboRawClient } from "./qboRawClient.js";
const c = new QboRawClient();
const r: any = (await c.query("select Id, TxnDate, TotalAmt, CustomerRef, PrivateNote from Invoice where TxnDate >= '2026-09-01' and TxnDate <= '2026-09-30' maxresults 200")).body;
for (const i of r.QueryResponse.Invoice ?? []) if (/^VLT/.test(i.CustomerRef?.name ?? "") || /VLT/.test(i.PrivateNote ?? "")) console.log(i.Id, i.TxnDate, i.TotalAmt, i.CustomerRef?.name, i.PrivateNote);
