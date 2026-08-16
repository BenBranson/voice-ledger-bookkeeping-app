/**
 * docs/phase-0/SPIKE_QUEUE.md Wave 1, items 9-10.
 */

import { capabilityTest, pass, fail } from "../capabilityTest.js";
import { QboRawClient } from "../qboRawClient.js";

export async function run(): Promise<void> {
  await capabilityTest(
    "C5",
    "CDC endpoint works for a near-term window and returns a recognizable shape",
    async (capture) => {
      const client = new QboRawClient();
      const oneHourAgo = new Date(Date.now() - 60 * 60 * 1000).toISOString();
      const result = await client.get("cdc", { entities: "Purchase,Account,Vendor", changedSince: oneHourAgo });
      capture({ entities: "Purchase,Account,Vendor", changedSince: oneHourAgo }, result.body);

      if (result.status !== 200) return fail(`HTTP ${result.status}: ${JSON.stringify(result.body)}`);

      const responses = (result.body as any)?.CDCResponse ?? [];
      const entityKeys = new Set<string>();
      for (const block of responses) {
        for (const key of Object.keys(block.QueryResponse?.[0] ?? {})) {
          if (key !== "startPosition" && key !== "maxResults" && key !== "totalCount") entityKeys.add(key);
        }
      }

      const detail =
        `CDC call succeeded for entities=Purchase,Account,Vendor over the last hour. ` +
        `Entity types with changes reported in this window: ${entityKeys.size ? [...entityKeys].join(", ") : "none (no changes in the last hour, or shape differs from expected — see fixture)"}. ` +
        `⚠ NOT tested in this run: the 30-day lookback boundary (needs real elapsed calendar time — 29/30/31 days — which a single session cannot produce), ` +
        `tombstone shape for a deleted entity, or behavior past the window. Those remain ASSUMED, not disproven or verified — this only confirms the endpoint itself is reachable and responds with the documented top-level shape.`;

      return pass(detail);
    }
  );

  await capabilityTest(
    "§2.5",
    "Rate-limit behavior under a rapid sequential burst",
    async (capture) => {
      const client = new QboRawClient();
      const MAX_REQUESTS = 40; // bounded deliberately — this is a sandbox company, not a load test
      const statuses: number[] = [];
      const latencies: number[] = [];
      let hit429: { atRequest: number; headers: Record<string, string>; body: unknown } | null = null;

      for (let i = 1; i <= MAX_REQUESTS; i++) {
        const r = await client.get(`companyinfo/${client.realmId}`);
        statuses.push(r.status);
        latencies.push(r.latencyMs);
        if (r.status === 429 && !hit429) {
          hit429 = { atRequest: i, headers: r.headers as Record<string, string>, body: r.body };
          break; // stop as soon as we have the finding — no reason to keep hammering
        }
      }

      capture({ maxRequests: MAX_REQUESTS }, { statuses, latencies, hit429 });

      const detail = hit429
        ? `429 hit at request ${hit429.atRequest}/${MAX_REQUESTS}. Retry-After header: ${hit429.headers["retry-after"] ?? "absent"}. ` +
          `Other rate-related headers: ${Object.keys(hit429.headers).filter((h) => /rate|limit|quota/i.test(h)).join(", ") || "none"}.`
        : `No 429 within ${MAX_REQUESTS} sequential requests to companyinfo (avg latency ${Math.round(latencies.reduce((a, b) => a + b, 0) / latencies.length)}ms). ` +
          `This does NOT mean no limit exists — only that this endpoint, at this volume, in this sandbox, didn't trip it. ` +
          `Deliberately did not push further; a sandbox company is not the place to find the ceiling by brute force.`;

      // Either outcome is a valid, recorded answer — not a failure.
      return pass(detail);
    }
  );
}
