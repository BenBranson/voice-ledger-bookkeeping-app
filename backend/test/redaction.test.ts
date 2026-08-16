import { describe, it, expect } from "vitest";
import { redact } from "../src/logging/redaction.js";

/**
 * docs/phase-0/12_TEST_STRATEGY.md §12.8's "log-hygiene suite" starts here:
 * the redaction filter itself must actually catch token- and currency-
 * shaped values, or the whole §3.5 control is decorative.
 */
describe("redact", () => {
  it("flags a bearer token", () => {
    const result = redact(JSON.stringify({ event: "test", header: "Bearer abcdefghijklmnopqrstuvwxyz123456" }));
    expect(result.matched).toBe(true);
    expect(result.patterns).toContain("bearer_token");
  });

  it("flags a serialized access_token field", () => {
    const result = redact(JSON.stringify({ access_token: "AB0123456789xyzsecretvalue" }));
    expect(result.matched).toBe(true);
  });

  it("flags a currency-shaped amount — CLAUDE.md rule / §3.5 forbidden list", () => {
    const result = redact(JSON.stringify({ event: "operation_succeeded", note: "total was $486.20" }));
    expect(result.matched).toBe(true);
    expect(result.patterns).toContain("currency_amount");
  });

  it("flags an Anthropic-style API key", () => {
    const result = redact("sk-ant-abcdefghijklmnopqrstuvwxyz0123456789");
    expect(result.matched).toBe(true);
  });

  it("does not flag an ordinary structured log line", () => {
    const result = redact(
      JSON.stringify({
        event: "operation_succeeded",
        realmId: "123456789",
        operationName: "readCompanyInfo",
        httpStatus: 200,
        latencyMs: 214,
        timestamp: new Date().toISOString()
      })
    );
    expect(result.matched).toBe(false);
  });
});
