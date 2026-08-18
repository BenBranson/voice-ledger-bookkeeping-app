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
import type { AnyOperationDefinition } from "./types.js";
import { logEvent } from "../logging/logger.js";

/**
 * Pure so the access-mode gate is unit-testable on its own — the real
 * catalog has zero write-classified operations right now
 * (`assertReadOnlyCatalog()`), so a test exercising this against
 * `CATALOG_OPERATIONS` directly couldn't reach the write branch at all.
 */
export function shouldBlockWrite(definition: AnyOperationDefinition, realmWriteEnabled: boolean): boolean {
  return definition.operationClass === "write" && !realmWriteEnabled;
}

export type DispatchResult =
  | { readonly kind: "success"; readonly data: unknown }
  | { readonly kind: "unreachable" }
  | { readonly kind: "writeDisabled" }
  | { readonly kind: "invalidParams"; readonly issues: readonly string[] }
  | { readonly kind: "operationError"; readonly message: string; readonly httpStatus: number };

/**
 * `realmWriteEnabled` — CLAUDE.md rule 4's access-mode gate, made
 * structural rather than a convention a route handler could forget: a
 * write-classified operation is refused HERE, in the one function every
 * operation call passes through, not just by callers remembering to check
 * first. No write-classified operation exists in the catalog yet
 * (`assertReadOnlyCatalog()` still holds) — this gate is built ahead of
 * that so the safety mechanism is proven before the first write op needs
 * it, not bolted on after.
 */
export async function dispatch(
  client: QBOClient,
  realmId: string,
  operationName: string,
  rawParams: unknown,
  realmWriteEnabled: boolean = false
): Promise<DispatchResult> {
  const definition = CATALOG_OPERATIONS.get(operationName);
  if (!definition) {
    logEvent("operation_unreachable", { realmId, operationName });
    return { kind: "unreachable" };
  }

  if (shouldBlockWrite(definition, realmWriteEnabled)) {
    logEvent("operation_write_disabled", { realmId, operationName });
    return { kind: "writeDisabled" };
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
