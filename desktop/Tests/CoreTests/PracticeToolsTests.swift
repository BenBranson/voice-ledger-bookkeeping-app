import Testing
import Foundation
@testable import Core

@Suite("Compliance calendar")
struct ComplianceCalendarTests {
    let start = AccountingDate(year: 2026, month: 10, day: 2)

    @Test("Quarterly Texas sales tax, franchise PIR, 1099s and payroll land on the right dates")
    func deadlines() {
        let p = ClientPracticeProfile(state: "TX", entityType: .singleMemberLLC, salesTaxFrequency: .quarterly, files1099s: true, hasEmployees: true)
        let d = ComplianceCalendar.deadlines(for: p, from: start, days: 240)
        func date(_ key: String) -> [String] { d.filter { $0.key.hasPrefix(key) }.map(\.date.formatted) }
        #expect(date("sales-tax").contains("2026-10-20"))
        #expect(date("sales-tax").contains("2027-1-20"))
        #expect(date("annual-report") == ["2027-5-17"])      // Texas PIR; May 15, 2027 is a Saturday
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

@Suite("Compliance calendar by state")
struct StateComplianceTests {
    let start = AccountingDate(year: 2026, month: 10, day: 2)
    func keys(_ d: [ComplianceDeadline], _ k: String) -> [String] { d.filter { $0.key == k }.map(\.date.formatted) }

    @Test("California quarterly: last day of the month after the quarter; $800 LLC tax April 15; SOI in formation month every 2 years")
    func california() {
        let p = ClientPracticeProfile(state: "CA", entityType: .singleMemberLLC, formationMonth: 3, formationYear: 2023, salesTaxFrequency: .quarterly)
        let d = ComplianceCalendar.deadlines(for: p, from: start, days: 365)
        #expect(keys(d, "sales-tax").contains("2026-11-2"))     // Oct 31, 2026 is a Saturday
        #expect(keys(d, "ca-llc-tax") == ["2027-4-15"])
        #expect(keys(d, "annual-report") == ["2027-3-31"])       // formed 2023: 2025, 2027
        #expect(keys(d, "federal-return") == ["2027-4-15"])      // Schedule C
    }

    @Test("New York quarters run March–May; due the 20th after")
    func newYork() {
        let d = ComplianceCalendar.deadlines(for: ClientPracticeProfile(state: "NY", salesTaxFrequency: .quarterly), from: start, days: 200)
        #expect(keys(d, "sales-tax") == ["2026-12-21", "2027-3-22"])   // Dec 20, 2026 Sun; Mar 20, 2027 Sat
    }

    @Test("Florida corporation: annual report May 1; S corp return March 15")
    func florida() {
        let d = ComplianceCalendar.deadlines(for: ClientPracticeProfile(state: "FL", entityType: .sCorporation, salesTaxFrequency: .monthly), from: start, days: 240)
        #expect(keys(d, "annual-report") == ["2027-5-3"])         // May 1, 2027 is a Saturday
        #expect(keys(d, "federal-return") == ["2027-3-15"])
        #expect(keys(d, "sales-tax").first == "2026-10-20")
    }

    @Test("An unchecked state gets no state dates, only a check to verify")
    func unchecked() {
        let p = ClientPracticeProfile(state: "OK", salesTaxFrequency: .monthly, hasEmployees: true)
        #expect(ComplianceCalendar.deadlines(for: p, from: start, days: 120).allSatisfy { $0.key != "sales-tax" && $0.key != "annual-report" })
        let checks = ComplianceCalendar.checks(for: p).map(\.title)
        #expect(checks.contains("Oklahoma rules not checked yet"))
        #expect(checks.contains("Oklahoma payroll filings"))
    }

    @Test("Anniversary-based reports ask for the formation month")
    func needsFormationMonth() {
        let p = ClientPracticeProfile(state: "WA", entityType: .multiMemberLLC)
        #expect(ComplianceCalendar.checks(for: p).contains { $0.title == "Add the formation month" })
    }

    @Test("Profiles saved by v1.59 still load")
    func legacyDecode() throws {
        let json = #"{"salesTaxFrequency":"quarterly","texasEntity":false,"files1099s":true,"hasEmployees":false,"filesIFTA":false,"filesForm2290":false,"statementsDueDay":10,"reportBusinessDay":15,"industry":"hotShotTrucking","reviewed":true}"#
        let p = try JSONDecoder().decode(ClientPracticeProfile.self, from: Data(json.utf8))
        #expect(p.state == "TX" && p.entityType == .soleProprietor && p.salesTaxFrequency == .quarterly && p.industry == .hotShotTrucking && p.reviewed)
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

@Suite("Economic nexus screen")
struct EconomicNexusTests {
    func inv(_ id: String, _ state: String?, _ dollars: Int64, _ m: Int = 6) -> LedgerTransaction {
        LedgerTransaction(id: id, entityKind: .invoice, vendorName: "C", txnDate: AccountingDate(year: 2026, month: m, day: 1),
                          totalAmount: Money(minorUnits: dollars * 100, currency: .usd), paymentAccountID: nil, docNumber: nil, isVoided: false,
                          memo: nil, provenance: .qboAPI(readAt: Date()), customerState: state)
    }
    let asOf = AccountingDate(year: 2026, month: 10, day: 2)

    @Test("Over a checked threshold with no agency is flagged; home state and agency states are not")
    func flags() {
        let sales = [inv("1", "AZ", 120_000), inv("2", "CA", 600_000), inv("3", "TX", 900_000), inv("4", "FL", 50_000), inv("5", "NV", 85_000)]
        let rows = EconomicNexusScreen.rows(sales: sales, homeState: "TX", taxAgencyNames: ["California Department of Tax and Fee Administration"], asOf: asOf)
        func row(_ s: String) -> NexusStateRow { rows.first { $0.state == s }! }
        #expect(row("AZ").needsReview && row("AZ").overThreshold && !row("AZ").thresholdChecked)
        #expect(!row("CA").needsReview)            // agency set up
        #expect(!row("TX").needsReview)            // home state
        #expect(!row("FL").needsReview)            // under 80%
        #expect(row("NV").needsReview && row("NV").approaching)
    }

    @Test("New York needs both the dollars and more than 100 sales; old invoices are outside the window")
    func newYork() {
        let rows = EconomicNexusScreen.rows(sales: [inv("1", "NY", 700_000), inv("2", "NY", 5, 1)], homeState: "TX", taxAgencyNames: [], asOf: asOf)
        #expect(rows.first?.overThreshold == false)
        #expect(rows.first?.transactionCount == 2)
        let old = EconomicNexusScreen.rows(sales: [inv("9", "AZ", 200_000, 1)].map { _ in LedgerTransaction(id: "9", entityKind: .invoice, vendorName: nil, txnDate: AccountingDate(year: 2025, month: 8, day: 1), totalAmount: Money(minorUnits: 20_000_000, currency: .usd), paymentAccountID: nil, docNumber: nil, isVoided: false, memo: nil, provenance: .qboAPI(readAt: Date()), customerState: "AZ") }, homeState: "TX", taxAgencyNames: [], asOf: asOf)
        #expect(old.isEmpty)
    }
}

@Suite("Industry templates, all industries")
struct IndustryCatalogTests {
    @Test("Every industry has accounts, tracking advice and red flags; grocery is high complexity")
    func complete() {
        for kind in IndustryTemplate.Kind.allCases {
            #expect(!IndustryTemplate.accounts(for: kind).isEmpty, "\(kind) accounts")
            #expect(!IndustryTemplate.tracking(for: kind).isEmpty, "\(kind) tracking")
            #expect(!IndustryTemplate.redFlags(for: kind).isEmpty, "\(kind) red flags")
        }
        #expect(IndustryTemplate.Kind.groceryConvenience.complexity == .high)
        #expect(IndustryTemplate.Kind.groceryConvenience.usesInventory && IndustryTemplate.Kind.restaurant.usesInventory)
        #expect(!IndustryTemplate.Kind.professionalServices.usesInventory)
    }
}

@Suite("Hard-to-price intake flags")
struct ComplexityFlagTests {
    @Test("Flags add their price-list prices and warnings; both heavy inventory and cash-heavy adds the custom-engagement warning")
    func flags() {
        let f = PricingCalculator.MonthlyComplexityFlags(heavyInventory: true, cashHeavy: true)
        let base = PricingCalculator.monthlyQuote(tier: .light, hourlyRate: PriceBook.hourlyRate, flags: .init())
        let quote = PricingCalculator.monthlyQuote(tier: .light, hourlyRate: PriceBook.hourlyRate, flags: f)
        #expect(quote.monthlyInvestment == base.monthlyInvestment + Money(minorUnits: 700_00, currency: .usd))   // $500 heavy inventory + $200 cash-heavy
        #expect(f.warnings.count == 3)
    }

    @Test("Intakes saved before the new flags still load")
    func legacy() throws {
        let json = #"{"payrollProcessing":true,"salesTaxManagement":false,"multipleBankAccounts":false,"inventoryTracking":true}"#
        let f = try JSONDecoder().decode(PricingCalculator.MonthlyComplexityFlags.self, from: Data(json.utf8))
        #expect(f.payrollProcessing && f.inventoryTracking && !f.heavyInventory && !f.multipleEntities)
    }
}

@Suite("Inventory review")
struct InventoryReviewTests {
    func usd(_ d: Int64) -> Money { Money(minorUnits: d * 100, currency: .usd) }
    func month(_ m: Int, sales: Int64, cogs: Int64) -> MonthlyReport {
        MonthlyReport(period: AccountingPeriod(year: 2026, month: m), lines: [
            ReportLine(label: "Total Income", amount: usd(sales), depth: 0, isSummary: true),
            ReportLine(label: "Total Cost of Goods Sold", amount: usd(cogs), depth: 0, isSummary: true)])
    }

    @Test("Cost-of-goods share by month, shift flagged, books vs count")
    func review() {
        let r = InventoryReview.build(monthlyProfitAndLoss: [month(4, sales: 10_000, cogs: 3_000), month(5, sales: 10_000, cogs: 3_000), month(6, sales: 10_000, cogs: 4_000)],
                                      accounts: [LedgerAccount(id: "1", name: "Inventory Asset", accountType: .otherCurrentAsset, accountSubType: "Inventory", currentBalance: usd(5_000))],
                                      count: usd(4_200), countDate: AccountingDate(year: 2026, month: 6, day: 30))
        #expect(r.months.map(\.percent) == [30, 30, 40])
        #expect(r.ratioFlag)
        #expect(r.countDifference == usd(800))
        #expect(!r.negativeInventory && !r.noCostOfGoods)
    }
}
