import Testing
@testable import Core
import Foundation

@Suite("VL-VEND-ANOMALY-001 — VendorAnomalyRule")
struct VendorAnomalyRuleTests {
    let realm = RealmID(rawValue: "9341456442848752")
    let period = AccountingPeriod(year: 2026, month: 7)

    func context() -> RuleContext {
        RuleContext(period: period, materiality: .defaultPolicy, companyFacts: CompanyFacts(customTxnNumbersForPurchases: false))
    }

    func purchase(
        id: String,
        vendor: String?,
        amountMinorUnits: Int64,
        isVoided: Bool = false
    ) -> LedgerTransaction {
        LedgerTransaction(
            id: id,
            entityKind: .purchase,
            vendorName: vendor,
            txnDate: AccountingDate(year: 2026, month: 7, day: 15),
            totalAmount: Money(minorUnits: amountMinorUnits, currency: .usd),
            paymentAccountID: "checking-1",
            docNumber: nil,
            isVoided: isVoided,
            memo: nil,
            provenance: .qboAPI(readAt: Date())
        )
    }

    func dataSet(_ transactions: [LedgerTransaction], coverage: Coverage = .complete) -> NormalizedDataSet {
        NormalizedDataSet(
            realmID: realm, period: period, transactions: transactions,
            coverage: coverage, companyFacts: CompanyFacts(customTxnNumbersForPurchases: false)
        )
    }

    // 2026-10-02: the charge being judged no longer counts toward its own "normal", so a
    // finding needs 3 OTHER charges (this month or the prior 12 months).
    @Test("A transaction at 4x the median of the vendor's other charges produces a finding")
    func largeOutlierProducesFinding() {
        let txns = [
            purchase(id: "1", vendor: "Acme Supply", amountMinorUnits: 10_000),
            purchase(id: "2", vendor: "Acme Supply", amountMinorUnits: 11_000),
            purchase(id: "4", vendor: "Acme Supply", amountMinorUnits: 10_500),
            purchase(id: "3", vendor: "Acme Supply", amountMinorUnits: 40_000)
        ]
        let outcome = VendorAnomalyRule.evaluate(dataSet(txns), context: context())
        guard case .findings(let findings) = outcome, findings.count == 1 else {
            Issue.record("expected one finding")
            return
        }
        #expect(findings[0].evidence.first?.transactionID == "3")
        #expect(findings[0].confidence == .medium)
    }

    @Test("A vendor with only ordinary variation (all under 3x median) produces .pass")
    func ordinaryVariationProducesPass() {
        let txns = [
            purchase(id: "1", vendor: "Acme Supply", amountMinorUnits: 10_000),
            purchase(id: "2", vendor: "Acme Supply", amountMinorUnits: 12_000),
            purchase(id: "3", vendor: "Acme Supply", amountMinorUnits: 15_000)
        ]
        let outcome = VendorAnomalyRule.evaluate(dataSet(txns), context: context())
        guard case .pass = outcome else {
            Issue.record("expected .pass — no transaction reaches 3x the median")
            return
        }
    }

    @Test("A vendor with fewer than 3 transactions this period is not evaluated for anomalies")
    func fewerThanThreeTransactionsSkipsVendor() {
        let txns = [
            purchase(id: "1", vendor: "Acme Supply", amountMinorUnits: 10_000),
            purchase(id: "2", vendor: "Acme Supply", amountMinorUnits: 100_000)
        ]
        let outcome = VendorAnomalyRule.evaluate(dataSet(txns), context: context())
        guard case .pass = outcome else {
            Issue.record("expected .pass — only 2 transactions, no baseline")
            return
        }
    }

    @Test("A voided transaction is excluded from both the baseline and candidacy")
    func voidedTransactionExcluded() {
        let txns = [
            purchase(id: "1", vendor: "Acme Supply", amountMinorUnits: 10_000),
            purchase(id: "2", vendor: "Acme Supply", amountMinorUnits: 11_000),
            purchase(id: "3", vendor: "Acme Supply", amountMinorUnits: 40_000, isVoided: true)
        ]
        let outcome = VendorAnomalyRule.evaluate(dataSet(txns), context: context())
        guard case .pass = outcome else {
            Issue.record("expected .pass — the outlier is voided and excluded, leaving only 2 real transactions")
            return
        }
    }

    @Test("Different vendors do not share a baseline with each other")
    func differentVendorsHaveSeparateBaselines() {
        let txns = [
            purchase(id: "1", vendor: "Acme Supply", amountMinorUnits: 10_000),
            purchase(id: "2", vendor: "Acme Supply", amountMinorUnits: 11_000),
            purchase(id: "3", vendor: "Acme Supply", amountMinorUnits: 12_000),
            purchase(id: "4", vendor: "Beta Vendor", amountMinorUnits: 100_000),
            purchase(id: "5", vendor: "Beta Vendor", amountMinorUnits: 110_000),
            purchase(id: "6", vendor: "Beta Vendor", amountMinorUnits: 120_000)
        ]
        let outcome = VendorAnomalyRule.evaluate(dataSet(txns), context: context())
        guard case .pass = outcome else {
            Issue.record("expected .pass — each vendor's amounts are consistent within themselves")
            return
        }
    }

    @Test("A transaction with no vendor name is excluded")
    func noVendorNameExcluded() {
        let txns = [
            purchase(id: "1", vendor: nil, amountMinorUnits: 10_000),
            purchase(id: "2", vendor: nil, amountMinorUnits: 11_000),
            purchase(id: "3", vendor: nil, amountMinorUnits: 40_000)
        ]
        let outcome = VendorAnomalyRule.evaluate(dataSet(txns), context: context())
        guard case .pass = outcome else {
            Issue.record("expected .pass — no vendor name means no grouping possible")
            return
        }
    }

    @Test("The rule never claims .pass on incomplete coverage")
    func neverClaimsPassOnPartialCoverage() {
        let outcome = VendorAnomalyRule.evaluate(
            dataSet([], coverage: .partial(reason: "sync incomplete")),
            context: context()
        )
        if case .pass = outcome {
            Issue.record("rule must not report .pass on partial coverage")
        }
    }

    @Test("median(of:) computes the standard median for both odd and even counts")
    func medianComputation() {
        #expect(VendorAnomalyRule.median(of: [10, 20, 30]) == 20)
        #expect(VendorAnomalyRule.median(of: [10, 20, 30, 40]) == 25)
        #expect(VendorAnomalyRule.median(of: []) == 0)
    }

    func charge(_ id: String, _ vendor: String, _ amount: Int64, _ month: Int, _ day: Int = 15, kind: QBOEntityKind = .purchase) -> LedgerTransaction {
        LedgerTransaction(id: id, entityKind: kind, vendorName: vendor, txnDate: AccountingDate(year: 2026, month: month, day: day),
                          totalAmount: Money(minorUnits: amount, currency: .usd), paymentAccountID: "checking-1", docNumber: nil,
                          isVoided: false, memo: nil, provenance: .qboAPI(readAt: Date()))
    }

    @Test("Owner test 2026-10-02: a first bill plus a duplicate pair is not 'unusual' — duplicates never set the baseline")
    func duplicatesDoNotSetTheBaseline() {
        let txns = [charge("a", "VLT Permian Pipe", 234_000, 7, 2, kind: .bill),
                    charge("b", "VLT Permian Pipe", 61_500, 7, 8, kind: .bill), charge("c", "VLT Permian Pipe", 61_500, 7, 8, kind: .bill)]
        if case .findings = VendorAnomalyRule.evaluate(dataSet(txns), context: context()) { Issue.record("flagged against its own duplicates") }
    }

    @Test("History sets 'normal': one large charge against 12 months of small ones is flagged, citing the history")
    func historyBaseline() {
        let history = (1...6).map { charge("h\($0)", "Chin's Gas", 26_000, $0) }
        let data = NormalizedDataSet(realmID: realm, period: period, transactions: [charge("big", "Chin's Gas", 115_000, 7)],
                                     historyTransactions: history, coverage: .complete, companyFacts: CompanyFacts(customTxnNumbersForPurchases: false))
        guard case .findings(let f) = VendorAnomalyRule.evaluate(data, context: context()), let first = f.first else { Issue.record("expected a finding"); return }
        #expect(first.narrative?.contains("6 charges over the last 12 months") == true)
    }

    @Test("Customer invoices are not vendor charges")
    func invoicesIgnored() {
        let txns = [charge("1", "Desert Rose", 10_000, 7, kind: .invoice), charge("2", "Desert Rose", 10_000, 7, 3, kind: .invoice),
                    charge("3", "Desert Rose", 10_000, 7, 4, kind: .invoice), charge("4", "Desert Rose", 90_000, 7, 5, kind: .invoice)]
        if case .findings = VendorAnomalyRule.evaluate(dataSet(txns), context: context()) { Issue.record("flagged an invoice") }
    }
}
