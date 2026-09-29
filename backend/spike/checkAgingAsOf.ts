// Read-only check (2026-09-29): does AgedReceivables honor report_date, and does it then tie to the Balance Sheet's A/R at that date?
import "dotenv/config";
import { QboRawClient } from "./qboRawClient.js";
const c = new QboRawClient();
function grand(body: any): string {
  const rows = body?.Rows?.Row ?? [];
  const total = rows.find((r: any) => r.group === "GrandTotal")?.Summary ?? rows.at(-1)?.Summary;
  return JSON.stringify(total?.ColData?.map((x: any) => x.value));
}
for (const date of ["2026-08-31", "2026-07-31"]) {
  const ar = await c.get(`reports/AgedReceivables`, { report_date: date });
  const bs = await c.get(`reports/BalanceSheet`, { start_date: date.slice(0, 8) + "01", end_date: date });
  const find = (rows: any[]): any => { for (const r of rows ?? []) { if (r.Summary?.ColData?.[0]?.value === "Total Accounts Receivable") return r.Summary.ColData[1].value; const x = find(r.Rows?.Row); if (x) return x; } };
  console.log(date, "aging header date:", (ar.body as any)?.Header?.EndPeriod ?? (ar.body as any)?.Header?.ReportBasis, "| aging total:", grand(ar.body), "| BS A/R:", find((bs.body as any)?.Rows?.Row));
}
const today = await c.get(`reports/AgedReceivables`, {});
console.log("no date → aging total:", grand(today.body));
