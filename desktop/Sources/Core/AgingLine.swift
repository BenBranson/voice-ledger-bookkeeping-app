import Foundation

/// docs/VOICE_LEDGER_SPEC.md Page 12. `AgedReceivables`/`AgedPayables` —
/// verified live 2026-08-18. Neither `ReportLine` (single amount) nor
/// `TrialBalanceLine` (debit/credit) fit: this report has 6 money columns
/// per row (Current, 1-30, 31-60, 61-90, 91-and-over, Total) keyed by
/// customer or vendor name. Also verified live to mix leaf-row shapes
/// within the SAME report: a customer/vendor with no sub-locations is a
/// bare `ColData` row with no `type` tag at all (like Trial Balance), but
/// a customer with sub-customers appears as a `Header`/`Rows`/`Summary`
/// section whose nested rows ARE tagged `"type": "Data"` (like Balance
/// Sheet). `QBOSyncClient.flattenAging`'s leaf rule — has `ColData`, no
/// `Header`, no nested `Rows` — is deliberately structural, not
/// type-tag-based, so it catches both shapes correctly rather than
/// silently dropping whichever one it wasn't written to expect.
public struct AgingLine: Identifiable, Hashable, Sendable {
    public let id: String
    public let label: String
    public let current: Money?
    public let days1to30: Money?
    public let days31to60: Money?
    public let days61to90: Money?
    public let days91AndOver: Money?
    public let total: Money?
    public let depth: Int
    public let isSummary: Bool
    /// QBO Customer/Vendor Id from the report's name column, for a link to
    /// that customer's or vendor's page in QBO. Nil when QBO omits it.
    public let entityID: String?
    /// On the TOTAL line only: exact figures from the aging DETAIL report for the
    /// same date (2026-10-02). The summary's buckets net a credit against invoices
    /// in the same age bucket, so "owed before credits" read from buckets moved as
    /// a credit aged. Nil when the detail wasn't read.
    public var openItems: OpenItemsSplit?

    public init(
        label: String,
        current: Money?,
        days1to30: Money?,
        days31to60: Money?,
        days61to90: Money?,
        days91AndOver: Money?,
        total: Money?,
        depth: Int,
        isSummary: Bool,
        entityID: String? = nil
    ) {
        self.entityID = entityID
        self.id = "\(depth)-\(label)-\(isSummary)-\(UUID().uuidString.prefix(8))"
        self.label = label
        self.current = current
        self.days1to30 = days1to30
        self.days31to60 = days31to60
        self.days61to90 = days61to90
        self.days91AndOver = days91AndOver
        self.total = total
        self.depth = depth
        self.isSummary = isSummary
    }
}


/// Exact split of an aging report from its open documents (aging DETAIL report):
/// invoices/bills with an open balance are owed; credit memos, vendor credits and
/// unapplied payments are credits.
public struct OpenItemsSplit: Hashable, Sendable {
    public let owed: Money
    public let credits: Money
    /// Owed (positive open balances only) in the 61–90 and 91+ sections.
    public let over60Owed: Money
    /// Sum of every open balance; must equal the summary report's TOTAL.
    public let net: Money
    public let itemCount: Int

    public init(owed: Money, credits: Money, over60Owed: Money, net: Money, itemCount: Int) {
        self.owed = owed; self.credits = credits; self.over60Owed = over60Owed; self.net = net; self.itemCount = itemCount
    }
}
