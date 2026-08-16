/**
 * docs/phase-0/SPIKE_QUEUE.md Wave 1, items 3-4.
 */

import { capabilityTest, pass, fail } from "../capabilityTest.js";
import { QboRawClient } from "../qboRawClient.js";

export async function run(): Promise<void> {
  await capabilityTest(
    "C1",
    "CompanyInfo is a live, non-cached, timestamped read; its error shape on an invalid/revoked token is well-formed",
    async (capture) => {
      const client = new QboRawClient();

      // Latency distribution across 3 sequential calls — cheap signal for
      // "is this hitting a server cache" (suspiciously flat near-0ms would
      // suggest caching; QBO's docs don't state either way).
      const latencies: number[] = [];
      let lastBody: unknown;
      for (let i = 0; i < 3; i++) {
        const r = await client.get(`companyinfo/${client.realmId}`);
        if (r.status !== 200) return fail(`Call ${i + 1}/3 returned HTTP ${r.status}: ${JSON.stringify(r.body)}`);
        latencies.push(r.latencyMs);
        lastBody = r.body;
      }

      // Rate-limit / metering headers, if QBO exposes any (checked here
      // since this is the cheapest, most frequently called read).
      const last = await client.get(`companyinfo/${client.realmId}`);
      const meteringHeaders = Object.keys(last.headers).filter((h) => /rate|limit|quota|throttle/i.test(h));

      // Error shape on an invalid token — NOT a genuinely revoked token
      // (revoking would require disconnecting and re-authorizing, which
      // this run doesn't do). This is a deliberately corrupted bearer token,
      // which is the closest safe proxy without disrupting the connection
      // Wave 1 depends on. Labeled as such, not oversold.
      const invalidTokenResult = await client.getWithOverrideToken(
        `companyinfo/${client.realmId}`,
        "invalid-token-for-capability-spike-probe-only"
      );

      capture(
        { note: "3x companyinfo read + 1x invalid-token probe" },
        { latencies, meteringHeaders, invalidTokenStatus: invalidTokenResult.status, invalidTokenBody: invalidTokenResult.body, sample: lastBody }
      );

      const detail =
        `3 live reads succeeded, latencies [${latencies.join(", ")}]ms. ` +
        `Metering-related response headers found: ${meteringHeaders.length ? meteringHeaders.join(", ") : "none"}. ` +
        `Invalid-token probe (NOT a genuinely revoked token — see comment) returned HTTP ${invalidTokenResult.status}: ` +
        `${JSON.stringify(invalidTokenResult.body)}. ` +
        `Non-cached vs. cached is not independently verifiable from outside QBO's infrastructure; not claimed either way.`;

      return pass(detail);
    }
  );

  await capabilityTest(
    "C3 / 2.1",
    "Preferences read succeeds; AccountingInfoPrefs shape, tax-mode fields, and BookCloseDate presence",
    async (capture) => {
      const client = new QboRawClient();
      const result = await client.query("select * from Preferences");
      capture({ query: "select * from Preferences" }, result.body);

      if (result.status !== 200) return fail(`HTTP ${result.status}: ${JSON.stringify(result.body)}`);

      const prefs = (result.body as any)?.QueryResponse?.Preferences?.[0];
      if (!prefs) return fail(`200 but no Preferences object in response: ${JSON.stringify(result.body)}`);

      const accountingInfo = prefs.AccountingInfoPrefs;
      const bookCloseDate = accountingInfo?.BookCloseDate;
      const taxPrefs = prefs.TaxPrefs;
      const usingSalesTax = taxPrefs?.UsingSalesTax;

      const detail =
        `Preferences read OK. AccountingInfoPrefs present: ${!!accountingInfo}. ` +
        `BookCloseDate present: ${bookCloseDate !== undefined} (value: ${JSON.stringify(bookCloseDate)} — ` +
        `undefined here most likely means no closing date has been SET in this sandbox yet, not that the field doesn't exist; ` +
        `docs/phase-0/SPIKE_QUEUE.md items 41-42 test the set/read cycle directly, not run in this session). ` +
        `TaxPrefs present: ${!!taxPrefs}, UsingSalesTax: ${JSON.stringify(usingSalesTax)} ` +
        `(relevant to docs/phase-0/02_QBO_CAPABILITY_MATRIX.md's AST-vs-legacy mode gate, row 9.1).`;

      return pass(detail);
    }
  );
}
