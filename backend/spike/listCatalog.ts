// Read-only: prints the sandbox's accounts, customers, and items for seed planning.
import "dotenv/config";
import { QboRawClient } from "./qboRawClient.js";
const c = new QboRawClient();
const acc = (await c.query("select Id, Name, AccountType, AccountSubType, Active, CurrentBalance from Account maxresults 1000")).body as any;
for (const a of acc.QueryResponse.Account ?? []) console.log(`ACCT ${a.Id}\t${a.AccountType}\t${a.Name}\t${a.Active}\t${a.CurrentBalance}`);
const cus = (await c.query("select Id, DisplayName, Balance from Customer maxresults 1000")).body as any;
for (const x of cus.QueryResponse.Customer ?? []) console.log(`CUST ${x.Id}\t${x.DisplayName}\t${x.Balance}`);
const items = (await c.query("select Id, Name, Type, UnitPrice from Item maxresults 1000")).body as any;
for (const x of items.QueryResponse.Item ?? []) console.log(`ITEM ${x.Id}\t${x.Type}\t${x.Name}\t${x.UnitPrice}`);
const ven = (await c.query("select Id, DisplayName from Vendor maxresults 1000")).body as any;
console.log("VENDORS", (ven.QueryResponse.Vendor ?? []).map((v: any) => v.DisplayName).join(" | "));
