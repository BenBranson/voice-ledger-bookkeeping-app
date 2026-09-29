import Testing
@testable import Core
import Foundation

@Suite("Work log, dismiss reasons, and report sections")
struct WorkLogAndSectionsTests {
    let realm = RealmID(rawValue: "r")
    let period = AccountingPeriod(year: 2026, month: 7)
    func usd(_ c: Int64) -> Money { Money(minorUnits: c, currency: .usd) }

    func finding(_ id: String, rule: String, status: FindingStatus, cents: Int64 = 85_000) -> Finding {
        var f = Finding(id: id, ruleID: RuleID(rawValue: rule), ruleVersion: RuleVersion(major: 1, minor: 0, patch: 0), realmID: realm, period: period,
                        title: "T\(id)", severity: .high, confidence: .high, dollarExposure: usd(cents), evidence: [], proposedActions: [], provenance: [], narrative: "N\(id)", riskIfIgnored: nil)
        f.status = status
        return f
    }
    func log(_ id: String, _ kind: ActivityKind, _ note: String?) -> ActivityLogEntry {
        ActivityLogEntry(realmID: realm, recordedAt: Date(timeIntervalSince1970: 1_786_000_000), actor: .user("Benjamin"), kind: kind, findingID: id, note: note)
    }

    @Test("Outcome comes from what QBO shows, not from the note alone")
    func statuses() {
        let findings = [
            finding("a", rule: "VL-DUP-EXP-001", status: .resolved),
            finding("b", rule: "VL-CAT-UNCAT-001", status: .open),
            finding("c", rule: "VL-CAT-UNCAT-001", status: .open),
            finding("d", rule: "VL-VEND-PRICE-001", status: .dismissed)
        ]
        let items = WorkLog.items(activityLog: [
            log("a", .manualCompletionAttested, "Corrected in QBO: voided copy"),
            log("b", .manualCompletionAttested, "Reclassified Transaction: moved"),
            log("c", .manualCompletionAttested, "Client Clarification Needed: asked Kris"),
            log("d", .findingDismissed, "Not an error — legitimate transaction: new rate")
        ], findings: findings, period: period)
        let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.findingID, $0) })
        #expect(byID["a"]?.status == .correctedVerified)
        #expect(byID["a"]?.impact.contains("raises reported profit") == true)
        #expect(byID["a"]?.impact.contains("No cash was recovered") == true)
        #expect(byID["b"]?.status == .awaitingVerification)
        #expect(byID["b"]?.impact.hasPrefix("Not yet confirmed") == true)
        #expect(byID["c"]?.status == .awaitingClient)
        #expect(byID["d"]?.status == .notAnError)
        #expect(byID["a"]?.affectedPeriodLabel == "July 2026")
    }

    @Test("Dismissing needs a reason; Other needs an explanation")
    func dismissReason() {
        #expect(DismissReason.note(reason: nil, detail: "x") == nil)
        #expect(DismissReason.note(reason: .other, detail: "  ") == nil)
        #expect(DismissReason.note(reason: .other, detail: "client paid personally") == "Other: client paid personally")
        #expect(DismissReason.note(reason: .immaterial, detail: "") == "Too small to be worth correcting")
    }

    @Test("Health check: overdrawn cash needs attention, unloaded receivables are insufficient, not zero")
    func health() {
        var input = MonthlyReportInputs(clientName: "A", period: period, today: AccountingDate(year: 2026, month: 9, day: 1), generatedAt: Date(), accountingBasis: "Accrual", environment: "sandbox",
                                        monthlyProfitAndLoss: [MonthlyReport(period: period, lines: [ReportLine(label: "Total Income", amount: usd(100_000), depth: 0, isSummary: true), ReportLine(label: "Net Income", amount: usd(-5_000), depth: 0, isSummary: true)])],
                                        balanceSheet: [ReportLine(label: "Total Bank Accounts", amount: usd(-1_000), depth: 1, isSummary: true)], cashFlow: [], agedReceivables: [], accountTypes: [:], findings: [], coverage: .complete)
        input.receivablesLoaded = false
        let report = MonthlyReportBuilder.build(input)
        let status = Dictionary(uniqueKeysWithValues: report.healthChecks.map { ($0.area, $0.statusKind) })
        #expect(status["Profitability"] == "attention")
        #expect(status["Cash & bills"] == "attention")
        #expect(status["Collections"] == "insufficient")
        #expect(report.priorities.first?.action == "Plan cash for upcoming bills and payroll")
        #expect(report.takeaways.first == "The business lost $50.00 in July.")
    }
}
