/**
 * Entry point for Wave 5 (docs/phase-0/SPIKE_QUEUE.md) — items 49-50 only.
 * Item 51 (testManualVoidPurchaseAPIShape) is not run here: it requires a
 * manual action in the QBO UI (voiding Purchase #151) that this script
 * cannot perform, unlike 49/50 which are pure reads.
 *
 * Separate entry point, same reasoning as runWave3.ts: reruns of this wave
 * shouldn't re-churn earlier waves' already-fixtured results.
 */

import "dotenv/config";
import { emitResults } from "./capabilityTest.js";
import { run as runCategorizationProvenance } from "./tests/11-categorization-provenance.spike.js";
import { run as runReconciledTransactionDetection } from "./tests/12-reconciled-transaction-detection.spike.js";

async function main(): Promise<void> {
  await runCategorizationProvenance(); // item 49
  await runReconciledTransactionDetection(); // item 50

  emitResults();
}

main().catch((error) => {
  process.stderr.write(`Wave 5 spike run failed: ${error instanceof Error ? error.stack : error}\n`);
  process.exit(1);
});
