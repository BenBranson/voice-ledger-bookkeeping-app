// One-off probe (2026-10-02): AgedReceivableDetail / AgedPayableDetail shape as of a date. Read-only.
import "dotenv/config";
import { QboRawClient } from "./qboRawClient.js";
const c = new QboRawClient();
for (const kind of ["AgedReceivableDetail", "AgedPayableDetail"]) {
  const r: any = (await c.get(`reports/${kind}`, { report_date: "2026-09-30" })).body;
  console.log(`\n## ${kind}`, JSON.stringify(r.Columns?.Column?.map((x: any) => x.ColTitle + "/" + x.ColType)));
  console.log("Options:", JSON.stringify(r.Header?.Option));
  let n = 0;
  const walk = (rows: any, d = 0) => { for (const row of rows?.Row ?? []) {
    if (row.Header) console.log(" ".repeat(d * 2) + "H:", row.Header.ColData.map((x: any) => x.value).join(" | "));
    if (row.ColData && n++ < 6) console.log(" ".repeat(d * 2) + "D:", JSON.stringify(row.ColData.map((x: any) => x.value + (x.id ? "#" + x.id : ""))));
    if (row.Rows) walk(row.Rows, d + 1);
    if (row.Summary) console.log(" ".repeat(d * 2) + "S:", row.Summary.ColData.map((x: any) => x.value).join(" | "));
  } };
  walk(r.Rows);
}
