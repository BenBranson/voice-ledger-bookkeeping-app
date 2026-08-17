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

    public struct ReadBillsParams: Encodable, Sendable {
        public let startDate: String
        public let endDate: String
        public init(startDate: String, endDate: String) {
            self.startDate = startDate
            self.endDate = endDate
        }
    }

    public struct ReadVendorsParams: Encodable, Sendable {
        public let activeOnly: Bool
        public init(activeOnly: Bool = true) {
            self.activeOnly = activeOnly
        }
    }

    public struct ReadInvoicesParams: Encodable, Sendable {
        public let startDate: String
        public let endDate: String
        public init(startDate: String, endDate: String) {
            self.startDate = startDate
            self.endDate = endDate
        }
    }

    public struct ReadPaymentsParams: Encodable, Sendable {
        public let startDate: String
        public let endDate: String
        public init(startDate: String, endDate: String) {
            self.startDate = startDate
            self.endDate = endDate
        }
    }

    public struct ReadDepositsParams: Encodable, Sendable {
        public let startDate: String
        public let endDate: String
        public init(startDate: String, endDate: String) {
            self.startDate = startDate
            self.endDate = endDate
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
    /// Connection Page (step 1.3) support — connection-level info, not
    /// period-scoped, so kept separate from `sync(realmID:period:)`.
    public func fetchCompanyInfo(realmID: RealmID) async throws -> CompanyConnectionInfo {
        let data = try await backend.call(.readCompanyInfo, realmID: realmID, params: EmptyParams())
        let decoded = try JSONDecoder().decode(QBORawCompanyInfoResponse.self, from: data)
        return CompanyConnectionInfo(companyName: decoded.companyInfo.companyName, realmID: realmID)
    }

    public func sync(realmID: RealmID, period: AccountingPeriod) async throws -> NormalizedDataSet {
        let (startDate, endDate) = Self.dateRange(for: period)
        let maxResults = 1000

        let purchasesData = try await backend.call(
            .readPurchases,
            realmID: realmID,
            params: ReadPurchasesParams(startDate: startDate, endDate: endDate)
        )
        let billsData = try await backend.call(
            .readBills,
            realmID: realmID,
            params: ReadBillsParams(startDate: startDate, endDate: endDate)
        )
        let accountsData = try await backend.call(
            .readAccounts,
            realmID: realmID,
            params: ReadAccountsParams()
        )
        let vendorsData = try await backend.call(
            .readVendors,
            realmID: realmID,
            params: ReadVendorsParams()
        )
        let invoicesData = try await backend.call(
            .readInvoices,
            realmID: realmID,
            params: ReadInvoicesParams(startDate: startDate, endDate: endDate)
        )
        let paymentsData = try await backend.call(
            .readPayments,
            realmID: realmID,
            params: ReadPaymentsParams(startDate: startDate, endDate: endDate)
        )
        // Note: scoped to the same period as everything else, so a Payment
        // dated near the period boundary that was swept by a Deposit
        // outside this window won't be matched — VL-BS-UNDEP-001 accepts
        // this as a known limitation rather than widening every other
        // entity's window to compensate.
        let depositsData = try await backend.call(
            .readDeposits,
            realmID: realmID,
            params: ReadDepositsParams(startDate: startDate, endDate: endDate)
        )
        let preferencesData = try await backend.call(
            .readPreferences,
            realmID: realmID,
            params: EmptyParams()
        )

        let decoder = JSONDecoder()
        let purchasesResponse = try decoder.decode(QBOPurchaseQueryResponse.self, from: purchasesData)
        let billsResponse = try decoder.decode(QBOBillQueryResponse.self, from: billsData)
        let accountsResponse = try decoder.decode(QBOAccountQueryResponse.self, from: accountsData)
        let vendorsResponse = try decoder.decode(QBOVendorQueryResponse.self, from: vendorsData)
        let invoicesResponse = try decoder.decode(QBOInvoiceQueryResponse.self, from: invoicesData)
        let paymentsResponse = try decoder.decode(QBOPaymentQueryResponse.self, from: paymentsData)
        let depositsResponse = try decoder.decode(QBODepositQueryResponse.self, from: depositsData)
        let preferencesResponse = try decoder.decode(QBOPreferencesQueryResponse.self, from: preferencesData)

        let rawPurchases = purchasesResponse.queryResponse.purchase ?? []
        let rawBills = billsResponse.queryResponse.bill ?? []
        let rawInvoices = invoicesResponse.queryResponse.invoice ?? []
        let rawPayments = paymentsResponse.queryResponse.payment ?? []
        let coverage: Coverage = (rawPurchases.count < maxResults && rawBills.count < maxResults && rawInvoices.count < maxResults && rawPayments.count < maxResults)
            ? .complete
            : .partial(reason: "readPurchases, readBills, readInvoices, or readPayments returned a full page (\(rawPurchases.count) purchases, \(rawBills.count) bills, \(rawInvoices.count) invoices, \(rawPayments.count) payments, of \(maxResults) max) — pagination is not yet wired into this sync call, so completeness beyond one page is unverified.")

        let customTxnNumbers = preferencesResponse.queryResponse.preferences?.first?
            .vendorAndPurchasesPrefs?.useCustomTxnNumbers ?? false

        // Purchase and Bill normalize into the SAME LedgerTransaction shape,
        // distinguished only by entityKind — the whole point of §4.1's
        // normalization contract (rules can't tell the source apart).
        let transactions = rawPurchases.map { Self.normalize($0) } + rawBills.map { Self.normalize($0) } + rawInvoices.map { Self.normalize($0) } + rawPayments.map { Self.normalize($0) }
        let accounts = (accountsResponse.queryResponse.account ?? []).compactMap { Self.normalize($0) }
        let vendors = (vendorsResponse.queryResponse.vendor ?? []).map { Self.normalize($0) }
        let deposits = (depositsResponse.queryResponse.deposit ?? []).map { Self.normalize($0) }

        return NormalizedDataSet(
            realmID: realmID,
            period: period,
            transactions: transactions,
            accounts: accounts,
            vendors: vendors,
            deposits: deposits,
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
        let balance = raw.currentBalance.map { Money(minorUnits: Self.minorUnits(from: $0), currency: .usd) } ?? .zero
        return LedgerAccount(id: raw.id, name: raw.name, accountType: type, accountSubType: raw.accountSubType, currentBalance: balance)
    }

    /// `isVoided` uses the same `status == "Voided"` check as Purchase, but
    /// **this has NOT been independently verified for Bill** — spike item 51
    /// confirmed the signal only for a manually-voided Purchase. Bill void
    /// via the API is separately confirmed anomalous (Wave 3: HTTP 200 with
    /// a leaked SystemFault), which is about the WRITE path, not this READ
    /// signal. Flagged rather than silently assumed to carry the same
    /// guarantee.
    static func normalize(_ raw: QBORawBill) -> LedgerTransaction {
        LedgerTransaction(
            id: raw.id,
            entityKind: .bill,
            vendorName: raw.vendorRef?.name,
            txnDate: AccountingDate(qboDateString: raw.txnDate),
            totalAmount: Money(minorUnits: Self.minorUnits(from: raw.totalAmt), currency: .usd),
            paymentAccountID: raw.apAccountRef?.value,
            docNumber: raw.docNumber,
            isVoided: raw.isVoided,
            memo: raw.privateNote,
            lineAccountIDs: raw.lineAccountIDs,
            provenance: .qboAPI(readAt: Date())
        )
    }

    /// `isVoided` reuses Purchase's proven `status == "Voided"` signal —
    /// see `QBORawInvoice`'s doc comment: not independently live-verified
    /// for Invoice, flagged rather than silently assumed.
    static func normalize(_ raw: QBORawInvoice) -> LedgerTransaction {
        LedgerTransaction(
            id: raw.id,
            entityKind: .invoice,
            vendorName: raw.customerRef?.name,
            txnDate: AccountingDate(qboDateString: raw.txnDate),
            totalAmount: Money(minorUnits: Self.minorUnits(from: raw.totalAmt), currency: .usd),
            paymentAccountID: nil,
            docNumber: raw.docNumber,
            isVoided: raw.isVoided,
            memo: raw.privateNote,
            lineAccountIDs: [],
            provenance: .qboAPI(readAt: Date())
        )
    }

    /// `isVoided` is decoded but unverified for Payment — see
    /// `QBORawPayment`'s doc comment.
    /// `paymentAccountID` is set to `DepositToAccountRef` here — the
    /// account the payment is heading to (Undeposited Funds, almost
    /// always), not an account it was paid FROM the way a Purchase's
    /// `paymentAccountID` works. `VL-BS-UNDEP-001` is the reason this
    /// field is populated at all; no other rule currently reads it on a
    /// `.payment` transaction.
    static func normalize(_ raw: QBORawPayment) -> LedgerTransaction {
        LedgerTransaction(
            id: raw.id,
            entityKind: .payment,
            vendorName: raw.customerRef?.name,
            txnDate: AccountingDate(qboDateString: raw.txnDate),
            totalAmount: Money(minorUnits: Self.minorUnits(from: raw.totalAmt), currency: .usd),
            paymentAccountID: raw.depositToAccountRef?.value,
            docNumber: nil,
            isVoided: raw.isVoided,
            memo: raw.privateNote,
            lineAccountIDs: [],
            provenance: .qboAPI(readAt: Date())
        )
    }

    static func normalize(_ raw: QBORawVendor) -> LedgerVendor {
        LedgerVendor(id: raw.id, displayName: raw.displayName, isActive: raw.active ?? true)
    }

    static func normalize(_ raw: QBORawDeposit) -> LedgerDeposit {
        LedgerDeposit(id: raw.id, linkedPaymentIDs: raw.linkedPaymentIDs)
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
