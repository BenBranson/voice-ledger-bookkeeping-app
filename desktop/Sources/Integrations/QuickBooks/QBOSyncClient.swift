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

    public struct ReadVendorCreditsParams: Encodable, Sendable {
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

    public struct ReadReportParams: Encodable, Sendable {
        public let reportKind: String
        public let startDate: String
        public let endDate: String
        public init(reportKind: String, startDate: String, endDate: String) {
            self.reportKind = reportKind
            self.startDate = startDate
            self.endDate = endDate
        }
    }

    /// docs/VOICE_LEDGER_SPEC.md Page 12 (Type A), minimal slice — Balance
    /// Sheet only, flattened. Separate from `sync(realmID:period:)` since a
    /// report read is comparatively expensive and not every screen needs
    /// it every sync.
    public func fetchBalanceSheet(realmID: RealmID, period: AccountingPeriod) async throws -> [ReportLine] {
        try await fetchReport(reportKind: "BalanceSheet", realmID: realmID, period: period)
    }

    /// Profit & Loss — verified live to share the exact same recursive
    /// section shape as Balance Sheet (`Header`/`Rows`/optional `Summary`,
    /// leaf rows as `ColData` + `type == "Data"`), so the same decoder and
    /// `flatten` function apply unchanged.
    public func fetchProfitAndLoss(realmID: RealmID, period: AccountingPeriod) async throws -> [ReportLine] {
        try await fetchReport(reportKind: "ProfitAndLoss", realmID: realmID, period: period)
    }

    /// Cash Flow — verified live 2026-08-18 to share the same recursive
    /// `Header`/`Rows`/`Summary`/`ColData` + `type == "Data"` leaf shape as
    /// Balance Sheet and Profit & Loss (single "Total" money column), so the
    /// same decoder and `flatten` function apply unchanged. **Not** the same
    /// shape as Trial Balance or the aged-receivables/payables reports — see
    /// those reports' own notes in docs/VOICE_LEDGER_HANDOFF.md before
    /// reusing this function for them; their leaf rows carry no `type` tag
    /// at all and `flatten` would silently drop every one of them.
    public func fetchCashFlow(realmID: RealmID, period: AccountingPeriod) async throws -> [ReportLine] {
        try await fetchReport(reportKind: "CashFlow", realmID: realmID, period: period)
    }

    /// Trial Balance — deliberately NOT `fetchReport`/`ReportLine`. Verified
    /// live 2026-08-18 that this report's leaf rows have a `Debit` and a
    /// `Credit` column (never both populated) instead of a single signed
    /// amount, and carry no `type` field at all — see `TrialBalanceLine`'s
    /// doc comment for why reusing the other three reports' decoder here
    /// would silently drop every real account row.
    public func fetchTrialBalance(realmID: RealmID, period: AccountingPeriod) async throws -> [TrialBalanceLine] {
        let (startDate, endDate) = Self.dateRange(for: period)
        let data = try await backend.call(
            .readReport,
            realmID: realmID,
            params: ReadReportParams(reportKind: "TrialBalance", startDate: startDate, endDate: endDate)
        )
        let decoded = try JSONDecoder().decode(QBORawReport.self, from: data)
        return Self.flattenTrialBalance(decoded.rows)
    }

    /// Aged Receivables — verified live 2026-08-18. See `AgingLine`'s doc
    /// comment: 6 money columns per row, and leaf rows appear in TWO
    /// different shapes within the same real report (bare, untagged
    /// `ColData` for a customer with no sub-locations; `type: "Data"` when
    /// nested inside a customer-with-sub-customers section) — `flattenAging`
    /// detects leaves structurally so both are caught.
    public func fetchAgedReceivables(realmID: RealmID) async throws -> [AgingLine] {
        try await fetchAgingReport(reportKind: "AgedReceivables", realmID: realmID)
    }

    /// Aged Payables — verified live 2026-08-18 to share `AgedReceivables`'s
    /// exact shape (Vendor instead of Customer as the row key).
    public func fetchAgedPayables(realmID: RealmID) async throws -> [AgingLine] {
        try await fetchAgingReport(reportKind: "AgedPayables", realmID: realmID)
    }

    public struct ReadAgingReportParams: Encodable, Sendable {
        public let reportKind: String
        public init(reportKind: String) {
            self.reportKind = reportKind
        }
    }

    /// Deliberately no `startDate`/`endDate` sent at all (not even empty
    /// strings — the backend's param schema requires either a real
    /// `YYYY-MM-DD` or the key omitted entirely). Verified live that QBO's
    /// aging reports work fine called this way and come back "as of today"
    /// (their `Header` carries only an `EndPeriod`, defaulting to the
    /// current date, no `StartPeriod` at all) — whether passing explicit
    /// dates would change that behavior was not tested, since "as of now"
    /// is the correct semantics for an aging report regardless.
    private func fetchAgingReport(reportKind: String, realmID: RealmID) async throws -> [AgingLine] {
        let data = try await backend.call(
            .readReport,
            realmID: realmID,
            params: ReadAgingReportParams(reportKind: reportKind)
        )
        let decoded = try JSONDecoder().decode(QBORawReport.self, from: data)
        return Self.flattenAging(decoded.rows, depth: 0)
    }

    private func fetchReport(reportKind: String, realmID: RealmID, period: AccountingPeriod) async throws -> [ReportLine] {
        let (startDate, endDate) = Self.dateRange(for: period)
        let data = try await backend.call(
            .readReport,
            realmID: realmID,
            params: ReadReportParams(reportKind: reportKind, startDate: startDate, endDate: endDate)
        )
        let decoded = try JSONDecoder().decode(QBORawReport.self, from: data)
        return Self.flatten(decoded.rows, depth: 0)
    }

    public struct UpdatePurchaseLineAccountParams: Encodable, Sendable {
        public let purchaseId: String
        public let lineId: String
        public let expectedSyncToken: String
        public let newAccountId: String
        public init(purchaseId: String, lineId: String, expectedSyncToken: String, newAccountId: String) {
            self.purchaseId = purchaseId
            self.lineId = lineId
            self.expectedSyncToken = expectedSyncToken
            self.newAccountId = newAccountId
        }
    }

    /// Voice Ledger's first QBO write. Refused by the backend (HTTP 403)
    /// for any realm not in Write-Enabled mode — this call does not check
    /// that itself first, since the backend's check is the authoritative
    /// one (§10.4) and a client-side pre-check would just be a second,
    /// spoofable copy of the same gate. Callers should still show a clear
    /// error if this throws rather than a generic failure — a 403 here
    /// specifically means "write access is off," not "something broke."
    public func reclassifyPurchaseLine(
        realmID: RealmID,
        purchaseID: String,
        lineID: String,
        expectedSyncToken: String,
        newAccountID: String
    ) async throws -> WriteVerificationResult {
        let data = try await backend.call(
            .updatePurchaseLineAccount,
            realmID: realmID,
            params: UpdatePurchaseLineAccountParams(
                purchaseId: purchaseID,
                lineId: lineID,
                expectedSyncToken: expectedSyncToken,
                newAccountId: newAccountID
            )
        )
        return try WriteVerificationResult.parse(from: data)
    }

    /// A section row (`Header`/`Rows`/optional `Summary`) and a leaf data
    /// row (`ColData` + `type == "Data"`) are distinguished by which
    /// optional fields are present — see `QBORawReportRow`'s doc comment.
    static func flatten(_ rowList: QBORawReportRowList, depth: Int) -> [ReportLine] {
        var lines: [ReportLine] = []
        for row in rowList.row ?? [] {
            if let header = row.header {
                lines.append(ReportLine(label: header.colData.first?.value ?? "", amount: nil, depth: depth, isSummary: false))
            }
            if let nested = row.rows {
                lines.append(contentsOf: flatten(nested, depth: depth + 1))
            }
            if row.type == "Data", let colData = row.colData {
                lines.append(Self.reportLine(from: colData, depth: depth, isSummary: false))
            }
            if let summary = row.summary {
                lines.append(Self.reportLine(from: summary.colData, depth: depth, isSummary: true))
            }
        }
        return lines
    }

    /// Trial Balance's leaf rows carry no `type` field (unlike BalanceSheet/
    /// P&L/CashFlow's `"type": "Data"`), so a row is a leaf here whenever it
    /// has `colData` and neither `header` nor nested `rows` — not gated on
    /// `type` at all. Verified live: this sandbox's real TrialBalance is
    /// flat (54 leaf rows, one closing `Summary`, zero section nesting),
    /// but the recursive walk here handles nested sections too in case a
    /// different company's report groups by account type.
    static func flattenTrialBalance(_ rowList: QBORawReportRowList) -> [TrialBalanceLine] {
        var lines: [TrialBalanceLine] = []
        for row in rowList.row ?? [] {
            if let header = row.header {
                lines.append(TrialBalanceLine(label: header.colData.first?.value ?? "", debit: nil, credit: nil, isSummary: false))
            }
            if let nested = row.rows {
                lines.append(contentsOf: flattenTrialBalance(nested))
            }
            if row.header == nil, row.rows == nil, let colData = row.colData {
                lines.append(Self.trialBalanceLine(from: colData, isSummary: false))
            }
            if let summary = row.summary {
                lines.append(Self.trialBalanceLine(from: summary.colData, isSummary: true))
            }
        }
        return lines
    }

    private static func trialBalanceLine(from colData: [QBORawReportColData], isSummary: Bool) -> TrialBalanceLine {
        let label = colData.first?.value ?? ""
        func amount(at index: Int) -> Money? {
            guard colData.count > index else { return nil }
            let value = colData[index].value
            guard !value.isEmpty else { return nil }
            return Money(minorUnits: Self.minorUnits(from: Decimal(string: value) ?? 0), currency: .usd)
        }
        return TrialBalanceLine(label: label, debit: amount(at: 1), credit: amount(at: 2), isSummary: isSummary)
    }

    /// Aged Receivables/Payables — same structural leaf rule as
    /// `flattenTrialBalance` (has `ColData`, no `Header`, no nested `Rows`)
    /// rather than gating on `type`, because the real report mixes leaf
    /// shapes: a customer/vendor with no sub-locations is bare `ColData`
    /// with no `type` tag; a customer/vendor WITH sub-locations wraps them
    /// in a `Header`/`Rows`/`Summary` section whose nested leaf rows ARE
    /// tagged `"type": "Data"`. The structural rule catches both without
    /// needing to special-case either.
    static func flattenAging(_ rowList: QBORawReportRowList, depth: Int) -> [AgingLine] {
        var lines: [AgingLine] = []
        for row in rowList.row ?? [] {
            if let header = row.header {
                // Matches `flatten`'s convention for ReportLine: a section
                // header's own row carries no real amount (its Summary row,
                // appended after the children below, has the true rolled-up
                // total) even though QBO's raw JSON happens to echo one.
                lines.append(AgingLine(label: header.colData.first?.value ?? "", current: nil, days1to30: nil, days31to60: nil, days61to90: nil, days91AndOver: nil, total: nil, depth: depth, isSummary: false))
            }
            if let nested = row.rows {
                lines.append(contentsOf: flattenAging(nested, depth: depth + 1))
            }
            if row.header == nil, row.rows == nil, let colData = row.colData {
                lines.append(Self.agingLine(from: colData, depth: depth, isSummary: false))
            }
            if let summary = row.summary {
                lines.append(Self.agingLine(from: summary.colData, depth: depth, isSummary: true))
            }
        }
        return lines
    }

    private static func agingLine(from colData: [QBORawReportColData], depth: Int, isSummary: Bool) -> AgingLine {
        let label = colData.first?.value ?? ""
        func amount(at index: Int) -> Money? {
            guard colData.count > index else { return nil }
            let value = colData[index].value
            guard !value.isEmpty else { return nil }
            return Money(minorUnits: Self.minorUnits(from: Decimal(string: value) ?? 0), currency: .usd)
        }
        return AgingLine(
            label: label,
            current: amount(at: 1),
            days1to30: amount(at: 2),
            days31to60: amount(at: 3),
            days61to90: amount(at: 4),
            days91AndOver: amount(at: 5),
            total: amount(at: 6),
            depth: depth,
            isSummary: isSummary
        )
    }

    private static func reportLine(from colData: [QBORawReportColData], depth: Int, isSummary: Bool) -> ReportLine {
        let label = colData.first?.value ?? ""
        let amountString = colData.count > 1 ? colData[1].value : nil
        let amount = amountString.flatMap { $0.isEmpty ? nil : Money(minorUnits: Self.minorUnits(from: Decimal(string: $0) ?? 0), currency: .usd) }
        return ReportLine(label: label, amount: amount, depth: depth, isSummary: isSummary)
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
        let vendorCreditsData = try await backend.call(
            .readVendorCredits,
            realmID: realmID,
            params: ReadVendorCreditsParams(startDate: startDate, endDate: endDate)
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
        let vendorCreditsResponse = try decoder.decode(QBOVendorCreditQueryResponse.self, from: vendorCreditsData)
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
        let vendorCredits = (vendorCreditsResponse.queryResponse.vendorCredit ?? []).map { Self.normalize($0) }

        return NormalizedDataSet(
            realmID: realmID,
            period: period,
            transactions: transactions,
            accounts: accounts,
            vendors: vendors,
            deposits: deposits,
            vendorCredits: vendorCredits,
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
            lines: Self.lines(from: raw.line),
            syncToken: raw.syncToken,
            provenance: .qboAPI(readAt: Date())
        )
    }

    /// `nil` for an `AccountType` value not in `LedgerAccountType`'s closed
    /// enum — silently dropping an unrecognized account would be worse
    /// (VL-CC-PAYMENT-001 would then falsely treat it as "not expense-like"
    /// and potentially match). Excluding it entirely means the rule's
    /// `lineAccounts.count == purchase.lineAccountIDs.count` check catches
    /// it and skips the transaction rather than guessing.
    /// A line with no `Id` (shouldn't happen on any real read — QBO always
    /// assigns one — but the field is optional in the raw decode) or no
    /// `AccountBasedExpenseLineDetail` is skipped, not guessed at, same
    /// discipline as `lineAccountIDs` already uses.
    static func lines(from rawLines: [QBORawPurchaseLine]?) -> [LedgerTransactionLine] {
        (rawLines ?? []).compactMap { rawLine in
            guard let lineID = rawLine.id, let accountID = rawLine.accountBasedExpenseLineDetail?.accountRef?.value else { return nil }
            return LedgerTransactionLine(id: lineID, accountID: accountID)
        }
    }

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
            lines: Self.lines(from: raw.line),
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

    /// `balance` defaults to 0 (not `totalAmt`) when QBO omits the field —
    /// the conservative direction to get wrong: treating an unexpected
    /// absence as "fully applied" understates findings rather than
    /// overstating them.
    static func normalize(_ raw: QBORawVendorCredit) -> LedgerVendorCredit {
        LedgerVendorCredit(
            id: raw.id,
            vendorName: raw.vendorRef?.name,
            txnDate: AccountingDate(qboDateString: raw.txnDate),
            totalAmount: Money(minorUnits: Self.minorUnits(from: raw.totalAmt), currency: .usd),
            balance: Money(minorUnits: Self.minorUnits(from: raw.balance ?? 0), currency: .usd),
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
