import Testing
import Foundation
@testable import Core

@Suite("Compliance calendar")
struct ComplianceCalendarTests {
    let start = AccountingDate(year: 2026, month: 10, day: 2)

    @Test("Quarterly Texas sales tax, franchise PIR, 1099s and payroll land on the right dates")
    func deadlines() {
        let p = ClientPracticeProfile(salesTaxFrequency: .quarterly, texasEntity: true, files1099s: true, hasEmployees: true)
        let d = ComplianceCalendar.deadlines(for: p, from: start, days: 240)
        func date(_ key: String) -> [String] { d.filter { $0.key.hasPrefix(key) }.map(\.date.formatted) }
        #expect(date("sales-tax").contains("2026-10-20"))
        #expect(date("sales-tax").contains("2027-1-20"))
        #expect(date("franchise") == ["2027-5-17"])          // May 15, 2027 is a Saturday
        #expect(date("1099") == ["2027-2-1"])                // Jan 31, 2027 is a Sunday
        #expect(date("941").contains("2026-11-2"))           // Oct 31, 2026 is a Saturday
    }

    @Test("Monthly sales tax is the 20th of the next month; no sales tax adds nothing")
    func monthly() {
        let monthly = ComplianceCalendar.deadlines(for: ClientPracticeProfile(salesTaxFrequency: .monthly), from: start, days: 60)
        #expect(monthly.filter { $0.key == "sales-tax" }.map(\.date.formatted) == ["2026-10-20", "2026-11-20"])
        #expect(ComplianceCalendar.deadlines(for: ClientPracticeProfile(), from: start, days: 60).allSatisfy { $0.key != "sales-tax" })
    }

    @Test("Weekends and federal holidays move to the next business day")
    func businessDays() {
        #expect(ComplianceCalendar.nextBusinessDay(AccountingDate(year: 2026, month: 7, day: 4)).formatted == "2026-7-6")   // Sat, observed Fri 3rd
        #expect(ComplianceCalendar.nextBusinessDay(AccountingDate(year: 2026, month: 12, day: 25)).formatted == "2026-12-28")
        #expect(ComplianceCalendar.businessDay(15, year: 2026, month: 11).formatted == "2026-11-23")   // Veterans Day skipped
    }
}

@Suite("13-week cash flow forecast")
struct ThirteenWeekForecastTests {
    func usd(_ c: Int64) -> Money { Money(minorUnits: c, currency: .usd) }
    func aging(current: Int64 = 0, d30: Int64 = 0, d90: Int64 = 0, d91: Int64 = 0) -> [AgingLine] {
        [AgingLine(label: "X", current: usd(current), days1to30: usd(d30), days31to60: usd(0), days61to90: usd(d90), days91AndOver: usd(d91), total: usd(current + d30 + d90 + d91), depth: 0, isSummary: false)]
    }

    @Test("Totals tie out: starting cash plus everything in minus everything out")
    func tiesOut() {
        let f = ThirteenWeekForecastEngine.compute(currentCash: usd(1_000_00), agedReceivablesLines: aging(current: 400_00, d30: 400_00, d90: 500_00, d91: 999_00),
                                                   agedPayablesLines: aging(current: 200_00), recurringVendors: [],
                                                   planned: [PlannedCashItem(week: 4, description: "Trailer", amount: usd(-2_000_00))], asOf: AccountingDate(year: 2026, month: 10, day: 2))
        #expect(f.weeks.count == 13)
        #expect(f.weeks.last?.endingCash == usd(1_000_00 + 1_300_00 - 200_00 - 2_000_00))   // over-90 never counted
        #expect(f.weeks[0].collections == usd(100_00))
        #expect(f.firstNegativeWeek?.number == 4)
        #expect(f.atRiskReceivables == usd(999_00))
    }
}

@Suite("Industry templates")
struct IndustryTemplateTests {
    @Test("Trucking: present accounts are matched by name within the same family")
    func compare() {
        let accounts = [LedgerAccount(id: "1", name: "Fuel", accountType: .expense), LedgerAccount(id: "2", name: "Factoring Fees", accountType: .expense),
                        LedgerAccount(id: "3", name: "Interest Earned", accountType: .income)]
        let c = IndustryTemplate.compare(.hotShotTrucking, accounts: accounts)
        #expect(c.present.map(\.0.name).contains("Fuel"))
        #expect(c.present.map(\.0.name).contains("Factoring Fees"))
        #expect(c.missing.map(\.name).contains("Freight Revenue"))
    }
}

@Suite("Scope requests")
struct ScopeRequestTests {
    @Test("Presets become requests; totals count approved monthly and unbilled one-time work")
    func totals() {
        let payroll = ScopePreset.defaults.first { $0.id == "payroll" }!
        let hourly = ScopePreset.defaults.first { $0.id == "hourly" }!
        var a = ScopeRequest(preset: payroll); a.status = .approved
        var b = ScopeRequest(preset: hourly, quantity: 3); b.status = .approved
        let c = ScopeRequest(preset: payroll)
        let t = ScopeLog.totals([a, b, c])
        #expect(t.monthlyAddOns == Money(minorUnits: 400_00, currency: .usd))
        #expect(t.unbilledOneTime == Money(minorUnits: 450_00, currency: .usd))
        #expect(t.awaitingApproval == 1)
    }

    @Test("The client reply states scope, price and approval")
    func reply() {
        let r = ScopeRequest(preset: ScopePreset.defaults.first { $0.id == "payroll" }!)
        let text = ScopeLog.clientReply(for: r, clientName: "Sam")
        #expect(text.contains("Hi Sam,") && text.contains("$400.00 a month") && text.contains("outside that scope") && text.contains("approve"))
    }
}

@Suite("New account alert")
struct NewAccountWatchTests {
    let a1 = LedgerAccount(id: "1", name: "Checking", accountType: .bank)
    let a2 = LedgerAccount(id: "2", name: "New Amex", accountType: .creditCard)
    let exp = LedgerAccount(id: "9", name: "Fuel", accountType: .expense)

    @Test("First sync seeds silently; a later new card is reported once")
    func watch() {
        let first = NewAccountWatch.check(baseline: KnownAccountsBaseline(), accounts: [a1, exp])
        #expect(first.newAlerts.isEmpty && first.baseline.accountIDs == ["1"])
        let second = NewAccountWatch.check(baseline: first.baseline, accounts: [a1, a2, exp])
        #expect(second.newAlerts.map(\.name) == ["New Amex"])
        let third = NewAccountWatch.check(baseline: second.baseline, accounts: [a1, a2, exp])
        #expect(third.newAlerts.isEmpty)
    }
}
