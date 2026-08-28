import Testing
@testable import Core

@Suite("TaxEstimate.netIncome")
struct TaxEstimateNetIncomeTests {
    @Test("Finds the summary 'Net Income' line among other summary lines")
    func findsNetIncomeLine() {
        let lines = [
            ReportLine(label: "Total Income", amount: Money(minorUnits: 100_000, currency: .usd), depth: 0, isSummary: true),
            ReportLine(label: "Total Other Expenses", amount: Money(minorUnits: 426_476, currency: .usd), depth: 0, isSummary: true),
            ReportLine(label: "Net Other Income", amount: Money(minorUnits: -426_476, currency: .usd), depth: 0, isSummary: true),
            // Real shape confirmed live 2026-08-27: "Net Income" is a bare
            // Summary-only Section, group "NetIncome" — negative here
            // matches a real observed sandbox result (-3264.76).
            ReportLine(label: "Net Income", amount: Money(minorUnits: -326_476, currency: .usd), depth: 0, isSummary: true)
        ]
        #expect(TaxEstimate.netIncome(from: lines) == Money(minorUnits: -326_476, currency: .usd))
    }

    @Test("Returns nil when no Net Income line is present — never a guess")
    func returnsNilWhenAbsent() {
        let lines = [ReportLine(label: "Total Income", amount: Money(minorUnits: 100_000, currency: .usd), depth: 0, isSummary: true)]
        #expect(TaxEstimate.netIncome(from: lines) == nil)
    }

    @Test("Returns nil for an empty report — not yet loaded is not zero")
    func returnsNilForEmptyReport() {
        #expect(TaxEstimate.netIncome(from: []) == nil)
    }

    @Test("Ignores a non-summary line that happens to share the label")
    func ignoresNonSummaryLineWithSameLabel() {
        let lines = [ReportLine(label: "Net Income", amount: Money(minorUnits: 999, currency: .usd), depth: 0, isSummary: false)]
        #expect(TaxEstimate.netIncome(from: lines) == nil)
    }
}

@Suite("TaxEstimate.estimatedSetAside — pure arithmetic, zero tax law")
struct TaxEstimateSetAsideTests {
    @Test("Multiplies net income by the user-supplied rate")
    func multipliesByRate() {
        let netIncome = Money(minorUnits: 1_000_00, currency: .usd) // $1,000.00
        let result = TaxEstimate.estimatedSetAside(netIncome: netIncome, ratePercent: 25)
        #expect(result == Money(minorUnits: 250_00, currency: .usd)) // $250.00
    }

    @Test("A 0% rate produces $0.00, not nil — the user explicitly said zero")
    func zeroRateProducesZero() {
        let netIncome = Money(minorUnits: 1_000_00, currency: .usd)
        #expect(TaxEstimate.estimatedSetAside(netIncome: netIncome, ratePercent: 0) == Money(minorUnits: 0, currency: .usd))
    }

    @Test("nil rate produces nil — never a default/assumed rate")
    func nilRateProducesNil() {
        let netIncome = Money(minorUnits: 1_000_00, currency: .usd)
        #expect(TaxEstimate.estimatedSetAside(netIncome: netIncome, ratePercent: nil) == nil)
    }

    @Test("A negative rate produces nil, never a negative set-aside")
    func negativeRateProducesNil() {
        let netIncome = Money(minorUnits: 1_000_00, currency: .usd)
        #expect(TaxEstimate.estimatedSetAside(netIncome: netIncome, ratePercent: -5) == nil)
    }

    @Test("nil net income (report not loaded) produces nil regardless of rate")
    func nilNetIncomeProducesNil() {
        #expect(TaxEstimate.estimatedSetAside(netIncome: nil, ratePercent: 25) == nil)
    }

    @Test("A loss (net income <= 0) produces nil — no meaningful set-aside on a loss")
    func lossProducesNil() {
        let loss = Money(minorUnits: -326_476, currency: .usd)
        #expect(TaxEstimate.estimatedSetAside(netIncome: loss, ratePercent: 25) == nil)
        let zero = Money(minorUnits: 0, currency: .usd)
        #expect(TaxEstimate.estimatedSetAside(netIncome: zero, ratePercent: 25) == nil)
    }

    @Test("Rounds to the nearest cent rather than truncating")
    func roundsToNearestCent() {
        // $100.01 * 33% = $33.0033 -> rounds to $33.00
        let netIncome = Money(minorUnits: 100_01, currency: .usd)
        let result = TaxEstimate.estimatedSetAside(netIncome: netIncome, ratePercent: 33)
        #expect(result == Money(minorUnits: 33_00, currency: .usd))
    }
}
