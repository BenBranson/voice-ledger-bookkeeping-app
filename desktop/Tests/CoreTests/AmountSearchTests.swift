import Testing
@testable import Core
import Foundation

@Suite("AmountSearch")
struct AmountSearchTests {
    @Test("Parses a plain decimal amount")
    func parsesPlainDecimal() {
        #expect(AmountSearch.parseAmount("142.50") == Money(minorUnits: 14_250, currency: .usd))
    }

    @Test("Parses with a dollar sign and thousands separator")
    func parsesDollarSignAndComma() {
        #expect(AmountSearch.parseAmount("$1,242.50") == Money(minorUnits: 124_250, currency: .usd))
    }

    @Test("Parses a whole-dollar amount with no decimal point")
    func parsesWholeDollarAmount() {
        #expect(AmountSearch.parseAmount("142") == Money(minorUnits: 14_200, currency: .usd))
    }

    @Test("Parses a single-digit cents value by padding, matching how a bookkeeper reads it ($142.5 == $142.50)")
    func parsesSingleDigitCentsAsPadded() {
        #expect(AmountSearch.parseAmount("142.5") == Money(minorUnits: 14_250, currency: .usd))
    }

    @Test("Parses a negative amount")
    func parsesNegativeAmount() {
        #expect(AmountSearch.parseAmount("-45.00") == Money(minorUnits: -4_500, currency: .usd))
    }

    @Test("Rejects more than 2 digits after the decimal point rather than silently truncating or rounding")
    func rejectsThreeCentsDigits() {
        #expect(AmountSearch.parseAmount("142.500") == nil)
    }

    @Test("Rejects non-numeric input")
    func rejectsNonNumericInput() {
        #expect(AmountSearch.parseAmount("abc") == nil)
        #expect(AmountSearch.parseAmount("") == nil)
        #expect(AmountSearch.parseAmount("$") == nil)
    }

    func purchase(id: String, vendor: String?, amountMinorUnits: Int64, currency: CurrencyCode = .usd) -> LedgerTransaction {
        LedgerTransaction(
            id: id, entityKind: .purchase, vendorName: vendor,
            txnDate: AccountingDate(year: 2026, month: 7, day: 15),
            totalAmount: Money(minorUnits: amountMinorUnits, currency: currency),
            paymentAccountID: "checking-1", docNumber: nil, isVoided: false, memo: nil,
            provenance: .qboAPI(readAt: Date())
        )
    }

    @Test("findTransactions matches on absolute value — a positive search also finds a same-magnitude negative (credit/refund)")
    func findTransactionsMatchesAbsoluteValue() {
        let txns = [
            purchase(id: "1", vendor: "A", amountMinorUnits: 14_250),
            purchase(id: "2", vendor: "B", amountMinorUnits: -14_250),
            purchase(id: "3", vendor: "C", amountMinorUnits: 5_000)
        ]
        let matches = AmountSearch.findTransactions(matching: Money(minorUnits: 14_250, currency: .usd), in: txns)
        #expect(Set(matches.map(\.id)) == ["1", "2"])
    }

    @Test("findTransactions never matches across different currencies")
    func findTransactionsNeverMatchesAcrossCurrencies() {
        let txns = [purchase(id: "1", vendor: "A", amountMinorUnits: 14_250, currency: CurrencyCode(rawValue: "EUR"))]
        let matches = AmountSearch.findTransactions(matching: Money(minorUnits: 14_250, currency: .usd), in: txns)
        #expect(matches.isEmpty)
    }

    @Test("findTransactions returns an empty array, not a crash, when nothing matches")
    func findTransactionsReturnsEmptyWhenNoMatch() {
        let txns = [purchase(id: "1", vendor: "A", amountMinorUnits: 14_250)]
        let matches = AmountSearch.findTransactions(matching: Money(minorUnits: 999_99, currency: .usd), in: txns)
        #expect(matches.isEmpty)
    }
}

@Suite("Amount search input boundaries")
struct AmountSearchBoundaryTests {
    @Test func excessiveAmountsAreRejectedWithoutOverflow() {
        #expect(AmountSearch.parseAmount("92233720368547758.07")?.minorUnits == Int64.max)
        for text in ["92233720368547758.08", "92233720368547759", "9223372036854775807", "-9223372036854775807", ".", "$."] {
            #expect(AmountSearch.parseAmount(text) == nil)
        }
    }

    @Test func minimumSignedAmountDoesNotTrapWhenComparing() {
        let amount = Money(minorUnits: Int64.min, currency: .usd)
        #expect(AmountSearch.findTransactions(matching: amount, in: []).isEmpty)
        #expect(AmountSearch.accountsWithBalance(amount, in: []).isEmpty)
        #expect(AmountSearch.combination(matching: amount, in: []) == nil)
    }
}
