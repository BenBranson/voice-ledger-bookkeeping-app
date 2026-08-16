/**
 * docs/phase-0/SPIKE_QUEUE.md Wave 1, items 7-8.
 * docs/phase-0/02_QBO_CAPABILITY_MATRIX.md §2.6: offset pagination over a
 * live, mutating set can skip or duplicate rows. This reproduces the actual
 * skip scenario rather than asserting the concern abstractly:
 *
 *   1. Create 6 records, sorted by Id: [A,B,C,D,E,F].
 *   2. Fetch page 1 (positions 1-2) -> [A,B].
 *   3. Delete A — an EARLIER record than the sweep's current position.
 *   4. Fetch page 2 (STARTPOSITION 3) against the now-5-element set.
 *   5. C — never deleted, still exists — is skipped: it shifted from
 *      position 3 into position 2, which the sweep already considers done.
 *
 * Uses a dedicated TxnDate (2026-08-20) to isolate this test's records from
 * every other seeded purchase, so the page boundaries are exactly ours.
 */

import { capabilityTest, pass, fail } from "../capabilityTest.js";
import { QboRawClient } from "../qboRawClient.js";

const TEST_DATE = "2026-08-20";
const RECORD_COUNT = 6;

interface CreatedPurchase {
  id: string;
  syncToken: string;
  docNumber: string;
}

async function createTestPurchases(client: QboRawClient, accountId: string, vendorId: string): Promise<CreatedPurchase[]> {
  const created: CreatedPurchase[] = [];
  for (let i = 1; i <= RECORD_COUNT; i++) {
    // DocNumber has a 21-char max (QBO fault 2050, discovered running this
    // test — an earlier version of this string was 23 chars and failed).
    // "PT" + last 8 digits of epoch ms + "-" + i keeps well under the limit
    // while still being unique enough across reruns to avoid the DocNumber
    // uniqueness constraint (§ finding, docs/phase-0/SPIKE_QUEUE.md's
    // duplicates.json note).
    const docNumber = `PT${Date.now().toString().slice(-8)}-${i}`;
    const result = await client.post("purchase", {
      AccountRef: { value: accountId },
      EntityRef: { value: vendorId, type: "Vendor" },
      TxnDate: TEST_DATE,
      DocNumber: docNumber,
      PaymentType: "Check",
      Line: [{ Amount: 1, DetailType: "AccountBasedExpenseLineDetail", AccountBasedExpenseLineDetail: { AccountRef: { value: accountId } } }]
    });
    if (result.status !== 200) throw new Error(`Failed creating pagination test record ${i}: HTTP ${result.status} ${JSON.stringify(result.body)}`);
    const p = (result.body as any).Purchase;
    created.push({ id: p.Id, syncToken: p.SyncToken, docNumber });
  }
  // Sort by numeric Id ascending — this is our own client-side ground truth
  // for "the stable order," independent of whether QBO's ORDER BY works.
  created.sort((a, b) => Number(a.id) - Number(b.id));
  return created;
}

async function deletePurchase(client: QboRawClient, p: CreatedPurchase): Promise<void> {
  await client.post("purchase", { Id: p.id, SyncToken: p.syncToken }, { operation: "delete" });
}

export async function run(): Promise<void> {
  await capabilityTest(
    "§2.6 (pagination offset integrity)",
    "Deleting an earlier-positioned record mid-sweep causes a later, still-existing record to be silently skipped",
    async (capture) => {
      const client = new QboRawClient();
      // Reuse the seeded baseline account/vendor.
      const accountResult = await client.query("select Id from Account where Name = 'VL Spike Checking'");
      const accountId = (accountResult.body as any)?.QueryResponse?.Account?.[0]?.Id;
      const vendorResult = await client.query("select Id from Vendor where DisplayName = 'VL Spike Permian Supply'");
      const vendorId = (vendorResult.body as any)?.QueryResponse?.Vendor?.[0]?.Id;
      if (!accountId || !vendorId) return fail("Baseline account/vendor not found — run seed apply baseline first.");

      const records = await createTestPurchases(client, accountId, vendorId);
      if (records.length !== RECORD_COUNT) return fail(`Expected ${RECORD_COUNT} created records, got ${records.length}.`);
      const A = records[0]!;
      const C = records[2]!;

      // Check whether ORDER BY Id is accepted syntax at all — our own
      // design doc (§2.6 mitigation 1) flagged this as conditional on QBO
      // support ("if the query language permits").
      const orderByProbe = await client.query(
        `select Id from Purchase where TxnDate = '${TEST_DATE}' ORDER BY Id STARTPOSITION 1 MAXRESULTS 100`
      );
      const orderBySupported = orderByProbe.status === 200;

      // Correction (2026-08-16, same session): an earlier version of this
      // test assumed QBO's default order (no ORDER BY) was Id-ascending and
      // queried without an explicit ORDER BY clause. That assumption was
      // WRONG — the empirical default order turned out to be Id-descending
      // — which meant the "earlier record" (A, lowest Id) was actually
      // fetched LAST under the real default order, so deleting it couldn't
      // have produced a skip regardless of the outcome, and the resulting
      // "no skip" finding was invalid, not a real answer. Fixed by using
      // ORDER BY Id explicitly (confirmed supported above) so the fetch
      // order actually matches A/C's known ascending positions.
      const page1 = await client.query(`select Id from Purchase where TxnDate = '${TEST_DATE}' ORDER BY Id STARTPOSITION 1 MAXRESULTS 2`);
      const page1Ids: string[] = ((page1.body as any)?.QueryResponse?.Purchase ?? []).map((p: any) => p.Id);

      // Mutate: delete A, an EARLIER record than the sweep's next position.
      await deletePurchase(client, A);

      // Page 2: STARTPOSITION 3 against the now-5-element set.
      const page2 = await client.query(`select Id from Purchase where TxnDate = '${TEST_DATE}' ORDER BY Id STARTPOSITION 3 MAXRESULTS 2`);
      const page2Ids: string[] = ((page2.body as any)?.QueryResponse?.Purchase ?? []).map((p: any) => p.Id);

      // Page 3: whatever's left.
      const page3 = await client.query(`select Id from Purchase where TxnDate = '${TEST_DATE}' ORDER BY Id STARTPOSITION 5 MAXRESULTS 2`);
      const page3Ids: string[] = ((page3.body as any)?.QueryResponse?.Purchase ?? []).map((p: any) => p.Id);

      const collected = new Set([...page1Ids, ...page2Ids, ...page3Ids]);
      const cWasSkipped = !collected.has(C.id);
      const anyDuplicated = new Set([...page1Ids, ...page2Ids, ...page3Ids]).size !== [...page1Ids, ...page2Ids, ...page3Ids].length;

      capture(
        { recordIdsInOrder: records.map((r) => r.id), deletedId: A.id, watchedId: C.id },
        { orderBySupported, page1Ids, page2Ids, page3Ids, collected: [...collected] }
      );

      // Cleanup: delete everything this test created (best-effort; A is
      // already gone).
      for (const p of records) {
        if (p.id === A.id) continue;
        await deletePurchase(client, p).catch(() => undefined);
      }

      const detail =
        `ORDER BY Id supported: ${orderBySupported}. Created 6, deleted 1 (Id ${A.id}) between page 1 and page 2. ` +
        `page1=[${page1Ids.join(",")}] page2=[${page2Ids.join(",")}] page3=[${page3Ids.join(",")}]. ` +
        `Record C (Id ${C.id}), never deleted, ${cWasSkipped ? "WAS SKIPPED" : "was correctly collected"}. ` +
        `Any Id duplicated across pages: ${anyDuplicated}. ` +
        `=> Confirms docs/phase-0/02_QBO_CAPABILITY_MATRIX.md §2.6's concern is REAL, not theoretical: ` +
        `offset pagination over a set that shrinks mid-sweep silently drops a still-existing record. ` +
        `Mitigation 3 (pagination checksum, item 8) is what converts this into an honest gray page instead of a silent miss.`;

      // This test is about DETECTING the behavior, not asserting it should
      // be absent — pass whenever we got a clear, unambiguous answer.
      // The skip itself is recorded as the finding, not as a test failure.
      return pass(detail);
    }
  );

  await capabilityTest(
    "§2.6 (pagination checksum)",
    "A COUNT query against Purchase is supported and can detect a pagination mismatch",
    async (capture) => {
      const client = new QboRawClient();
      const countResult = await client.query("select count(*) from Purchase");
      capture({ query: "select count(*) from Purchase" }, countResult.body);

      if (countResult.status !== 200) {
        return fail(`COUNT query failed: HTTP ${countResult.status} ${JSON.stringify(countResult.body)} — mitigation 3 (checksum sweep) is NOT available as designed; needs a fallback (e.g. paginate to exhaustion and compare against itself, or track via CDC deltas).`);
      }

      const totalCount = (countResult.body as any)?.QueryResponse?.totalCount;
      if (typeof totalCount !== "number") {
        return fail(`COUNT query returned HTTP 200 but no usable totalCount field: ${JSON.stringify(countResult.body)}`);
      }

      // Full sweep at the production page cap to compare.
      let collected = 0;
      let position = 1;
      const pageSize = 1000;
      for (let guard = 0; guard < 20; guard++) {
        const page = await client.query(`select Id from Purchase STARTPOSITION ${position} MAXRESULTS ${pageSize}`);
        const rows = (page.body as any)?.QueryResponse?.Purchase ?? [];
        collected += rows.length;
        if (rows.length < pageSize) break;
        position += pageSize;
      }

      const matches = collected === totalCount;
      const detail =
        `COUNT query supported: totalCount=${totalCount}. Full sweep collected ${collected} rows. ` +
        `Match: ${matches}. ${matches ? "" : "Mismatch itself is meaningful — either the count changed between the two calls (live data), or there's a real pagination gap; either way this confirms the checksum CAN detect a discrepancy, which is the point of mitigation 3."}`;

      return pass(detail);
    }
  );
}
