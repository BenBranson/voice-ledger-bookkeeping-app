import { describe, it, expect } from "vitest";
import { assertReadOnlyCatalog, CATALOG_OPERATIONS } from "../src/catalog/operations.js";
import { dispatch } from "../src/catalog/dispatcher.js";
import type { QBOClient } from "../src/qbo/client.js";

/**
 * docs/phase-0/12_TEST_STRATEGY.md §12.2 item 3 (adapted from Swift to this
 * backend): the read-only catalog must actually be read-only, and an
 * operation name outside the catalog must be structurally unreachable, not
 * merely rejected by a permission check.
 */
describe("catalog", () => {
  it("Phase 1 step 1.2 scope: every operation is read-classified", () => {
    expect(() => assertReadOnlyCatalog()).not.toThrow();
    for (const definition of CATALOG_OPERATIONS.values()) {
      expect(definition.operationClass).toBe("read");
    }
  });

  it("contains exactly the seven operations named in the desktop-side CatalogOperation enum", () => {
    const names = [...CATALOG_OPERATIONS.keys()].sort();
    expect(names).toEqual(
      ["cdcSince", "readAccounts", "readCompanyInfo", "readPreferences", "readPurchases", "readVendors", "readReport"].sort()
    );
  });

  it("readVendors calls through to the QBO client with parsed params on success", async () => {
    let capturedPath: string | undefined;
    const fakeClient = {
      get: async (_realmId: string, path: string) => {
        capturedPath = path;
        return { QueryResponse: { Vendor: [] } };
      }
    } as unknown as QBOClient;

    const result = await dispatch(fakeClient, "123456", "readVendors", { activeOnly: true });
    expect(result.kind).toBe("success");
    expect(capturedPath).toBe("query");
  });

  it("dispatch returns 'unreachable' for an operation name not in the catalog — not merely unauthorized", async () => {
    const fakeClient = {} as QBOClient; // never called — dispatch must short-circuit before reaching it
    const result = await dispatch(fakeClient, "123456", "voidPurchase", {});
    expect(result.kind).toBe("unreachable");
  });

  it("dispatch rejects invalid parameters before calling the QBO client", async () => {
    let called = false;
    const fakeClient = { get: async () => ((called = true), {}) } as unknown as QBOClient;
    const result = await dispatch(fakeClient, "123456", "readPurchases", { startDate: "not-a-date" });
    expect(result.kind).toBe("invalidParams");
    expect(called).toBe(false);
  });

  it("dispatch calls through to the QBO client with parsed params on success", async () => {
    let capturedPath: string | undefined;
    const fakeClient = {
      get: async (_realmId: string, path: string) => {
        capturedPath = path;
        return { QueryResponse: { Account: [] } };
      }
    } as unknown as QBOClient;

    const result = await dispatch(fakeClient, "123456", "readAccounts", { activeOnly: true });
    expect(result.kind).toBe("success");
    expect(capturedPath).toBe("query");
  });

  it("readReport rejects a report kind outside the closed enum", async () => {
    const fakeClient = {} as QBOClient;
    const result = await dispatch(fakeClient, "123456", "readReport", { reportKind: "SomeUnlistedReport" });
    expect(result.kind).toBe("invalidParams");
  });
});
