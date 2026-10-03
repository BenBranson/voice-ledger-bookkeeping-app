import Foundation
import Testing
@testable import Core

@Suite("PricingCalculator")
struct PricingCalculatorTests {
    func rate(_ dollars: Int64) -> Money {
        Money(minorUnits: dollars * 100, currency: .usd)
    }

    // MARK: monthlyQuote

    @Test("Base tier with no add-ons: base hours × rate, rounded to $50 (3 × $125 = $375 → $400)")
    func monthlyQuoteNoAddOns() {
        let quote = PricingCalculator.monthlyQuote(tier: .light, hourlyRate: rate(125), flags: .init())
        #expect(quote.baseHours == 3.0)
        #expect(quote.baseAmount == rate(400))
        #expect(quote.addOns.isEmpty)
        #expect(quote.monthlyInvestment == rate(400))
    }

    @Test("Add-ons stack at their price-list prices, not hours")
    func monthlyQuoteAllAddOns() {
        let flags = PricingCalculator.MonthlyComplexityFlags(payrollProcessing: true, salesTaxManagement: true, multipleBankAccounts: true, inventoryTracking: true)
        let quote = PricingCalculator.monthlyQuote(tier: .growth, hourlyRate: rate(125), flags: flags)
        // $700 Growth + $200 payroll bookkeeping + $150 sales tax + $50 extra account + $250 inventory
        #expect(quote.addOnTotal == rate(650))
        #expect(quote.monthlyInvestment == rate(1_350))
    }

    @Test("Monthly investment rounds to the nearest $50, not truncated or floored")
    func monthlyQuoteRoundsToNearest50() {
        // 3 hrs * $110/hr = $330 -> nearest $50 is $350, not $300.
        let quote = PricingCalculator.monthlyQuote(tier: .light, hourlyRate: rate(110), flags: .init())
        #expect(quote.monthlyInvestment == rate(350))
    }

    @Test("Higher volume tier alone increases the base hours and therefore the price")
    func monthlyQuoteHigherVolumeIsMoreExpensive() {
        let light = PricingCalculator.monthlyQuote(tier: .light, hourlyRate: rate(100), flags: .init())
        let high = PricingCalculator.monthlyQuote(tier: .high, hourlyRate: rate(100), flags: .init())
        #expect(high.monthlyInvestment > light.monthlyInvestment)
    }

    // MARK: cleanupQuote

    @Test("A clean, recent, low-volume, no-issues cleanup produces the price list's $500 floor, not a smaller number")
    func cleanupQuoteRespectsFloor() {
        let quote = PricingCalculator.cleanupQuote(monthsBehind: .oneToThree, volumeTier: .light, hourlyRate: rate(10), issues: .init())
        // Deliberately tiny rate so the raw midpoint*0.8 would fall under the floor.
        #expect(quote.low == PriceBook.cleanupFloor)
        #expect(quote.low == rate(500))
    }

    @Test("More months behind increases the midpoint, holding everything else constant")
    func cleanupQuoteScalesWithMonthsBehind() {
        let recent = PricingCalculator.cleanupQuote(monthsBehind: .oneToThree, volumeTier: .growth, hourlyRate: rate(100), issues: .init())
        let veryBehind = PricingCalculator.cleanupQuote(monthsBehind: .twelvePlus, volumeTier: .growth, hourlyRate: rate(100), issues: .init())
        #expect(veryBehind.midpoint > recent.midpoint)
    }

    @Test("More active issue flags increases the midpoint, holding months/volume/rate constant")
    func cleanupQuoteScalesWithIssueCount() {
        let noIssues = PricingCalculator.cleanupQuote(monthsBehind: .threeToSix, volumeTier: .growth, hourlyRate: rate(100), issues: .init())
        let manyIssues = PricingCalculator.cleanupQuote(
            monthsBehind: .threeToSix, volumeTier: .growth, hourlyRate: rate(100),
            issues: .init(multipleUncategorized: true, personalBusinessMixed: true, payrollNotReconciled: true, negativeBalances: true)
        )
        #expect(manyIssues.midpoint > noIssues.midpoint)
        #expect(manyIssues.issueCount == 4)
    }

    @Test("high is always greater than low, and midpoint sits between them")
    func cleanupQuoteRangeIsOrdered() {
        let quote = PricingCalculator.cleanupQuote(monthsBehind: .sixToTwelve, volumeTier: .high, hourlyRate: rate(125), issues: .init(negativeBalances: true, duplicatedAccounts: true))
        #expect(quote.low < quote.midpoint)
        #expect(quote.midpoint < quote.high)
    }

    // MARK: CombinedProposal

    @Test("dayOneTotal with a cleanup phase equals cleanup midpoint plus the first month's retainer")
    func combinedProposalDayOneTotalWithCleanup() {
        let monthly = PricingCalculator.monthlyQuote(tier: .light, hourlyRate: rate(100), flags: .init())
        let cleanup = PricingCalculator.cleanupQuote(monthsBehind: .oneToThree, volumeTier: .light, hourlyRate: rate(100), issues: .init())
        let proposal = PricingCalculator.CombinedProposal(cleanup: cleanup, monthly: monthly)
        #expect(proposal.dayOneTotal == cleanup.midpoint + monthly.monthlyInvestment)
    }

    @Test("dayOneTotal with no cleanup phase equals just the first month's retainer")
    func combinedProposalDayOneTotalWithoutCleanup() {
        let monthly = PricingCalculator.monthlyQuote(tier: .light, hourlyRate: rate(100), flags: .init())
        let proposal = PricingCalculator.CombinedProposal(cleanup: nil, monthly: monthly)
        #expect(proposal.dayOneTotal == monthly.monthlyInvestment)
    }
}

@Suite("Price book: one list for calculator, presets, agreement and website")
struct PriceBookTests {
    func usd(_ d: Int64) -> Money { Money(minorUnits: d * 100, currency: .usd) }

    @Test("Owner-approved 2026-10-03: tiers are $400 / $700 / $1,000 at the standard $125/hr")
    func tiers() {
        #expect(PriceBook.hourlyRate == usd(125))
        #expect(PricingCalculator.monthlyQuote(tier: .light, hourlyRate: PriceBook.hourlyRate, flags: .init()).monthlyInvestment == usd(400))
        #expect(PricingCalculator.monthlyQuote(tier: .growth, hourlyRate: PriceBook.hourlyRate, flags: .init()).monthlyInvestment == usd(700))
        #expect(PricingCalculator.monthlyQuote(tier: .high, hourlyRate: PriceBook.hourlyRate, flags: .init()).monthlyInvestment == usd(1_000))
        #expect(PriceBook.outOfScopeHourly == usd(150))
        #expect(PriceBook.foundingStarter == usd(300) && PriceBook.foundingMonths == 12)
    }

    @Test("The price buttons ARE the price book, and every calculator add-on is a published item")
    func oneList() {
        #expect(ScopePreset.defaults == PriceBook.items)
        let all = PricingCalculator.MonthlyComplexityFlags(payrollProcessing: true, salesTaxManagement: true, inventoryTracking: true, heavyInventory: true,
                                                           multiStateSales: true, cashHeavy: true, multipleEntities: true, advisory: true, extraAccounts: 1)
        for item in all.addOns { #expect(PriceBook.items.contains(item)) }
        #expect(Set(PriceBook.items.map(\.id)).count == PriceBook.items.count)
    }

    @Test("Extra accounts are priced per account; an old saved yes/no reads as one")
    func extraAccounts() throws {
        let three = PricingCalculator.MonthlyComplexityFlags(extraAccounts: 3)
        #expect(PricingCalculator.monthlyQuote(tier: .light, hourlyRate: usd(125), flags: three).addOnTotal == usd(150))
        let legacy = try JSONDecoder().decode(PricingCalculator.MonthlyComplexityFlags.self, from: Data(#"{"payrollProcessing":false,"salesTaxManagement":false,"multipleBankAccounts":true,"inventoryTracking":false}"#.utf8))
        #expect(legacy.extraAccounts == 1)
        let round = try JSONDecoder().decode(PricingCalculator.MonthlyComplexityFlags.self, from: JSONEncoder().encode(three))
        #expect(round.extraAccounts == 3)
    }

    @Test("Screen labels read their prices from the book")
    func labels() {
        #expect(PriceBook.addOnPrice("payroll-bookkeeping") == "+$200/mo")
        #expect(PriceBook.addOnPrice("1099") == "+$50 per form")
    }
}
