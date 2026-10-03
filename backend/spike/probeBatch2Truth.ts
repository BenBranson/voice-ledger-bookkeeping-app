// One-off probe (2026-10-02): QBO's own figures for scenario batch 2. Read-only.
import "dotenv/config";
import { QboRawClient } from "./qboRawClient.js";
const c = new QboRawClient();
const get = async (p: string, q: Record<string, string> = {}) => (await c.get(p, q)).body as any;
const refund = (await get("refundreceipt/848")).RefundReceipt;
console.log("Refund total", refund.TotalAmt, "tax", refund.TxnTaxDetail?.TotalTax);
const inv = (await get("invoice/843")).Invoice;
console.log("NV invoice BillAddr", JSON.stringify(inv.BillAddr), "ShipAddr", JSON.stringify(inv.ShipAddr));
function rows(r: any, out: string[] = [], d = 0) { for (const row of r?.Row ?? []) {
  if (row.Header) out.push("  ".repeat(d) + row.Header.ColData.map((x: any) => x.value).join(" | "));
  if (row.ColData) out.push("  ".repeat(d) + row.ColData.map((x: any) => x.value).join(" | "));
  if (row.Rows) rows(row.Rows, out, d + 1);
  if (row.Summary) out.push("  ".repeat(d) + "= " + row.Summary.ColData.map((x: any) => x.value).join(" | ")); } return out; }
const pl = await get("reports/ProfitAndLoss", { start_date: "2026-10-01", end_date: "2026-10-31" });
console.log("\n## Oct P&L\n" + rows(pl.Rows).join("\n"));
for (const k of ["AgedReceivables", "AgedPayables"]) {
  const r = await get(`reports/${k}`, { report_date: "2026-10-31" });
  console.log(`\n## ${k} @10-31\n` + rows(r.Rows).filter((l) => /VLT|TOTAL/.test(l)).join("\n"));
}
const bs = await get("reports/BalanceSheet", { start_date: "2026-10-01", end_date: "2026-10-31" });
console.log("\n## BS lines\n" + rows(bs.Rows).filter((l) => /Checking|Savings|Loan Payable|Arizona|Inventory Asset|TOTAL/.test(l)).join("\n"));
