/**
 * Entry point for Wave 5 (docs/phase-0/SPIKE_QUEUE.md) — items 49-51.
 * Item 51 (testManualVoidPurchaseAPIShape) requires Purchase #151 to
 * already be manually voided in the QBO UI before this runs — that step
 * can't be automated from here, but the read/verification itself can be
 * once it's done (done 2026-08-17).
 *
 * Separate entry point, same reasoning as runWave3.ts: reruns of this wave
 * shouldn't re-churn earlier waves' already-fixtured results.
 */

import "dotenv/config";
import { emitResults } from "./capabilityTest.js";
import { run as runCategorizationProvenance } from "./tests/11-categorization-provenance.spike.js";
import { run as runReconciledTransactionDetection } from "./tests/12-reconciled-transaction-detection.spike.js";
import { run as runManualVoidPurchaseShape } from "./tests/13-manual-void-purchase-shape.spike.js";

async function main(): Promise<void> {
  await runCategorizationProvenance(); // item 49
  await runReconciledTransactionDetection(); // item 50
  await runManualVoidPurchaseShape(); // item 51 — requires #151 already voided manually in the QBO UI first

  emitResults();
}

main().catch((error) => {
  process.stderr.write(`Wave 5 spike run failed: ${error instanceof Error ? error.stack : error}\n`);
  process.exit(1);
});
