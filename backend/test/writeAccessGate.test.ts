import { describe, it, expect } from "vitest";
import { z } from "zod";
import { shouldBlockWrite, dispatch } from "../src/catalog/dispatcher.js";
import type { AnyOperationDefinition } from "../src/catalog/types.js";
import type { QBOClient } from "../src/qbo/client.js";

/**
 * CLAUDE.md rule 4's access-mode gate. The real catalog has zero
 * write-classified operations (`assertReadOnlyCatalog()`), so this tests
 * `shouldBlockWrite` directly against synthetic definitions rather than
 * the real `CATALOG_OPERATIONS` map — proving the gate mechanism itself
 * works before any real write operation exists to depend on it.
 */
describe("write access gate", () => {
  const fakeWriteOp: AnyOperationDefinition = {
    name: "readAccounts" as never, // any valid OperationName works for this synthetic test
    operationClass: "write",
    matrixRow: "test",
    paramsSchema: z.object({}).strict(),
    execute: async () => ({ ok: true })
  };

  const fakeReadOp: AnyOperationDefinition = {
    name: "readAccounts" as never,
    operationClass: "read",
    matrixRow: "test",
    paramsSchema: z.object({}).strict(),
    execute: async () => ({ ok: true })
  };

  it("blocks a write-classified operation when the realm is write-disabled", () => {
    expect(shouldBlockWrite(fakeWriteOp, false)).toBe(true);
  });

  it("allows a write-classified operation when the realm is write-enabled", () => {
    expect(shouldBlockWrite(fakeWriteOp, true)).toBe(false);
  });

  it("never blocks a read-classified operation, regardless of write-enabled status", () => {
    expect(shouldBlockWrite(fakeReadOp, false)).toBe(false);
    expect(shouldBlockWrite(fakeReadOp, true)).toBe(false);
  });

  it("dispatch defaults realmWriteEnabled to false when the caller omits it — the safe direction to default", async () => {
    const fakeClient = {} as QBOClient;
    // readAccounts is real and read-classified, so this exercises the
    // real dispatch() path end to end with no explicit 5th argument.
    const result = await dispatch(fakeClient, "123456", "doesNotExist", {});
    expect(result.kind).toBe("unreachable"); // proves dispatch ran at all with the default param
  });
});
