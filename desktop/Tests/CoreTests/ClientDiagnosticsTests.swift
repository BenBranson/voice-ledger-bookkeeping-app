import Testing
@testable import Core
import Foundation

@Suite("ClientDiagnostics")
struct ClientDiagnosticsTests {
    let realm = RealmID(rawValue: "9341456442848752")
    let asOf = AccountingDate(year: 2026, month: 9, day: 29)

    func usd(_ cents: Int64) -> Money { Money(minorUnits: cents, currency: .usd) }

    func txn(_ id: String, _ kind: QBOEntityKind, account: String?, day: AccountingDate, cents: Int64 = 10_000) -> LedgerTransaction {
        LedgerTransaction(id: id, entityKind: kind, vendorName: "V", txnDate: day, totalAmount: usd(cents), paymentAccountID: account,
                          docNumber: nil, isVoided: false, memo: nil, provenance: .qboAPI(readAt: Date()))
    }

    func pl(_ period: AccountingPeriod, _ lines: [(String, Int64)]) -> MonthlyReport {
        MonthlyReport(period: period, lines: lines.map { ReportLine(label: $0.0, amount: usd($0.1), depth: 1, isSummary: false) })
    }

    func history(transactions: [LedgerTransaction] = [], deposits: [LedgerDeposit] = [], accounts: [LedgerAccount] = [], monthly: [MonthlyReport] = [], balanceSheet: [ReportLine] = [], cashFlow: [ReportLine] = []) -> HistorySnapshot {
        HistorySnapshot(realmID: realm, fetchedAt: Date(), from: AccountingDate(year: 2024, month: 10, day: 1), through: asOf,
                        transactions: transactions, deposits: deposits, vendorCredits: [], accounts: accounts,
                        monthlyProfitAndLoss: monthly, latestBalanceSheet: balanceSheet, latestCashFlow: cashFlow, coverage: .complete)
    }

    @Test("Stale feed: an account whose newest posting is over 5 days old is stale; a recent one isn't")
    func staleFeed() {
        let accounts = [LedgerAccount(id: "chk", name: "Checking", accountType: .bank), LedgerAccount(id: "cc", name: "Amex", accountType: .creditCard), LedgerAccount(id: "exp", name: "Supplies", accountType: .expense)]
        let h = history(
            transactions: [txn("1", .purchase, account: "chk", day: AccountingDate(year: 2026, month: 9, day: 27))],
            deposits: [LedgerDeposit(id: "d", linkedPaymentIDs: [], txnDate: AccountingDate(year: 2026, month: 9, day: 10), depositToAccountID: "cc")],
            accounts: accounts
        )
        let activity = ClientDiagnostics.bankFeedActivity(history: h, asOf: asOf)
        #expect(activity.count == 2)
        #expect(activity.first { $0.accountID == "chk" }?.isStale == false)
        #expect(activity.first { $0.accountID == "cc" }?.daysSinceLastActivity == 19)
        #expect(activity.first { $0.accountID == "cc" }?.isStale == true)
    }

    @Test("Stale feed: an account with no postings at all is stale with unknown last activity")
    func noActivityIsStale() {
        let h = history(accounts: [LedgerAccount(id: "chk", name: "Checking", accountType: .bank)])
        let activity = ClientDiagnostics.bankFeedActivity(history: h, asOf: asOf)
        #expect(activity.first?.lastActivity == nil)
        #expect(activity.first?.isStale == true)
    }

    @Test("Flux: >20% AND >$500 vs the trailing 3-month average is flagged; small swings are not")
    func flux() {
        let monthly = [
            pl(AccountingPeriod(year: 2026, month: 5), [("Rent", 200_000), ("Supplies", 10_000)]),
            pl(AccountingPeriod(year: 2026, month: 6), [("Rent", 200_000), ("Supplies", 10_000)]),
            pl(AccountingPeriod(year: 2026, month: 7), [("Rent", 200_000), ("Supplies", 10_000)]),
            pl(AccountingPeriod(year: 2026, month: 8), [("Rent", 300_000), ("Supplies", 30_000)]),
            pl(AccountingPeriod(year: 2026, month: 9), [("Rent", 999_999)])
        ]
        let alerts = ClientDiagnostics.fluxAlerts(history: history(monthly: monthly), asOf: asOf)
        #expect(alerts.map(\.label) == ["Rent"])
        #expect(alerts.first?.period == AccountingPeriod(year: 2026, month: 8))
        #expect(alerts.first?.change == usd(100_000))
    }

    @Test("Flux needs 4 complete months; fewer returns nothing rather than a misleading comparison")
    func fluxNeedsHistory() {
        let monthly = [pl(AccountingPeriod(year: 2026, month: 7), [("Rent", 1)]), pl(AccountingPeriod(year: 2026, month: 8), [("Rent", 900_000)])]
        #expect(ClientDiagnostics.fluxAlerts(history: history(monthly: monthly), asOf: asOf).isEmpty)
    }

    @Test("KPI: DSO from A/R over trailing-90-day revenue, OCF from the real cash flow label")
    func kpis() {
        func income(_ p: AccountingPeriod, _ cents: Int64) -> MonthlyReport {
            MonthlyReport(period: p, lines: [ReportLine(label: "Total Income", amount: usd(cents), depth: 0, isSummary: true)])
        }
        let h = history(
            monthly: [income(AccountingPeriod(year: 2026, month: 6), 300_000), income(AccountingPeriod(year: 2026, month: 7), 300_000), income(AccountingPeriod(year: 2026, month: 8), 300_000)],
            balanceSheet: [ReportLine(label: "Total Accounts Receivable", amount: usd(300_000), depth: 0, isSummary: true)],
            cashFlow: [ReportLine(label: "Net cash provided by operating activities", amount: usd(-9_000), depth: 0, isSummary: true)]
        )
        let kpi = ClientDiagnostics.kpiSummary(history: h, asOf: asOf)
        #expect(kpi.daysSalesOutstanding == 30)
        #expect(kpi.operatingCashFlow == usd(-9_000))
        #expect(kpi.emailBullets.contains("Operating cash flow: ($90.00)"))
        #expect(kpi.emailBullets.contains { $0.hasPrefix("Gross margin: not available") })
        #expect(kpi.emailBullets.first == "Revenue for August 2026: $3,000.00")
    }

    @Test("Scope score: the owner's quote formula — base + months×$150 + anomalies×$35 + uncategorized×$2.50")
    func quoteFormula() {
        func finding(_ rule: String, _ id: String) -> Finding {
            Finding(id: id, ruleID: RuleID(rawValue: rule), ruleVersion: RuleVersion(major: 1, minor: 0, patch: 0), realmID: realm,
                    period: AccountingPeriod(year: 2026, month: 7), title: "t", severity: .high, confidence: .high, dollarExposure: usd(10_000),
                    evidence: [], proposedActions: [], provenance: [], narrative: nil, riskIfIgnored: nil)
        }
        let findings = (0..<4).map { finding("VL-DUP-BILL-001", "a\($0)") } + (0..<10).map { finding("VL-CAT-UNCAT-001", "u\($0)") }
        let accounts = [
            LedgerAccount(id: "1", name: "Office Supplies", accountType: .expense, fullyQualifiedName: "Office Supplies"),
            LedgerAccount(id: "2", name: "Office supplies.", accountType: .expense, fullyQualifiedName: "Office supplies."),
            LedgerAccount(id: "3", name: "Repairs", accountType: .expense, fullyQualifiedName: "Truck:Repairs"),
            LedgerAccount(id: "4", name: "Repairs", accountType: .expense, fullyQualifiedName: "Building:Repairs")
        ]
        let score = ClientDiagnostics.scopeScore(history: history(accounts: accounts), openFindings: findings, asOf: asOf, inputs: CleanupScopeInputs(unreconciledMonths: 6))
        // 500 + 6×150 + 4×35 + 10×2.50 = 1,565.00
        #expect(score.cleanupQuote == usd(156_500))
        #expect(score.openAnomalies == 4)
        #expect(score.uncategorizedTransactions == 10)
        #expect(score.duplicateAccountGroups == 1)
        #expect(score.totalExposure == usd(140_000))
    }
}
