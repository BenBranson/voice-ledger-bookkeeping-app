/**
 * Dispatches a named catalog operation. This function — not a generic proxy
 * — is the entire surface through which the desktop client can make QBO
 * data move. An operation name absent from `CATALOG_OPERATIONS` is not
 * merely unauthorized, it is genuinely unreachable: `dispatch` has no
 * fallback path that forwards an unrecognized name anywhere.
 *
 * docs/phase-0/03_SECURITY_THREAT_MODEL.md §3.4 property A: "Unlisted
 * operations are unreachable."
 */

import { CATALOG_OPERATIONS } from "./operations.js";
import type { QBOClient } from "../qbo/client.js";
import { logEvent } from "../logging/logger.js";

export type DispatchResult =
  | { readonly kind: "success"; readonly data: unknown }
  | { readonly kind: "unreachable" }
  | { readonly kind: "invalidParams"; readonly issues: readonly string[] }
  | { readonly kind: "operationError"; readonly message: string; readonly httpStatus: number };

export async function dispatch(
  client: QBOClient,
  realmId: string,
  operationName: string,
  rawParams: unknown
): Promise<DispatchResult> {
  const definition = CATALOG_OPERATIONS.get(operationName);
  if (!definition) {
    logEvent("operation_unreachable", { realmId, operationName });
    return { kind: "unreachable" };
  }

  const parsed = definition.paramsSchema.safeParse(rawParams ?? {});
  if (!parsed.success) {
    return {
      kind: "invalidParams",
      issues: parsed.error.issues.map((issue) => `${issue.path.join(".")}: ${issue.message}`)
    };
  }

  logEvent("operation_invoked", { realmId, operationName });

  try {
    const data = await definition.execute(client, realmId, parsed.data);
    return { kind: "success", data };
  } catch (error) {
    const httpStatus = (error as { httpStatus?: number }).httpStatus ?? 502;
    const message = error instanceof Error ? error.message : "Unknown operation error";
    return { kind: "operationError", message, httpStatus };
  }
}
