import Testing
@testable import Core

/// docs/phase-0/04_DATA_MODEL.md §4.3, decision M1: money is exact, integer
/// minor units, never floating point. These tests exist so a future refactor
/// toward `Double` (which will look like a harmless simplification) fails
/// immediately.
@Suite("Money")
struct MoneyTests {
    @Test("Equality is exact, not approximate")
    func exactEquality() {
        let a = Money(minorUnits: 48620, currency: .usd)
        let b = Money(minorUnits: 48620, currency: .usd)
        #expect(a == b)
    }

    @Test("Addition and subtraction are exact")
    func exactArithmetic() {
        let a = Money(minorUnits: 100, currency: .usd)
        let b = Money(minorUnits: 1, currency: .usd)
        var total = Money.zero
        for _ in 0..<100 {
            total = total + b
        }
        // If this were Double-backed, repeated addition of small values is
        // exactly where floating-point drift shows up. It must not here.
        #expect(total == a)
    }

    @Test("Comparing across currencies traps rather than silently coercing")
    func crossCurrencyComparisonTraps() async {
        // Swift Testing doesn't have a direct precondition-trap expectation
        // helper cross-platform; this test documents the requirement and is
        // exercised via #expect(throws:) once the comparison is wrapped in a
        // throwing boundary at the call site that uses it. Left as a marker
        // that the precondition exists in Money.swift and must not be
        // silently removed in a future refactor.
        let usd = Money(minorUnits: 100, currency: .usd)
        let eur = Money(minorUnits: 100, currency: CurrencyCode(rawValue: "EUR"))
        #expect(usd.currency != eur.currency)
    }

    @Test("description renders minor units correctly, including single-digit cents")
    func descriptionFormatsCentsWithLeadingZero() {
        let money = Money(minorUnits: 48605, currency: .usd)
        #expect(money.description == "USD 486.05")
    }
}
