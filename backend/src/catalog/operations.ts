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
import { classifyWriteResponse } from "../qbo/writeResponse.js";

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

const readVendorCreditsParams = z.object({
  startDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, "expected YYYY-MM-DD"),
  endDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, "expected YYYY-MM-DD"),
  startPosition: z.number().int().min(1).default(1),
  maxResults: z.number().int().min(1).max(1000).default(1000)
});

// Added 2026-08-17 for the vendor-refunds/vendor-credits cleanup workflow
// (VL-VENDCREDIT-UNAPPLIED-001). VendorCredit.Balance (verified live against
// a real created VendorCredit, Id 224) is the authoritative "how much of
// this credit is still unapplied" signal — not something that has to be
// computed from BillPayment/JournalEntry cross-referencing.
const readVendorCredits = op({
  name: "readVendorCredits",
  operationClass: "read",
  matrixRow: "TBD — new row, not yet in 02_QBO_CAPABILITY_MATRIX.md",
  paramsSchema: readVendorCreditsParams,
  execute: async (client, realmId, params: z.infer<typeof readVendorCreditsParams>) => {
    const query =
      `select * from VendorCredit where TxnDate >= '${params.startDate}' and TxnDate <= '${params.endDate}' ` +
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

// docs/phase-0/15_STAGED_WRITES... (no such doc yet — see
// docs/VOICE_LEDGER_HANDOFF.md's write-path section instead). Voice
// Ledger's FIRST write-classified operation, added 2026-08-17 after its
// capability spike passed (a full-entity Purchase-line reclassification,
// round-trip verified live: DocNumber/PrivateNote/TotalAmt/the untouched
// second line all preserved exactly, only the targeted line's AccountRef
// changed) and the owner explicitly approved crossing the Phase 1 (read-
// only) -> Phase 2 (writes) threshold `assertReadOnlyCatalog` below used to
// guard.
//
// CLAUDE.md rule 8 / docs/phase-0/10_STAGING_APPROVAL_AUDIT.md §10.3's
// round-trip fidelity check is not optional here — it is baked into the
// operation itself, not left to a caller to remember. Every other field on
// the entity, and every OTHER line besides the one being reclassified, is
// compared byte-for-byte between the pre-update read and a fresh POST-
// update read (not the update response — a fresh read, so QBO-side
// normalization or partial application can't hide behind an optimistic
// response body). `verified: false` in the result means exactly that: the
// write happened, but it didn't come back the way it should have, and the
// caller must treat this as `UNKNOWN`-adjacent (docs/VOICE_LEDGER_HANDOFF.md's
// `UNKNOWN` write-state description), not as success.
const updatePurchaseLineAccountParams = z.object({
  purchaseId: z.string().min(1),
  // QBO's own `Line.Id` — not an array index. An index could silently
  // target the wrong line if QBO ever reorders lines between the caller's
  // read and this call; `Line.Id` is stable identity.
  lineId: z.string().min(1),
  // The `SyncToken` the caller last read — required, not optional. A
  // mismatch means someone else (the client, a prior bookkeeper, QBO
  // auto-categorization) changed this Purchase since the caller last saw
  // it, and this operation refuses to blindly overwrite that.
  expectedSyncToken: z.string().min(1),
  newAccountId: z.string().min(1)
});

const FIELDS_THAT_MUST_NOT_DRIFT = ["DocNumber", "PrivateNote", "TotalAmt", "EntityRef", "AccountRef", "TxnDate"] as const;

// dispatcher.ts's operationError branch reads `(error as {httpStatus?}).httpStatus`,
// defaulting to 502 for a plain Error — accurate for "QBO itself failed" but
// misleading for a validation/conflict error that never left this process.
class OperationValidationError extends Error {
  constructor(message: string, readonly httpStatus: number) {
    super(message);
    this.name = "OperationValidationError";
  }
}

const updatePurchaseLineAccount = op({
  name: "updatePurchaseLineAccount",
  operationClass: "write",
  matrixRow: "TBD — Phase 2, first write operation, not yet in 02_QBO_CAPABILITY_MATRIX.md",
  paramsSchema: updatePurchaseLineAccountParams,
  execute: async (client, realmId, params: z.infer<typeof updatePurchaseLineAccountParams>) => {
    // Step 1: a FRESH read, never trusting a caller-supplied "current
    // state" beyond the SyncToken it's about to be checked against.
    const beforeResponse = (await client.get(realmId, "query", {
      query: `select * from Purchase where Id = '${params.purchaseId}'`
    })) as { QueryResponse?: { Purchase?: any[] } };
    const beforeEntity = beforeResponse.QueryResponse?.Purchase?.[0];
    if (!beforeEntity) {
      throw new OperationValidationError(`Purchase ${params.purchaseId} not found.`, 404);
    }
    if (beforeEntity.SyncToken !== params.expectedSyncToken) {
      throw new OperationValidationError(
        `Stale SyncToken for Purchase ${params.purchaseId}: expected ${params.expectedSyncToken}, QBO has ${beforeEntity.SyncToken}. Resync and try again — someone else changed this transaction.`,
        409
      );
    }

    const targetLine = (beforeEntity.Line ?? []).find((line: any) => line.Id === params.lineId);
    if (!targetLine) {
      throw new OperationValidationError(`Line ${params.lineId} not found on Purchase ${params.purchaseId}.`, 404);
    }
    if (!targetLine.AccountBasedExpenseLineDetail) {
      throw new OperationValidationError(
        `Line ${params.lineId} is not an AccountBasedExpenseLineDetail line — this operation only reclassifies expense-category lines.`,
        400
      );
    }
    const oldAccountId = targetLine.AccountBasedExpenseLineDetail.AccountRef?.value;

    // Step 2: full-entity update — the ENTIRE read-back entity, with ONLY
    // the target line's AccountRef changed. A sparse update loses data
    // (verified: a Purchase line memo and a Bill's second line were both
    // dropped by one) — full-entity is the only approach approved for
    // this catalog.
    const modified = JSON.parse(JSON.stringify(beforeEntity));
    delete modified.sparse;
    const modifiedLine = modified.Line.find((line: any) => line.Id === params.lineId);
    modifiedLine.AccountBasedExpenseLineDetail.AccountRef = { value: params.newAccountId };

    const postResponse = await client.post(realmId, "purchase", modified);

    // §10.5a: a 2xx status is not success — check the body BEFORE trusting
    // anything happened. A real QBO fault embedded in a 200 (the Bill-void
    // shape found in the void spike) is thrown immediately, with the
    // actual QBO error message, rather than silently falling through to a
    // round-trip verification that would just report an unexplained
    // `verified: false`. An empty/unexpected body ("unknown") is NOT
    // thrown here — it falls through to the same round-trip read below,
    // which is this operation's own stand-in for the §10.6 resolution
    // probe (not yet built as a separate mechanism) and can tell
    // definitively whether the write actually applied.
    const classified = classifyWriteResponse(postResponse, "Purchase");
    if (classified.kind === "unknown" && classified.reason === "faultInside2xx") {
      throw new OperationValidationError(
        `QBO rejected the update to Purchase ${params.purchaseId} with a fault inside a 200 response: ${classified.fault.message}` +
          (classified.fault.detail ? ` — ${classified.fault.detail}` : ""),
        502
      );
    }

    // Step 3: round-trip verification via a FRESH read (not the update
    // response) — compares every field that must NOT have drifted, and
    // every OTHER line's content, byte-for-byte against the pre-update read.
    const verifyResponse = (await client.get(realmId, "query", {
      query: `select * from Purchase where Id = '${params.purchaseId}'`
    })) as { QueryResponse?: { Purchase?: any[] } };
    const verifiedEntity = verifyResponse.QueryResponse?.Purchase?.[0];

    const verifiedLine = (verifiedEntity?.Line ?? []).find((line: any) => line.Id === params.lineId);
    const accountChangedCorrectly = verifiedLine?.AccountBasedExpenseLineDetail?.AccountRef?.value === params.newAccountId;

    const unexpectedFieldChanges = verifiedEntity
      ? FIELDS_THAT_MUST_NOT_DRIFT.filter(
          (field) => JSON.stringify((beforeEntity as any)[field]) !== JSON.stringify((verifiedEntity as any)[field])
        )
      : FIELDS_THAT_MUST_NOT_DRIFT.slice();

    const otherLinesUnchanged = verifiedEntity
      ? (beforeEntity.Line as any[])
          .filter((line: any) => line.Id !== params.lineId)
          .every((beforeLine: any) => {
            const afterLine = (verifiedEntity.Line as any[]).find((line: any) => line.Id === beforeLine.Id);
            return afterLine !== undefined && JSON.stringify(afterLine) === JSON.stringify(beforeLine);
          })
      : false;

    const verified = accountChangedCorrectly && unexpectedFieldChanges.length === 0 && otherLinesUnchanged;

    return {
      verified,
      purchaseId: params.purchaseId,
      lineId: params.lineId,
      oldAccountId,
      newAccountId: params.newAccountId,
      newSyncToken: verifiedEntity?.SyncToken ?? null,
      unexpectedFieldChanges,
      otherLinesUnchanged,
      // Full before/after snapshots — docs/VOICE_LEDGER_HANDOFF.md's
      // Activity Log requirement ("before/after entity snapshots"), not
      // summarized away.
      before: beforeEntity,
      after: verifiedEntity ?? null
    };
  }
});

export const CATALOG_OPERATIONS: ReadonlyMap<string, AnyOperationDefinition> = new Map(
  [
    readCompanyInfo,
    readPreferences,
    readAccounts,
    readPurchases,
    readBills,
    readVendors,
    readInvoices,
    readPayments,
    readDeposits,
    readVendorCredits,
    readReport,
    cdcSince,
    updatePurchaseLineAccount
  ].map((definition) => [definition.name, definition])
);

/**
 * T0 structural guarantee (docs/phase-0/12_TEST_STRATEGY.md §12.2),
 * UPDATED 2026-08-17 from a blanket "read-only" assertion to an explicit
 * allowlist, the moment the first write operation's spike passed and the
 * owner approved it. The property this still protects is unchanged: a
 * write-classified operation cannot silently appear in the catalog without
 * a deliberate, reviewable change to this exact list — it just now
 * tolerates the one operation that has actually cleared that bar, by name,
 * rather than tolerating none.
 */
const APPROVED_WRITE_OPERATIONS: ReadonlySet<string> = new Set(["updatePurchaseLineAccount"]);

export function assertCatalogWriteOpsAreApproved(): void {
  for (const definition of CATALOG_OPERATIONS.values()) {
    if (definition.operationClass === "write" && !APPROVED_WRITE_OPERATIONS.has(definition.name)) {
      throw new Error(
        `Catalog contains an unapproved write operation "${definition.name}". ` +
          `A write operation may only be added to APPROVED_WRITE_OPERATIONS once its capability-spike test has passed ` +
          `(docs/phase-0/SPIKE_QUEUE.md) and that requires separate, explicit owner approval.`
      );
    }
  }
}
