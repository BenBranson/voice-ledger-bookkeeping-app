/**
 * The capability-spike test harness. docs/phase-0/12_TEST_STRATEGY.md §12.5:
 * "§2's matrix is generated from T3 test results. It is not hand-edited...
 * A human cannot promote a row to VERIFIED by typing."
 *
 * This is the TypeScript adaptation of the Swift `@CapabilityTest` sketch in
 * that document — the backend is TS, so the spike harness lives here rather
 * than in a separate Swift-only tool. The shape (row id, claim, request/
 * response capture, fixture emission) is unchanged.
 *
 * These tests require a live sandbox connection and are NOT part of `npm
 * test` (test/*.test.ts) — they're gated behind environment variables and
 * run via `npm run spike`. Every capability test in
 * docs/phase-0/SPIKE_QUEUE.md corresponds to one function here.
 */

import { writeFileSync, mkdirSync } from "node:fs";
import { dirname, join } from "node:path";

export type CapabilityStatus = "VERIFIED" | "DISPROVEN" | "SKIPPED_NO_SANDBOX";

export interface CapabilityResult {
  readonly matrixRow: string;
  readonly claim: string;
  readonly status: CapabilityStatus;
  readonly verifiedAt: string | null;
  readonly detail: string;
  readonly request?: unknown;
  readonly response?: unknown;
  readonly negativeEvidence?: readonly string[];
}

const results: CapabilityResult[] = [];

export function sandboxIsConfigured(): boolean {
  return Boolean(process.env.QBO_SANDBOX_CLIENT_ID && process.env.QBO_SPIKE_REALM_ID);
}

/**
 * Runs one capability test. `fn` receives a `capture` helper for recording
 * the request/response fixture. Skips (not fails) when no sandbox is
 * configured, so `npm run spike` is safe to run before Wave 0 setup is
 * complete — it will just report everything as skipped rather than
 * erroring, which is the honest state at that point.
 */
export async function capabilityTest(
  matrixRow: string,
  claim: string,
  fn: (capture: CaptureFn) => Promise<CapabilityOutcome>
): Promise<void> {
  if (!sandboxIsConfigured()) {
    results.push({
      matrixRow,
      claim,
      status: "SKIPPED_NO_SANDBOX",
      verifiedAt: null,
      detail: "QBO_SANDBOX_CLIENT_ID / QBO_SPIKE_REALM_ID not set — see docs/phase-0/SPIKE_QUEUE.md Wave 0."
    });
    return;
  }

  let captured: { request?: unknown; response?: unknown } = {};
  const capture: CaptureFn = (request, response) => {
    captured = { request, response };
  };

  try {
    const outcome = await fn(capture);
    results.push({
      matrixRow,
      claim,
      status: outcome.disproven ? "DISPROVEN" : "VERIFIED",
      verifiedAt: new Date().toISOString(),
      detail: outcome.detail,
      request: captured.request,
      response: captured.response,
      // exactOptionalPropertyTypes forbids `key: undefined` — only spread
      // the field in when it actually has a value.
      ...(outcome.negativeEvidence ? { negativeEvidence: outcome.negativeEvidence } : {})
    });
  } catch (error) {
    results.push({
      matrixRow,
      claim,
      status: "DISPROVEN",
      verifiedAt: new Date().toISOString(),
      detail: error instanceof Error ? error.message : String(error),
      request: captured.request,
      response: captured.response
    });
  }
}

export type CaptureFn = (request: unknown, response: unknown) => void;

export interface CapabilityOutcome {
  readonly disproven: boolean;
  readonly detail: string;
  readonly negativeEvidence?: readonly string[];
}

export function pass(detail: string): CapabilityOutcome {
  return { disproven: false, detail };
}

export function fail(detail: string): CapabilityOutcome {
  return { disproven: true, detail };
}

/** For negative-capability tests (§12.5's "negative capability tests"). */
export function confirmedAbsent(searched: readonly string[]): CapabilityOutcome {
  return { disproven: false, detail: "Confirmed absent — see negativeEvidence.", negativeEvidence: searched };
}

/**
 * Writes every result collected so far to a fixture directory and prints a
 * summary table. This is what §12.5 means by "the matrix is generated from
 * test results" — a future script reads these JSON files to regenerate
 * docs/phase-0/02_QBO_CAPABILITY_MATRIX.md rather than a human editing them.
 */
export function emitResults(): void {
  const outDir = join(process.cwd(), "spike", "fixtures");
  mkdirSync(outDir, { recursive: true });
  const path = join(outDir, `results-${new Date().toISOString().replace(/[:.]/g, "-")}.json`);
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, JSON.stringify(results, null, 2));

  const counts = results.reduce<Record<CapabilityStatus, number>>(
    (acc, r) => ({ ...acc, [r.status]: (acc[r.status] ?? 0) + 1 }),
    { VERIFIED: 0, DISPROVEN: 0, SKIPPED_NO_SANDBOX: 0 }
  );

  process.stdout.write(`\nCapability spike results: ${results.length} test(s)\n`);
  process.stdout.write(`  VERIFIED:            ${counts.VERIFIED}\n`);
  process.stdout.write(`  DISPROVEN:            ${counts.DISPROVEN}\n`);
  process.stdout.write(`  SKIPPED_NO_SANDBOX:   ${counts.SKIPPED_NO_SANDBOX}\n`);
  process.stdout.write(`Fixture written to ${path}\n`);

  for (const r of results.filter((r) => r.status === "DISPROVEN")) {
    process.stdout.write(`\nDISPROVEN — row ${r.matrixRow}: ${r.claim}\n  ${r.detail}\n`);
  }
}

export function getResults(): readonly CapabilityResult[] {
  return results;
}
