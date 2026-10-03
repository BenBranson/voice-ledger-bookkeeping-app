// One-off probe (2026-10-02): QBO's own range totals to verify the Business Diagnosis. Read-only.
import "dotenv/config";
import { QboRawClient } from "./qboRawClient.js";
const c = new QboRawClient();
function find(rows: any, label: string): string | undefined {
  for (const r of rows?.Row ?? []) {
    if (r.Summary?.ColData?.[0]?.value === label) return r.Summary.ColData[1]?.value;
    if (r.ColData?.[0]?.value === label) return r.ColData[1]?.value;
    const n = find(r.Rows, label); if (n !== undefined) return n;
  }
}
for (const [s, e] of [["2025-10-01", "2026-09-30"], ["2026-07-01", "2026-09-30"], ["2025-07-01", "2025-09-30"], ["2026-04-01", "2026-06-30"]]) {
  const r: any = (await c.get("reports/ProfitAndLoss", { start_date: s, end_date: e })).body;
  console.log(s, "→", e, "| Income", find(r.Rows, "Total Income"), "| Net", find(r.Rows, "Net Income"), "| Fuel", find(r.Rows, "Fuel"), "| Job Materials (other)?", find(r.Rows, "Job Materials"));
}
