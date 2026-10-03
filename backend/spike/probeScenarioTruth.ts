// One-off probe (2026-10-02): QBO's own figures for the September scenario batch. Read-only.
import "dotenv/config";
import { QboRawClient } from "./qboRawClient.js";
const c = new QboRawClient();
const inv: any = (await c.get("invoice/834")).body.Invoice;
console.log("Invoice 834 total", inv.TotalAmt, "tax", inv.TxnTaxDetail?.TotalTax, "balance", inv.Balance);
const cm: any = (await c.get("creditmemo/838")).body.CreditMemo;
console.log("CreditMemo 838 total", cm.TotalAmt, "remaining credit", cm.RemainingCredit, "balance", cm.Balance);
function rows(r: any, depth = 0, out: string[] = []) {
  for (const row of r?.Row ?? []) {
    if (row.Header) out.push("  ".repeat(depth) + row.Header.ColData.map((c: any) => c.value).join(" | "));
    if (row.ColData) out.push("  ".repeat(depth) + row.ColData.map((c: any) => c.value).join(" | "));
    if (row.Rows) rows(row.Rows, depth + 1, out);
    if (row.Summary) out.push("  ".repeat(depth) + "= " + row.Summary.ColData.map((c: any) => c.value).join(" | "));
  }
  return out;
}
for (const [name, params] of [["AgedReceivables", {}], ["AgedPayables", {}], ["ProfitAndLoss", { start_date: "2026-09-01", end_date: "2026-09-30" }]] as const) {
  const r: any = (await c.get(`reports/${name}`, params as any)).body;
  const lines = rows(r.Rows).filter((l) => /VLT|TOTAL|Total|Cost of Goods|Gross|Net Income|Sales of Product|Fuel|Uncategorized|Meals/i.test(l));
  console.log(`\n## ${name}`, JSON.stringify(r.Columns?.Column?.map((x: any) => x.ColTitle)));
  console.log(lines.join("\n"));
}
