// One-off probe (2026-10-02): account names/types for the scenario seed. Read-only.
import "dotenv/config";
import { QboRawClient } from "./qboRawClient.js";
const c = new QboRawClient();
const r: any = (await c.query("select Id, Name, AccountType, Active from Account maxresults 200")).body;
for (const a of r.QueryResponse.Account) console.log(a.Id.padStart(10), a.AccountType.padEnd(22), a.Name);
