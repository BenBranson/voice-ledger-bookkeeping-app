/**
 * Entry point for `npm run spike`. Runs every capability test file under
 * spike/tests/ in the order defined by docs/phase-0/SPIKE_QUEUE.md, then
 * writes the combined fixture and prints a summary.
 *
 * Safe to run before Wave 0 setup is complete — with no sandbox configured,
 * every test reports SKIPPED_NO_SANDBOX rather than failing, so this can be
 * used to sanity-check the harness itself before real credentials exist.
 */

import "dotenv/config";
import { emitResults } from "./capabilityTest.js";
import { run as runGateTests } from "./tests/00-purchase-void.spike.js";
import { run as runConnectionReads } from "./tests/01-connection-reads.spike.js";
import { run as runEntityReads } from "./tests/02-entity-reads.spike.js";
import { run as runPagination } from "./tests/03-pagination.spike.js";
import { run as runCdcAndLimits } from "./tests/04-cdc-and-limits.spike.js";
import { run as runReports } from "./tests/05-reports.spike.js";

async function main(): Promise<void> {
  // Deliberately sequential, matching docs/phase-0/SPIKE_QUEUE.md's ordering
  // ("later items assume earlier ones passed") — not run in parallel.
  await runGateTests(); // items 1-2, "the gate"
  await runConnectionReads(); // Wave 1, items 3-4
  await runEntityReads(); // Wave 1, items 5-6
  await runPagination(); // Wave 1, items 7-8
  await runCdcAndLimits(); // Wave 1, items 9-10
  await runReports(); // Wave 1, item 11

  emitResults();
}

main().catch((error) => {
  process.stderr.write(`Spike run failed: ${error instanceof Error ? error.stack : error}\n`);
  process.exit(1);
});
