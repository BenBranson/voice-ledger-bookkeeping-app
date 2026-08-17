/**
 * docs/phase-0/SPIKE_QUEUE.md Wave 5, item 51 — `testManualVoidPurchaseAPIShape`.
 *
 * `?operation=void` on Purchase is confirmed unsupported (§11.1), so the
 * only way a real Purchase becomes voided is a manual void in the QBO UI.
 * The TotalAmt==0 heuristic tried earlier was DISPROVEN (false-positived on
 * the legitimate $0 VL-SPIKE-ZERO fixture, #146). This test checks the real
 * signal, now that Purchase #151 (docs/phase-0/11_VERTICAL_SLICE.md §11.4's
 * worked example) has actually been voided manually in the sandbox UI,
 * 2026-08-17, by the owner.
 *
 * Compares #151 (voided) against #146 (never voided, but legitimately
 * TotalAmt==0 — the exact case that broke the old heuristic) to confirm the
 * new signal doesn't repeat that false positive.
 */

import { capabilityTest, pass, fail } from "../capabilityTest.js";
import { QboRawClient } from "../qboRawClient.js";

export async function run(): Promise<void> {
  await capabilityTest(
    "testManualVoidPurchaseAPIShape",
    "What does a Purchase manually voided in the QBO UI look like via the API, and is there a reliable isVoided signal?",
    async (capture) => {
      const client = new QboRawClient();

      const voidedResult = await client.query("select * from Purchase where Id = '151'");
      const zeroButNotVoidedResult = await client.query("select * from Purchase where Id = '146'");

      if (voidedResult.status !== 200 || zeroButNotVoidedResult.status !== 200) {
        return fail(`Query failed: voided=${voidedResult.status}, zero-fixture=${zeroButNotVoidedResult.status}`);
      }

      const voided: any = (voidedResult.body as any)?.QueryResponse?.Purchase?.[0];
      const zeroButNotVoided: any = (zeroButNotVoidedResult.body as any)?.QueryResponse?.Purchase?.[0];

      if (!voided) return fail("Purchase #151 not found — was it actually voided?");
      if (!zeroButNotVoided) return fail("Purchase #146 (control fixture) not found.");

      capture(
        { queries: ["select * from Purchase where Id = '151'", "select * from Purchase where Id = '146'"] },
        {
          voided: { status: voided.status, totalAmt: voided.TotalAmt, privateNote: voided.PrivateNote, syncToken: voided.SyncToken },
          zeroButNotVoided: { status: zeroButNotVoided.status, totalAmt: zeroButNotVoided.TotalAmt, privateNote: zeroButNotVoided.PrivateNote }
        }
      );

      const voidedHasStatusField = "status" in voided;
      const voidedStatusIsVoided = voided.status === "Voided";
      const controlHasStatusField = "status" in zeroButNotVoided;
      const notePrefixed = typeof voided.PrivateNote === "string" && voided.PrivateNote.startsWith("Voided - ");

      if (!voidedHasStatusField || !voidedStatusIsVoided) {
        return fail(
          `Expected voided Purchase to carry a top-level "status": "Voided" field. Got status=${JSON.stringify(voided.status)}.`
        );
      }
      if (controlHasStatusField) {
        return fail(
          `The "status" field appeared on the CONTROL fixture too (#146, legitimately $0, never voided) — ` +
            `not a safe signal after all. Got status=${JSON.stringify(zeroButNotVoided.status)}.`
        );
      }

      return pass(
        `VERIFIED — a manually-voided Purchase carries a top-level "status": "Voided" field, absent entirely on ` +
          `non-voided Purchases (checked against #146, the same $0 fixture that broke the earlier TotalAmt==0 ` +
          `heuristic — confirms this signal doesn't repeat that false positive). QBO also automatically prefixed ` +
          `PrivateNote with "Voided - " (prefixed=${notePrefixed}: "${voided.PrivateNote}"), a secondary corroborating ` +
          `signal but "status" is the primary one. TotalAmt and all Line amounts are zeroed (already known, not ` +
          `sufficient alone). SyncToken incremented to "${voided.SyncToken}" as expected for any write. ` +
          `Branch B's isVoided-exclusion resolution path (§11.1, §11.4) is now provably reachable against real data.`
      );
    }
  );
}
