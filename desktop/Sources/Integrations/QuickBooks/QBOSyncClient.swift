import Foundation
import Core

/// docs/phase-0/11_VERTICAL_SLICE.md §11.2's pipeline steps 1-3: sync
/// `Purchase` for the period via the backend's fixed catalog, normalize into
/// Core's shape (§4), with `Provenance` attached. This is the only place in
/// `IntegrationsQuickBooks` that constructs a `NormalizedDataSet` — `/core`
/// itself has zero knowledge of QBO's JSON shape, by design (`CLAUDE.md`:
/// `/core` never imports `/integrations`).
public struct QBOSyncClient: Sendable {
    private let backend: BackendClient

    public init(backend: BackendClient) {
        self.backend = backend
    }

    public struct ReadPurchasesParams: Encodable, Sendable {
        public let startDate: String
        public let endDate: String
        public init(startDate: String, endDate: String) {
            self.startDate = startDate
            self.endDate = endDate
        }
    }

    public struct ReadAccountsParams: Encodable, Sendable {
        public let activeOnly: Bool
        public init(activeOnly: Bool = true) {
            self.activeOnly = activeOnly
        }
    }

    /// Fetches `Purchase` for the period, `Account` (the full chart of
    /// accounts — needed by `VL-CC-PAYMENT-001` to know what a line was
    /// coded to), and `Preferences` for the company feature flag (§11.2's
    /// `.customTxnNumbersForPurchases`), and normalizes all three into a
    /// `NormalizedDataSet`. **`Coverage` is `.complete` only if the returned
    /// Purchase page count is strictly less than the requested
    /// `maxResults`** — a full page is treated as `.partial` pending real
    /// pagination (§2.6's checksum/offset-integrity machinery is specified
    /// but not wired in at this call site yet). This is the conservative
    /// direction to get wrong: a real gap could otherwise render green.
    /// Accounts are read `activeOnly` and are not period-scoped (the chart
    /// of accounts isn't a per-period concept), so an incomplete accounts
    /// page does not independently affect coverage here — a client with
    /// over 1000 active accounts would need real pagination on this call
    /// too, not yet built.
    public func sync(realmID: RealmID, period: AccountingPeriod) async throws -> NormalizedDataSet {
        let (startDate, endDate) = Self.dateRange(for: period)
        let maxResults = 1000

        let purchasesData = try await backend.call(
            .readPurchases,
            realmID: realmID,
            params: ReadPurchasesParams(startDate: startDate, endDate: endDate)
        )
        let accountsData = try await backend.call(
            .readAccounts,
            realmID: realmID,
            params: ReadAccountsParams()
        )
        let preferencesData = try await backend.call(
            .readPreferences,
            realmID: realmID,
            params: EmptyParams()
        )

        let decoder = JSONDecoder()
        let purchasesResponse = try decoder.decode(QBOPurchaseQueryResponse.self, from: purchasesData)
        let accountsResponse = try decoder.decode(QBOAccountQueryResponse.self, from: accountsData)
        let preferencesResponse = try decoder.decode(QBOPreferencesQueryResponse.self, from: preferencesData)

        let rawPurchases = purchasesResponse.queryResponse.purchase ?? []
        let coverage: Coverage = rawPurchases.count < maxResults
            ? .complete
            : .partial(reason: "readPurchases returned a full page (\(rawPurchases.count) of \(maxResults)) — pagination is not yet wired into this sync call, so completeness beyond one page is unverified.")

        let customTxnNumbers = preferencesResponse.queryResponse.preferences?.first?
            .vendorAndPurchasesPrefs?.useCustomTxnNumbers ?? false

        let transactions = rawPurchases.map { Self.normalize($0) }
        let accounts = (accountsResponse.queryResponse.account ?? []).compactMap { Self.normalize($0) }

        return NormalizedDataSet(
            realmID: realmID,
            period: period,
            transactions: transactions,
            accounts: accounts,
            coverage: coverage,
            companyFacts: CompanyFacts(customTxnNumbersForPurchases: customTxnNumbers)
        )
    }

    static func normalize(_ raw: QBORawPurchase) -> LedgerTransaction {
        LedgerTransaction(
            id: raw.id,
            entityKind: .purchase,
            vendorName: raw.entityRef?.name,
            txnDate: AccountingDate(qboDateString: raw.txnDate),
            totalAmount: Money(minorUnits: Self.minorUnits(from: raw.totalAmt), currency: .usd),
            paymentAccountID: raw.accountRef?.value,
            docNumber: raw.docNumber,
            // See QBORawPurchase's doc comment: verified 2026-08-17 against
            // a real manually-voided Purchase (spike item 51) — the
            // top-level "status": "Voided" field, not TotalAmt==0 (tried
            // first, DISPROVEN). Branch B's isVoided-exclusion resolution
            // path (§11.1) is now reachable end-to-end against real data.
            isVoided: raw.isVoided,
            memo: raw.privateNote,
            lineAccountIDs: raw.lineAccountIDs,
            provenance: .qboAPI(readAt: Date())
        )
    }

    /// `nil` for an `AccountType` value not in `LedgerAccountType`'s closed
    /// enum — silently dropping an unrecognized account would be worse
    /// (VL-CC-PAYMENT-001 would then falsely treat it as "not expense-like"
    /// and potentially match). Excluding it entirely means the rule's
    /// `lineAccounts.count == purchase.lineAccountIDs.count` check catches
    /// it and skips the transaction rather than guessing.
    static func normalize(_ raw: QBORawAccount) -> LedgerAccount? {
        guard let type = LedgerAccountType(rawValue: raw.accountType) else { return nil }
        return LedgerAccount(id: raw.id, name: raw.name, accountType: type)
    }

    static func minorUnits(from amount: Decimal) -> Int64 {
        let scaled = amount * 100
        return NSDecimalNumber(decimal: scaled).int64Value
    }

    static func dateRange(for period: AccountingPeriod) -> (start: String, end: String) {
        var comps = DateComponents()
        comps.year = period.year
        comps.month = period.month
        comps.day = 1
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let startDate = calendar.date(from: comps)!
        let range = calendar.range(of: .day, in: .month, for: startDate)!
        let lastDay = range.count
        func fmt(_ y: Int, _ m: Int, _ d: Int) -> String {
            String(format: "%04d-%02d-%02d", y, m, d)
        }
        return (fmt(period.year, period.month, 1), fmt(period.year, period.month, lastDay))
    }
}
