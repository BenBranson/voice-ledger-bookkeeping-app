import Testing
@testable import Core

@Suite("TranspositionHint")
struct TranspositionHintTests {
    @Test("$54 vs $45 ($9.00) and 540 vs 450 ($90.00) are flagged; $10.00 and zero are not")
    func divisibleByNine() {
        #expect(TranspositionHint.isConsistentWithTransposition(Money(minorUnits: 900, currency: .usd)))
        #expect(TranspositionHint.isConsistentWithTransposition(Money(minorUnits: -9_000, currency: .usd)))
        #expect(!TranspositionHint.isConsistentWithTransposition(Money(minorUnits: 1_000, currency: .usd)))
        #expect(!TranspositionHint.isConsistentWithTransposition(Money(minorUnits: 0, currency: .usd)))
    }

    @Test("The narrative is only extended when the hint applies")
    func appendsOnlyWhenApplicable() {
        #expect(TranspositionHint.appending(to: "Off.", difference: Money(minorUnits: 1_000, currency: .usd)) == "Off.")
        #expect(TranspositionHint.appending(to: "Off.", difference: Money(minorUnits: 900, currency: .usd)).contains("divisible by 9"))
    }
}
