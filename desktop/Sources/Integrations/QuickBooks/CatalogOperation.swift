/// The fixed catalog of named backend operations the desktop client can
/// invoke. Mirrors `backend/src/catalog/operations.ts` — not shared code
/// (different languages, different processes), but a deliberately identical
/// closed set.
///
/// docs/phase-0/03_SECURITY_THREAT_MODEL.md §3.4, decision D5: "The desktop
/// client cannot express a QBO request... it can only invoke a named,
/// typed operation." This enum is the desktop-side half of that guarantee —
/// there is no `CatalogOperation` case that accepts an arbitrary path or
/// method, so nothing in `IntegrationsQuickBooks` can construct one.
///
/// **Phase 1, step 1.2 scope: read-only.** No write-classified case exists
/// yet. Per the owner's Phase 1 approval: "No write operation enters the
/// catalog until its spike test has passed" — see docs/phase-0/SPIKE_QUEUE.md.
/// Adding a case here without the matching backend implementation and a
/// passing capability-spike test is exactly the mistake §3.4 exists to make
/// structurally hard.
public enum CatalogOperation: String, Sendable, CaseIterable {
    case readCompanyInfo
    case readPreferences
    case readAccounts
    case readPurchases
    /// Added 2026-08-17 alongside `VL-DUP-VEND-001` — mirrors the backend's
    /// `readVendors` operation (`backend/src/catalog/operations.ts`), added
    /// in the same commit.
    case readVendors
    case readReport
    case cdcSince
}
