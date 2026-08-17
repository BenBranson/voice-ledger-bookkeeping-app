/**
 * The catalog contents. Phase 1 step 1.2 scope: READ-ONLY.
 *
 * Per the owner's Phase 1 approval: "No write operation enters the catalog
 * until its spike test has passed" — see docs/phase-0/SPIKE_QUEUE.md. Every
 * entry below is `operationClass: "read"`; `assertReadOnlyCatalog()` at the
 * bottom of this file is a runtime check (also exercised in
 * test/catalog.test.ts) that fails loudly if that ever silently changes.
 */

import { z } from "zod";
import type { AnyOperationDefinition, OperationDefinition } from "./types.js";

function op<Params>(definition: OperationDefinition<Params>): AnyOperationDefinition {
  return definition as AnyOperationDefinition;
}

const readCompanyInfo = op({
  name: "readCompanyInfo",
  operationClass: "read",
  matrixRow: "1.1 / C1",
  paramsSchema: z.object({}).strict(),
  execute: async (client, realmId) => client.get(realmId, `companyinfo/${realmId}`)
});

const readPreferences = op({
  name: "readPreferences",
  operationClass: "read",
  matrixRow: "C3 / 2.1",
  paramsSchema: z.object({}).strict(),
  execute: async (client, realmId) =>
    client.get(realmId, "query", { query: "select * from Preferences" })
});

const readAccountsParams = z.object({
  activeOnly: z.boolean().default(true),
  startPosition: z.number().int().min(1).default(1),
  maxResults: z.number().int().min(1).max(1000).default(1000)
});

const readAccounts = op({
  name: "readAccounts",
  operationClass: "read",
  matrixRow: "1.2 / 6.1",
  paramsSchema: readAccountsParams,
  execute: async (client, realmId, params: z.infer<typeof readAccountsParams>) => {
    const whereClause = params.activeOnly ? " where Active = true" : "";
    const query = `select * from Account${whereClause} STARTPOSITION ${params.startPosition} MAXRESULTS ${params.maxResults}`;
    return client.get(realmId, "query", { query });
  }
});

const readPurchasesParams = z.object({
  startDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, "expected YYYY-MM-DD"),
  endDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, "expected YYYY-MM-DD"),
  startPosition: z.number().int().min(1).default(1),
  maxResults: z.number().int().min(1).max(1000).default(1000)
});

const readPurchases = op({
  name: "readPurchases",
  operationClass: "read",
  matrixRow: "3.1 / 4.1",
  paramsSchema: readPurchasesParams,
  execute: async (client, realmId, params: z.infer<typeof readPurchasesParams>) => {
    const query =
      `select * from Purchase where TxnDate >= '${params.startDate}' and TxnDate <= '${params.endDate}' ` +
      `STARTPOSITION ${params.startPosition} MAXRESULTS ${params.maxResults}`;
    return client.get(realmId, "query", { query });
  }
});

const readBillsParams = z.object({
  startDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, "expected YYYY-MM-DD"),
  endDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, "expected YYYY-MM-DD"),
  startPosition: z.number().int().min(1).default(1),
  maxResults: z.number().int().min(1).max(1000).default(1000)
});

// docs/backlog's VL-DUP-BILL-001. Added 2026-08-17, same pattern as
// readPurchases — Bill is date-bounded the same way.
const readBills = op({
  name: "readBills",
  operationClass: "read",
  matrixRow: "TBD — new row, not yet in 02_QBO_CAPABILITY_MATRIX.md",
  paramsSchema: readBillsParams,
  execute: async (client, realmId, params: z.infer<typeof readBillsParams>) => {
    const query =
      `select * from Bill where TxnDate >= '${params.startDate}' and TxnDate <= '${params.endDate}' ` +
      `STARTPOSITION ${params.startPosition} MAXRESULTS ${params.maxResults}`;
    return client.get(realmId, "query", { query });
  }
});

const readInvoicesParams = z.object({
  startDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, "expected YYYY-MM-DD"),
  endDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, "expected YYYY-MM-DD"),
  startPosition: z.number().int().min(1).default(1),
  maxResults: z.number().int().min(1).max(1000).default(1000)
});

// docs/backlog's VL-DUP-INV-001. Added 2026-08-17, same date-bounded
// pattern as readPurchases/readBills — Invoice is the sales-side
// equivalent of Bill (CustomerRef instead of VendorRef).
const readInvoices = op({
  name: "readInvoices",
  operationClass: "read",
  matrixRow: "TBD — new row, not yet in 02_QBO_CAPABILITY_MATRIX.md",
  paramsSchema: readInvoicesParams,
  execute: async (client, realmId, params: z.infer<typeof readInvoicesParams>) => {
    const query =
      `select * from Invoice where TxnDate >= '${params.startDate}' and TxnDate <= '${params.endDate}' ` +
      `STARTPOSITION ${params.startPosition} MAXRESULTS ${params.maxResults}`;
    return client.get(realmId, "query", { query });
  }
});

const readPaymentsParams = z.object({
  startDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, "expected YYYY-MM-DD"),
  endDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, "expected YYYY-MM-DD"),
  startPosition: z.number().int().min(1).default(1),
  maxResults: z.number().int().min(1).max(1000).default(1000)
});

// docs/backlog's VL-DUP-PAY-001. Added 2026-08-17, same date-bounded
// pattern as readInvoices — Payment is the customer-payment counterpart to
// Invoice (CustomerRef, TotalAmt, TxnDate — verified live against a real
// sample-company Payment before this operation was written).
const readPayments = op({
  name: "readPayments",
  operationClass: "read",
  matrixRow: "TBD — new row, not yet in 02_QBO_CAPABILITY_MATRIX.md",
  paramsSchema: readPaymentsParams,
  execute: async (client, realmId, params: z.infer<typeof readPaymentsParams>) => {
    const query =
      `select * from Payment where TxnDate >= '${params.startDate}' and TxnDate <= '${params.endDate}' ` +
      `STARTPOSITION ${params.startPosition} MAXRESULTS ${params.maxResults}`;
    return client.get(realmId, "query", { query });
  }
});

const readDepositsParams = z.object({
  startDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, "expected YYYY-MM-DD"),
  endDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, "expected YYYY-MM-DD"),
  startPosition: z.number().int().min(1).default(1),
  maxResults: z.number().int().min(1).max(1000).default(1000)
});

// docs/backlog's VL-BS-UNDEP-001. Added 2026-08-17 — Deposit.Line[].LinkedTxn
// is the authoritative signal for which Payments have already been swept out
// of Undeposited Funds, confirmed live (a Payment dated Jan 21 was found
// swept by a Deposit dated Jan 25 — a Payment-only check would have
// false-positived on it as "stuck").
const readDeposits = op({
  name: "readDeposits",
  operationClass: "read",
  matrixRow: "TBD — new row, not yet in 02_QBO_CAPABILITY_MATRIX.md",
  paramsSchema: readDepositsParams,
  execute: async (client, realmId, params: z.infer<typeof readDepositsParams>) => {
    const query =
      `select * from Deposit where TxnDate >= '${params.startDate}' and TxnDate <= '${params.endDate}' ` +
      `STARTPOSITION ${params.startPosition} MAXRESULTS ${params.maxResults}`;
    return client.get(realmId, "query", { query });
  }
});

const readVendorsParams = z.object({
  activeOnly: z.boolean().default(true),
  startPosition: z.number().int().min(1).default(1),
  maxResults: z.number().int().min(1).max(1000).default(1000)
});

// docs/backlog/CLEANUP_MODE.md / the original 27-rule backlog's
// VL-DUP-VEND-001. Added 2026-08-17 alongside that rule — read-only, same
// pattern as readAccounts.
const readVendors = op({
  name: "readVendors",
  operationClass: "read",
  matrixRow: "TBD — new row, not yet in 02_QBO_CAPABILITY_MATRIX.md",
  paramsSchema: readVendorsParams,
  execute: async (client, realmId, params: z.infer<typeof readVendorsParams>) => {
    const whereClause = params.activeOnly ? " where Active = true" : "";
    const query = `select * from Vendor${whereClause} STARTPOSITION ${params.startPosition} MAXRESULTS ${params.maxResults}`;
    return client.get(realmId, "query", { query });
  }
});

// Closed set — deliberately NOT an arbitrary report-name passthrough.
// docs/phase-0/04_DATA_MODEL.md §4.9: report column composition varies by
// minor version and locale; an unlisted report name has no normalizer and
// must not be reachable.
const reportKindSchema = z.enum([
  "BalanceSheet",
  "ProfitAndLoss",
  "TrialBalance",
  "GeneralLedger",
  "TransactionList",
  "CashFlow",
  "AgedReceivables",
  "AgedPayables"
]);

const readReportParams = z.object({
  reportKind: reportKindSchema,
  startDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
  endDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional()
});

const readReport = op({
  name: "readReport",
  operationClass: "read",
  matrixRow: "1.3 / 8.1-8.3 / 12.1-12.4",
  paramsSchema: readReportParams,
  execute: async (client, realmId, params: z.infer<typeof readReportParams>) => {
    const searchParams: Record<string, string> = {};
    if (params.startDate) searchParams.start_date = params.startDate;
    if (params.endDate) searchParams.end_date = params.endDate;
    return client.get(realmId, `reports/${params.reportKind}`, searchParams);
  }
});

// Closed entity set for the same reason reportKind is closed above.
const cdcEntityKindSchema = z.enum(["Account", "Vendor", "Purchase", "Bill", "Customer", "Item"]);

const cdcSinceParams = z.object({
  entityKinds: z.array(cdcEntityKindSchema).min(1),
  since: z.string().datetime()
});

const cdcSince = op({
  name: "cdcSince",
  operationClass: "read",
  matrixRow: "C5",
  paramsSchema: cdcSinceParams,
  execute: async (client, realmId, params: z.infer<typeof cdcSinceParams>) =>
    client.get(realmId, "cdc", {
      entities: params.entityKinds.join(","),
      changedSince: params.since
    })
});

export const CATALOG_OPERATIONS: ReadonlyMap<string, AnyOperationDefinition> = new Map(
  [readCompanyInfo, readPreferences, readAccounts, readPurchases, readBills, readVendors, readInvoices, readPayments, readDeposits, readReport, cdcSince].map(
    (definition) => [definition.name, definition]
  )
);

/**
 * T0 structural guarantee (docs/phase-0/12_TEST_STRATEGY.md §12.2):
 * Phase 1 step 1.2 ships read-only. This throws if that's ever violated,
 * and test/catalog.test.ts asserts it runs clean.
 */
export function assertReadOnlyCatalog(): void {
  for (const definition of CATALOG_OPERATIONS.values()) {
    if (definition.operationClass !== "read") {
      throw new Error(
        `Catalog contains a non-read operation "${definition.name}" — Phase 1 step 1.2 scope is read-only. ` +
          `A write operation may only be added once its capability-spike test has passed (docs/phase-0/SPIKE_QUEUE.md) ` +
          `and that requires separate, explicit approval per the Phase 1 gate table.`
      );
    }
  }
}
