import Testing
@testable import Core

@Suite("Money.accountingDescription")
struct MoneyAccountingFormatTests {
    @Test("Positive, negative, thousands separators, and zero")
    func formats() {
        #expect(Money(minorUnits: 126_376, currency: .usd).accountingDescription == "$1,263.76")
        #expect(Money(minorUnits: -306_376, currency: .usd).accountingDescription == "($3,063.76)")
        #expect(Money(minorUnits: 4_941_335, currency: .usd).accountingDescription == "$49,413.35")
        #expect(Money(minorUnits: -250_000_000, currency: .usd).accountingDescription == "($2,500,000.00)")
        #expect(Money(minorUnits: 5, currency: .usd).accountingDescription == "$0.05")
        #expect(Money.zero.accountingDescription == "$0.00")
    }

    @Test("The plain description is unchanged")
    func descriptionUnchanged() {
        #expect(Money(minorUnits: -126_376, currency: .usd).description == "-USD 1263.76")
    }
}
