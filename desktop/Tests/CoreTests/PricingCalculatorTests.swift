import Testing
@testable import Core

@Suite("PricingCalculator")
struct PricingCalculatorTests {
    func rate(_ dollars: Int64) -> Money {
        Money(minorUnits: dollars * 100, currency: .usd)
    }

    // MARK: monthlyQuote

    @Test("Base tier with no add-ons: hours and investment match the plain base-hours × rate math")
    func monthlyQuoteNoAddOns() {
        let quote = PricingCalculator.monthlyQuote(tier: .light, hourlyRate: rate(100), flags: .init())
        #expect(quote.baseHours == 3.0)
        #expect(quote.addOnHours == 0.0)
        #expect(quote.totalHours == 3.0)
        // 3 hrs * $100 = $300, already a multiple of $50.
        #expect(quote.monthlyInvestment == rate(300))
    }

    @Test("All complexity add-ons stack correctly")
    func monthlyQuoteAllAddOns() {
        let flags = PricingCalculator.MonthlyComplexityFlags(payrollProcessing: true, salesTaxManagement: true, multipleBankAccounts: true, inventoryTracking: true)
        let quote = PricingCalculator.monthlyQuote(tier: .growth, hourlyRate: rate(100), flags: flags)
        // 5.5 base + 1.5 + 1.0 + 1.0 + 2.0 = 11.0 hours
        #expect(quote.totalHours == 11.0)
        // 11 * $100 = $1100, already a multiple of $50.
        #expect(quote.monthlyInvestment == rate(1_100))
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

    @Test("A clean, recent, low-volume, no-issues cleanup produces the $400 floor, not a smaller number")
    func cleanupQuoteRespectsFloor() {
        let quote = PricingCalculator.cleanupQuote(monthsBehind: .oneToThree, volumeTier: .light, hourlyRate: rate(10), issues: .init())
        // Deliberately tiny rate so the raw midpoint*0.8 would fall under $400.
        #expect(quote.low == Money(minorUnits: 40_000, currency: .usd))
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
