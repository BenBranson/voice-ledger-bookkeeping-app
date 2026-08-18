import { describe, it, expect } from "vitest";
import { classifyWriteResponse } from "../src/qbo/writeResponse.js";

/**
 * docs/phase-0/10_STAGING_APPROVAL_AUDIT.md §10.5a: "HTTP 200 is not
 * success." These test the two real anomalous-200 shapes the void spike
 * found (Wave 3, spike/fixtures/results-2026-08-16T20-45-42-102Z.json) —
 * a fault embedded in a 200 body, and an empty/missing expected entity.
 */
describe("classifyWriteResponse", () => {
  it("classifies a well-formed entity response as success", () => {
    const result = classifyWriteResponse({ Purchase: { Id: "1", SyncToken: "1" } }, "Purchase");
    expect(result.kind).toBe("success");
    if (result.kind === "success") {
      expect(result.entity.Id).toBe("1");
    }
  });

  it("classifies a Fault embedded in a 200 body as unknown/faultInside2xx — the Bill-void shape", () => {
    const result = classifyWriteResponse(
      { Fault: { Error: [{ Message: "Business Validation Error", Detail: "Something was not right.", code: "6000" }] } },
      "Purchase"
    );
    expect(result.kind).toBe("unknown");
    if (result.kind === "unknown" && result.reason === "faultInside2xx") {
      expect(result.fault.message).toBe("Business Validation Error");
      expect(result.fault.detail).toBe("Something was not right.");
      expect(result.fault.code).toBe("6000");
    } else {
      throw new Error("expected faultInside2xx");
    }
  });

  it("classifies an empty body as unknown/emptyOrMissingExpectedEntity — the JournalEntry-void shape", () => {
    const result = classifyWriteResponse({}, "Purchase");
    expect(result).toEqual({ kind: "unknown", reason: "emptyOrMissingExpectedEntity" });
  });

  it("classifies a null body as unknown/emptyOrMissingExpectedEntity", () => {
    expect(classifyWriteResponse(null, "Purchase")).toEqual({ kind: "unknown", reason: "emptyOrMissingExpectedEntity" });
  });

  it("classifies a Fault with no Error array as unknown/emptyOrMissingExpectedEntity, not a crash", () => {
    expect(classifyWriteResponse({ Fault: {} }, "Purchase")).toEqual({
      kind: "unknown",
      reason: "emptyOrMissingExpectedEntity"
    });
  });
});
