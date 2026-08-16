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
import { run as runPurchaseVoidTests } from "./tests/00-purchase-void.spike.js";

async function main(): Promise<void> {
  // Deliberately sequential, matching docs/phase-0/SPIKE_QUEUE.md's ordering
  // ("later items assume earlier ones passed") — not run in parallel.
  await runPurchaseVoidTests();

  // Additional spike/tests/NN-*.spike.ts files land here as later
  // SPIKE_QUEUE.md items get implemented — each import + one call, in queue
  // order.

  emitResults();
}

main().catch((error) => {
  process.stderr.write(`Spike run failed: ${error instanceof Error ? error.stack : error}\n`);
  process.exit(1);
});
