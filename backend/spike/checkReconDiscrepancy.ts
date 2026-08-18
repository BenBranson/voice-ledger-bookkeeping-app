// Spike for VL-FORCED-RECON-001 (2026-08-18). Confirmed that a forced
// reconciliation adjustment is visible via the Profit & Loss report, as an
// "Other Expenses" line named "Reconciliation Discrepancies" — after two
// other hypotheses were tried and disproven first: `Account.CurrentBalance`
// on the auto-created discrepancy account read 0 (not meaningful for
// Expense-classified accounts), and no `JournalEntry` was created for the
// adjustment either. See docs/VOICE_LEDGER_HANDOFF.md's VL-FORCED-RECON-001
// entry and Sources/Core/ForcedReconciliationRule.swift.
import "dotenv/config";
import { QboRawClient } from "./qboRawClient.js";

const client = new QboRawClient();
const result = await client.get("reports/ProfitAndLoss", { start_date: "2026-07-01", end_date: "2026-08-18" });
console.log(JSON.stringify(result.body, null, 2));
