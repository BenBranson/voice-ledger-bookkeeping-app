import Testing
@testable import Core

@Suite("Spoken numbers and the number guard")
struct SpokenNumberAndGuardTests {
    func usd(_ c: Int64) -> Money { Money(minorUnits: c, currency: .usd) }

    @Test("Amounts as the recognizer hears them")
    func spoken() {
        #expect(SpokenNumber.amount(in: "find the $1,420 transaction") == usd(142_000))
        #expect(SpokenNumber.amount(in: "find 1420.00") == usd(142_000))
        #expect(SpokenNumber.amount(in: "find fourteen twenty") == usd(142_000))
        #expect(SpokenNumber.amount(in: "find one four two zero") == usd(142_000))
        #expect(SpokenNumber.amount(in: "twelve hundred dollars") == usd(120_000))
        #expect(SpokenNumber.amount(in: "three thousand two hundred ninety three dollars and two cents") == usd(329_302))
        #expect(SpokenNumber.amount(in: "five hundred") == usd(50_000))
        #expect(SpokenNumber.amount(in: "open the duplicates") == nil)
        #expect(SpokenNumber.amount(in: "show me 3 findings") == nil)
    }

    @Test("Guard keeps sentences whose numbers exist in the source and replaces the rest")
    func guardCheck() {
        let source = "VL Spike Sweeper Checking currently shows ($3,293.02).\nFor July 2026."
        let ok = NumberGuard.check("The balance is ($3,293.02), which is overdrawn.", source: source)
        #expect(ok.replacedSentences == 0)
        let bad = NumberGuard.check("The balance is $14,250.00. It is overdrawn.", source: source)
        #expect(bad.replacedSentences == 1)
        #expect(bad.text.contains("($3,293.02)") && !bad.text.contains("14,250"))
        #expect(NumberGuard.amounts(in: "-3,293.02 and $12 and 1420.00") == ["3,293.02", "$12", "1420.00"])
    }
}
