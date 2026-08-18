import { describe, it, expect } from "vitest";
import { assertCatalogWriteOpsAreApproved, CATALOG_OPERATIONS } from "../src/catalog/operations.js";
import { dispatch } from "../src/catalog/dispatcher.js";
import type { QBOClient } from "../src/qbo/client.js";

/**
 * docs/phase-0/12_TEST_STRATEGY.md §12.2 item 3 (adapted from Swift to this
 * backend): an operation name outside the catalog must be structurally
 * unreachable, not merely rejected by a permission check. Updated
 * 2026-08-17: the catalog is no longer blanket read-only — exactly one
 * write-classified operation exists, spike-verified and owner-approved
 * (`updatePurchaseLineAccount`) — so this now asserts the explicit
 * allowlist holds, not that every operation is read-classified.
 */
describe("catalog", () => {
  it("every write-classified operation is on the explicit approved list", () => {
    expect(() => assertCatalogWriteOpsAreApproved()).not.toThrow();
  });

  it("exactly one operation is write-classified — updatePurchaseLineAccount, and no other", () => {
    const writeOps = [...CATALOG_OPERATIONS.values()].filter((def) => def.operationClass === "write");
    expect(writeOps.map((def) => def.name)).toEqual(["updatePurchaseLineAccount"]);
  });

  it("contains exactly the thirteen operations named in the desktop-side CatalogOperation enum", () => {
    const names = [...CATALOG_OPERATIONS.keys()].sort();
    expect(names).toEqual(
      [
        "cdcSince",
        "readAccounts",
        "readBills",
        "readCompanyInfo",
        "readDeposits",
        "readInvoices",
        "readPayments",
        "readPreferences",
        "readPurchases",
        "readVendors",
        "readVendorCredits",
        "readReport",
        "updatePurchaseLineAccount"
      ].sort()
    );
  });

  it("readBills calls through to the QBO client with parsed params on success", async () => {
    let capturedPath: string | undefined;
    const fakeClient = {
      get: async (_realmId: string, path: string) => {
        capturedPath = path;
        return { QueryResponse: { Bill: [] } };
      }
    } as unknown as QBOClient;

    const result = await dispatch(fakeClient, "123456", "readBills", { startDate: "2026-07-01", endDate: "2026-07-31" });
    expect(result.kind).toBe("success");
    expect(capturedPath).toBe("query");
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

  it("readInvoices calls through to the QBO client with parsed params on success", async () => {
    let capturedPath: string | undefined;
    const fakeClient = {
      get: async (_realmId: string, path: string) => {
        capturedPath = path;
        return { QueryResponse: { Invoice: [] } };
      }
    } as unknown as QBOClient;

    const result = await dispatch(fakeClient, "123456", "readInvoices", { startDate: "2026-07-01", endDate: "2026-07-31" });
    expect(result.kind).toBe("success");
    expect(capturedPath).toBe("query");
  });

  it("readPayments calls through to the QBO client with parsed params on success", async () => {
    let capturedPath: string | undefined;
    const fakeClient = {
      get: async (_realmId: string, path: string) => {
        capturedPath = path;
        return { QueryResponse: { Payment: [] } };
      }
    } as unknown as QBOClient;

    const result = await dispatch(fakeClient, "123456", "readPayments", { startDate: "2026-07-01", endDate: "2026-07-31" });
    expect(result.kind).toBe("success");
    expect(capturedPath).toBe("query");
  });

  it("readDeposits calls through to the QBO client with parsed params on success", async () => {
    let capturedPath: string | undefined;
    const fakeClient = {
      get: async (_realmId: string, path: string) => {
        capturedPath = path;
        return { QueryResponse: { Deposit: [] } };
      }
    } as unknown as QBOClient;

    const result = await dispatch(fakeClient, "123456", "readDeposits", { startDate: "2026-07-01", endDate: "2026-07-31" });
    expect(result.kind).toBe("success");
    expect(capturedPath).toBe("query");
  });

  it("readVendorCredits calls through to the QBO client with parsed params on success", async () => {
    let capturedPath: string | undefined;
    const fakeClient = {
      get: async (_realmId: string, path: string) => {
        capturedPath = path;
        return { QueryResponse: { VendorCredit: [] } };
      }
    } as unknown as QBOClient;

    const result = await dispatch(fakeClient, "123456", "readVendorCredits", { startDate: "2026-07-01", endDate: "2026-07-31" });
    expect(result.kind).toBe("success");
    expect(capturedPath).toBe("query");
  });

  it("updatePurchaseLineAccount is refused for a write-disabled realm — the access-mode gate applies to the real write op, not just a synthetic one", async () => {
    const fakeClient = {} as QBOClient; // never called — the gate must short-circuit before reaching it
    const result = await dispatch(
      fakeClient,
      "123456",
      "updatePurchaseLineAccount",
      { purchaseId: "1", lineId: "1", expectedSyncToken: "0", newAccountId: "2" },
      false // realmWriteEnabled
    );
    expect(result.kind).toBe("writeDisabled");
  });

  it("updatePurchaseLineAccount verifies the round trip and reports verified:true on a clean update", async () => {
    const beforeEntity = {
      Id: "1",
      SyncToken: "0",
      DocNumber: "1001",
      PrivateNote: "test",
      TotalAmt: 50,
      EntityRef: { value: "10" },
      AccountRef: { value: "35" },
      TxnDate: "2026-07-14",
      Line: [
        { Id: "1", AccountBasedExpenseLineDetail: { AccountRef: { value: "old-account" } } },
        { Id: "2", AccountBasedExpenseLineDetail: { AccountRef: { value: "untouched-account" } } }
      ]
    };
    const afterEntity = {
      ...beforeEntity,
      SyncToken: "1",
      Line: [
        { Id: "1", AccountBasedExpenseLineDetail: { AccountRef: { value: "new-account" } } },
        { Id: "2", AccountBasedExpenseLineDetail: { AccountRef: { value: "untouched-account" } } }
      ]
    };
    let readCount = 0;
    const fakeClient = {
      get: async () => {
        readCount += 1;
        return { QueryResponse: { Purchase: [readCount === 1 ? beforeEntity : afterEntity] } };
      },
      post: async () => ({ Purchase: afterEntity })
    } as unknown as QBOClient;

    const result = await dispatch(
      fakeClient,
      "123456",
      "updatePurchaseLineAccount",
      { purchaseId: "1", lineId: "1", expectedSyncToken: "0", newAccountId: "new-account" },
      true
    );
    expect(result.kind).toBe("success");
    if (result.kind === "success") {
      const data = result.data as { verified: boolean; oldAccountId: string; unexpectedFieldChanges: string[] };
      expect(data.verified).toBe(true);
      expect(data.oldAccountId).toBe("old-account");
      expect(data.unexpectedFieldChanges).toEqual([]);
    }
  });

  it("updatePurchaseLineAccount reports verified:false when an untouched line drifted — round-trip fidelity actually checked, not assumed", async () => {
    const beforeEntity = {
      Id: "1",
      SyncToken: "0",
      DocNumber: "1001",
      TotalAmt: 50,
      Line: [
        { Id: "1", AccountBasedExpenseLineDetail: { AccountRef: { value: "old-account" } } },
        { Id: "2", AccountBasedExpenseLineDetail: { AccountRef: { value: "untouched-account" } } }
      ]
    };
    // Simulates data loss: line 2's account silently changed too.
    const driftedEntity = {
      ...beforeEntity,
      SyncToken: "1",
      Line: [
        { Id: "1", AccountBasedExpenseLineDetail: { AccountRef: { value: "new-account" } } },
        { Id: "2", AccountBasedExpenseLineDetail: { AccountRef: { value: "DRIFTED" } } }
      ]
    };
    let readCount = 0;
    const fakeClient = {
      get: async () => {
        readCount += 1;
        return { QueryResponse: { Purchase: [readCount === 1 ? beforeEntity : driftedEntity] } };
      },
      post: async () => ({ Purchase: driftedEntity })
    } as unknown as QBOClient;

    const result = await dispatch(
      fakeClient,
      "123456",
      "updatePurchaseLineAccount",
      { purchaseId: "1", lineId: "1", expectedSyncToken: "0", newAccountId: "new-account" },
      true
    );
    expect(result.kind).toBe("success");
    if (result.kind === "success") {
      const data = result.data as { verified: boolean; otherLinesUnchanged: boolean };
      expect(data.verified).toBe(false);
      expect(data.otherLinesUnchanged).toBe(false);
    }
  });

  it("updatePurchaseLineAccount refuses a stale SyncToken rather than blindly overwriting", async () => {
    const beforeEntity = {
      Id: "1",
      SyncToken: "5", // QBO has 5; caller thinks it's 0
      Line: [{ Id: "1", AccountBasedExpenseLineDetail: { AccountRef: { value: "old-account" } } }]
    };
    const fakeClient = {
      get: async () => ({ QueryResponse: { Purchase: [beforeEntity] } }),
      post: async () => {
        throw new Error("post must not be called when SyncToken is stale");
      }
    } as unknown as QBOClient;

    const result = await dispatch(
      fakeClient,
      "123456",
      "updatePurchaseLineAccount",
      { purchaseId: "1", lineId: "1", expectedSyncToken: "0", newAccountId: "new-account" },
      true
    );
    expect(result.kind).toBe("operationError");
    if (result.kind === "operationError") {
      expect(result.message).toContain("Stale SyncToken");
    }
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
