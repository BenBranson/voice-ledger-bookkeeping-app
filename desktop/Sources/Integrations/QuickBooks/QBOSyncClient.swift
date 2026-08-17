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

    /// Fetches `Purchase` for the period and `Preferences` for the company
    /// feature flag (§11.2's `.customTxnNumbersForPurchases`), and normalizes
    /// both into a `NormalizedDataSet`. **`Coverage` is `.complete` only if
    /// the returned page count is strictly less than the requested
    /// `maxResults`** — a full page is treated as `.partial` pending real
    /// pagination (§2.6's checksum/offset-integrity machinery is specified
    /// but not wired in at this call site yet; see the final report's note
    /// on what Part 5 left undone). This is the conservative direction to
    /// get wrong: a real gap could otherwise render green.
    public func sync(realmID: RealmID, period: AccountingPeriod) async throws -> NormalizedDataSet {
        let (startDate, endDate) = Self.dateRange(for: period)
        let maxResults = 1000

        let purchasesData = try await backend.call(
            .readPurchases,
            realmID: realmID,
            params: ReadPurchasesParams(startDate: startDate, endDate: endDate)
        )
        let preferencesData = try await backend.call(
            .readPreferences,
            realmID: realmID,
            params: EmptyParams()
        )

        let decoder = JSONDecoder()
        let purchasesResponse = try decoder.decode(QBOPurchaseQueryResponse.self, from: purchasesData)
        let preferencesResponse = try decoder.decode(QBOPreferencesQueryResponse.self, from: preferencesData)

        let rawPurchases = purchasesResponse.queryResponse.purchase ?? []
        let coverage: Coverage = rawPurchases.count < maxResults
            ? .complete
            : .partial(reason: "readPurchases returned a full page (\(rawPurchases.count) of \(maxResults)) — pagination is not yet wired into this sync call, so completeness beyond one page is unverified.")

        let customTxnNumbers = preferencesResponse.queryResponse.preferences?.first?
            .vendorAndPurchasesPrefs?.useCustomTxnNumbers ?? false

        let transactions = rawPurchases.map { Self.normalize($0) }

        return NormalizedDataSet(
            realmID: realmID,
            period: period,
            transactions: transactions,
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
            // See QBORawPurchase's doc comment: TotalAmt==0 was tried as
            // this signal and DISPROVEN against the live sandbox 2026-08-17
            // (false-positived on the legitimate $0 VL-SPIKE-ZERO fixture).
            // isVoidedHeuristic is now hardcoded false — Branch B's
            // isVoided-exclusion resolution path (§11.1) is real in the rule
            // engine but not yet reachable end-to-end against real synced
            // QBO data. Spike item 51 needs a real signal before this can
            // move past `false`.
            isVoided: raw.isVoidedHeuristic,
            memo: raw.privateNote,
            provenance: .qboAPI(readAt: Date())
        )
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
