/**
 * The fixed catalog of named QBO operations. Mirrors
 * desktop/Sources/Integrations/QuickBooks/CatalogOperation.swift — not
 * shared code, but a deliberately identical closed set.
 *
 * docs/phase-0/03_SECURITY_THREAT_MODEL.md §3.4, decision D5: "The desktop
 * client cannot express a QBO request... The backend does not have a proxy
 * route." This module is the backend half of that guarantee: there is no
 * dispatcher path that accepts an arbitrary QBO path or method — only a
 * name from `CATALOG_OPERATIONS` below, each with its own typed parameter
 * schema and its own hand-written call into QBOClient.
 */

import type { z } from "zod";
import type { QBOClient } from "../qbo/client.js";

export type OperationName =
  | "readCompanyInfo"
  | "readPreferences"
  | "readAccounts"
  | "readPurchases"
  | "readBills"
  | "readVendors"
  | "readInvoices"
  | "readPayments"
  | "readDeposits"
  | "readVendorCredits"
  | "readReport"
  | "cdcSince";

/**
 * Whether an operation is classified read or write matters structurally:
 * the access-mode gate (docs/phase-0/10_STAGING_APPROVAL_AUDIT.md §10.4)
 * refuses ALL write-classified operations for a realm not in Write-Enabled
 * mode. Phase 1 step 1.2 defines only `"read"` operations — see the
 * assertion in operations.ts that no `"write"` entry exists yet.
 */
export type OperationClass = "read" | "write";

export interface OperationDefinition<Params> {
  readonly name: OperationName;
  readonly operationClass: OperationClass;
  readonly matrixRow: string; // docs/phase-0/02_QBO_CAPABILITY_MATRIX.md row id — traceability from code back to its verification status
  // The third type parameter (Input) is deliberately left as `any`: our
  // schemas use `.default(...)`, which makes a field's parsed INPUT type
  // optional while its OUTPUT type (what `execute` receives) is not. We
  // only care about the output shape here.
  readonly paramsSchema: z.ZodType<Params, z.ZodTypeDef, any>;
  readonly execute: (client: QBOClient, realmId: string, params: Params) => Promise<unknown>;
}

// An operation is erased to this shape once registered, so the catalog map
// can hold a heterogeneous set of operations with different Params types
// while the dispatcher stays generic.
export type AnyOperationDefinition = OperationDefinition<unknown>;
