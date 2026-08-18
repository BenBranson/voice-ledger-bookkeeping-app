/**
 * docs/phase-0/10_STAGING_APPROVAL_AUDIT.md §10.5a: "HTTP 200 is not
 * success." Wave 3's void-on-other-entities spike found two real anomalous
 * responses from QBO, both HTTP 200: a `Bill` void returned a `SystemFault`
 * embedded in the body, and a `JournalEntry` void returned an empty
 * `BatchItemResponse` — a silent no-op. Either would be read as success by
 * a status-code check alone.
 *
 * `QBOClient.post()` already throws on a non-2xx status (`QBOApiError`), so
 * by the time a write operation's `execute()` sees a response body here,
 * the status was already 2xx — this function's whole job is to keep that
 * from being trusted on its own. The one call site so far
 * (`updatePurchaseLineAccount`) does its own independent round-trip GET
 * regardless of what this returns for the "empty/unexpected shape" case —
 * that fresh read is this catalog's stand-in for the §10.6 resolution
 * probe, which doesn't exist as a separate mechanism yet. What this
 * function adds is surfacing a REAL QBO fault embedded in a 200 as a clear
 * error immediately, instead of silently discarding it and reporting an
 * unexplained `verified: false` later.
 */

export interface QBOFault {
  readonly message: string;
  readonly detail?: string;
  readonly code?: string;
}

export type WriteResponseOutcome =
  | { readonly kind: "success"; readonly entity: Record<string, unknown> }
  | { readonly kind: "unknown"; readonly reason: "faultInside2xx"; readonly fault: QBOFault }
  | { readonly kind: "unknown"; readonly reason: "emptyOrMissingExpectedEntity" };

/**
 * The ONLY function permitted to decide what a write response body actually
 * means. `entityKey` is the top-level key QBO wraps the entity in on
 * success (e.g. `"Purchase"`) — every QBO write response uses this
 * envelope shape.
 */
export function classifyWriteResponse(body: unknown, entityKey: string): WriteResponseOutcome {
  if (body === null || typeof body !== "object") {
    return { kind: "unknown", reason: "emptyOrMissingExpectedEntity" };
  }
  const record = body as Record<string, unknown>;

  const fault = record.Fault as { Error?: Array<{ Message?: string; Detail?: string; code?: string }> } | undefined;
  if (fault?.Error && fault.Error.length > 0) {
    const first = fault.Error[0]!;
    const faultValue: QBOFault = { message: first.Message ?? "Unknown QBO fault" };
    return {
      kind: "unknown",
      reason: "faultInside2xx",
      fault: {
        ...faultValue,
        ...(first.Detail !== undefined ? { detail: first.Detail } : {}),
        ...(first.code !== undefined ? { code: first.code } : {})
      }
    };
  }

  const entity = record[entityKey];
  if (entity === null || typeof entity !== "object") {
    return { kind: "unknown", reason: "emptyOrMissingExpectedEntity" };
  }

  return { kind: "success", entity: entity as Record<string, unknown> };
}
