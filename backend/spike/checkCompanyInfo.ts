import "dotenv/config";
import { QboRawClient } from "./qboRawClient.js";
const c = new QboRawClient();
const direct = await c.get(`companyinfo/${c.realmId}`, {});
console.log("GET companyinfo:", direct.status, JSON.stringify(direct.body).slice(0, 300));
const q = await c.query("select * from CompanyInfo");
console.log("query CompanyInfo:", q.status, JSON.stringify((q.body as any)?.QueryResponse?.CompanyInfo?.[0]?.CompanyName ?? q.body).slice(0, 300));
