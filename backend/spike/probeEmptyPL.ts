// One-off probe (2026-10-02): what QBO returns for a P&L month with no activity yet. Read-only.
import "dotenv/config";
import { QboRawClient } from "./qboRawClient.js";
const c = new QboRawClient();
const r: any = (await c.get("reports/ProfitAndLoss", { start_date: "2026-10-01", end_date: "2026-10-31" })).body;
console.log(JSON.stringify(r.Header?.Option), "\nRows:", JSON.stringify(r.Rows).slice(0, 600));
