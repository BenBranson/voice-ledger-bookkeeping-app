/**
 * Entry point for Wave 3 (writes) plus the three additional void tests from
 * Decision 3, 2026-08-16. Separate from run.ts (which covers the gate +
 * Wave 1) so re-running Wave 3 doesn't also re-churn Wave 1's already-
 * verified, already-fixtured results with more sandbox writes.
 *
 * Fixtures from both entry points land in the same spike/fixtures/
 * directory and are merged by regenerateMatrix.ts, which keeps the latest
 * result per matrixRow regardless of which entry point produced it.
 */

import "dotenv/config";
import { emitResults } from "./capabilityTest.js";
import { run as runAccountWrites } from "./tests/06-account-writes.spike.js";
import { run as runSparseUpdates } from "./tests/07-sparse-updates.spike.js";
import { run as runBatchAndAttachment } from "./tests/08-batch-and-attachment.spike.js";
import { run as runJeAndTransfer } from "./tests/09-je-and-transfer.spike.js";
import { run as runVoidOtherEntities } from "./tests/10-void-other-entities.spike.js";

async function main(): Promise<void> {
  await runAccountWrites(); // items 12-15
  await runSparseUpdates(); // items 16-17 — the ones that matter most
  await runBatchAndAttachment(); // items 18-19
  await runJeAndTransfer(); // items 20-21
  await runVoidOtherEntities(); // Decision 3 addition: void on Bill/JournalEntry/BillPayment

  emitResults();
}

main().catch((error) => {
  process.stderr.write(`Wave 3 spike run failed: ${error instanceof Error ? error.stack : error}\n`);
  process.exit(1);
});
