import Testing
@testable import Core

@Suite("VarianceAnalysis")
struct VarianceAnalysisTests {
    func line(_ label: String, _ amountMinorUnits: Int64?, depth: Int = 0, isSummary: Bool = false) -> ReportLine {
        ReportLine(label: label, amount: amountMinorUnits.map { Money(minorUnits: $0, currency: .usd) }, depth: depth, isSummary: isSummary)
    }

    @Test("An increase computes a positive change and percent")
    func increaseComputesPositiveChange() {
        let result = VarianceAnalysis.compute(current: [line("Rent", 120_000)], prior: [line("Rent", 100_000)])
        #expect(result.count == 1)
        #expect(result[0].change == Money(minorUnits: 20_000, currency: .usd))
        #expect(result[0].percentChange == 0.2)
    }

    @Test("A decrease computes a negative change and percent")
    func decreaseComputesNegativeChange() {
        let result = VarianceAnalysis.compute(current: [line("Rent", 80_000)], prior: [line("Rent", 100_000)])
        #expect(result[0].change == Money(minorUnits: -20_000, currency: .usd))
        #expect(result[0].percentChange == -0.2)
    }

    @Test("A line present only in the current period has a nil prior amount, nil change, nil percent — never fabricated as zero")
    func newLineHasNilPriorAndChange() {
        let result = VarianceAnalysis.compute(current: [line("New Vendor", 5_000)], prior: [])
        #expect(result[0].currentAmount != nil)
        #expect(result[0].priorAmount == nil)
        #expect(result[0].change == nil)
        #expect(result[0].percentChange == nil)
    }

    @Test("A line present only in the prior period is appended, with a nil current amount and nil change")
    func priorOnlyLineIsAppended() {
        let result = VarianceAnalysis.compute(current: [line("Rent", 100_000)], prior: [line("Rent", 100_000), line("Old Vendor", 3_000)])
        #expect(result.count == 2)
        #expect(result[1].label == "Old Vendor")
        #expect(result[1].currentAmount == nil)
        #expect(result[1].priorAmount != nil)
        #expect(result[1].change == nil)
    }

    @Test("A zero prior amount produces a nil percentChange — dividing by zero has no honest percentage")
    func zeroPriorAmountProducesNilPercent() {
        let result = VarianceAnalysis.compute(current: [line("Rent", 5_000)], prior: [line("Rent", 0)])
        #expect(result[0].change == Money(minorUnits: 5_000, currency: .usd))
        #expect(result[0].percentChange == nil)
    }

    @Test("A nil amount on either side produces a nil change, not a change computed against zero")
    func nilAmountProducesNilChange() {
        let result = VarianceAnalysis.compute(current: [line("Rent", nil)], prior: [line("Rent", 100_000)])
        #expect(result[0].change == nil)
        #expect(result[0].percentChange == nil)
    }

    @Test("Result preserves current's line order and depth/isSummary")
    func resultPreservesCurrentOrderAndShape() {
        let result = VarianceAnalysis.compute(
            current: [line("Total Assets", 500_000, depth: 0, isSummary: true), line("Checking", 200_000, depth: 1)],
            prior: [line("Checking", 150_000, depth: 1), line("Total Assets", 400_000, depth: 0, isSummary: true)]
        )
        #expect(result[0].label == "Total Assets")
        #expect(result[0].isSummary == true)
        #expect(result[1].label == "Checking")
        #expect(result[1].depth == 1)
    }

    @Test("Duplicate labels on both sides match by first-occurrence order, not cross-matched arbitrarily")
    func duplicateLabelsMatchByOrder() {
        let result = VarianceAnalysis.compute(
            current: [line("Other", 1_000), line("Other", 2_000)],
            prior: [line("Other", 900), line("Other", 1_800)]
        )
        #expect(result[0].priorAmount == Money(minorUnits: 900, currency: .usd))
        #expect(result[1].priorAmount == Money(minorUnits: 1_800, currency: .usd))
    }
}
