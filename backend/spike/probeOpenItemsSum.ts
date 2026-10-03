// One-off probe (2026-10-02): independent sum of AgedReceivableDetail open balances as of 2026-09-30. Read-only.
import "dotenv/config";
import { QboRawClient } from "./qboRawClient.js";
const c = new QboRawClient();
const r: any = (await c.get("reports/AgedReceivableDetail", { report_date: "2026-09-30" })).body;
let pos = 0, neg = 0; const credits: string[] = [];
const walk = (rows: any) => { for (const row of rows?.Row ?? []) { if (row.Rows) walk(row.Rows);
  if (row.ColData && !row.Header) { const v = Math.round(parseFloat(row.ColData.at(-1).value) * 100); if (v > 0) pos += v; else if (v < 0) { neg += v; credits.push(`${row.ColData[1].value} ${row.ColData[3].value} ${v / 100}`); } } } };
walk(r.Rows);
console.log("owed", pos / 100, "credits", neg / 100, "net", (pos + neg) / 100); console.log(credits.join("\n"));
