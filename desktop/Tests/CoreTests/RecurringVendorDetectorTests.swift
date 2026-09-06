import Foundation
import Testing
@testable import Core

@Suite("RecurringVendorDetector")
struct RecurringVendorDetectorTests {
    func purchase(vendorName: String?, day: (Int, Int, Int), amountMinorUnits: Int64, isVoided: Bool = false) -> LedgerTransaction {
        LedgerTransaction(
            id: UUID().uuidString,
            entityKind: .purchase,
            vendorName: vendorName,
            txnDate: AccountingDate(year: day.0, month: day.1, day: day.2),
            totalAmount: Money(minorUnits: amountMinorUnits, currency: .usd),
            paymentAccountID: "acct-1",
            docNumber: nil,
            isVoided: isVoided,
            memo: nil,
            provenance: .qboAPI(readAt: Date())
        )
    }

    @Test("Detects a vendor charged at a consistent monthly interval and amount")
    func detectsMonthlyRecurring() throws {
        let transactions = [
            purchase(vendorName: "Adobe", day: (2026, 4, 1), amountMinorUnits: 5_000),
            purchase(vendorName: "Adobe", day: (2026, 5, 1), amountMinorUnits: 5_000),
            purchase(vendorName: "Adobe", day: (2026, 6, 1), amountMinorUnits: 5_000),
            purchase(vendorName: "Adobe", day: (2026, 7, 2), amountMinorUnits: 5_000)
        ]
        let recurring = RecurringVendorDetector.detect(from: transactions)
        let vendor = try #require(recurring.first)
        #expect(recurring.count == 1)
        #expect(vendor.vendorName == "Adobe")
        #expect(vendor.occurrenceCount == 4)
        #expect(!vendor.lastAmountChanged)
    }

    @Test("Does not flag fewer than the minimum occurrences as recurring")
    func requiresMinimumOccurrences() {
        let transactions = [
            purchase(vendorName: "Adobe", day: (2026, 6, 1), amountMinorUnits: 5_000),
            purchase(vendorName: "Adobe", day: (2026, 7, 1), amountMinorUnits: 5_000)
        ]
        #expect(RecurringVendorDetector.detect(from: transactions).isEmpty)
    }

    @Test("Does not flag irregular one-off purchases from the same vendor as recurring")
    func rejectsIrregularIntervals() {
        let transactions = [
            purchase(vendorName: "Home Depot", day: (2026, 1, 3), amountMinorUnits: 4_500),
            purchase(vendorName: "Home Depot", day: (2026, 2, 20), amountMinorUnits: 12_000),
            purchase(vendorName: "Home Depot", day: (2026, 7, 9), amountMinorUnits: 800)
        ]
        #expect(RecurringVendorDetector.detect(from: transactions).isEmpty)
    }

    @Test("Excludes voided transactions")
    func excludesVoided() {
        let transactions = [
            purchase(vendorName: "Adobe", day: (2026, 4, 1), amountMinorUnits: 5_000),
            purchase(vendorName: "Adobe", day: (2026, 5, 1), amountMinorUnits: 5_000),
            purchase(vendorName: "Adobe", day: (2026, 6, 1), amountMinorUnits: 5_000, isVoided: true)
        ]
        #expect(RecurringVendorDetector.detect(from: transactions).isEmpty)
    }

    @Test("Flags the most recent charge as changed when it breaks the vendor's own amount pattern")
    func flagsAmountChange() throws {
        let transactions = [
            purchase(vendorName: "Adobe", day: (2026, 4, 1), amountMinorUnits: 5_000),
            purchase(vendorName: "Adobe", day: (2026, 5, 1), amountMinorUnits: 5_000),
            purchase(vendorName: "Adobe", day: (2026, 6, 1), amountMinorUnits: 5_000),
            purchase(vendorName: "Adobe", day: (2026, 7, 1), amountMinorUnits: 9_000)
        ]
        let recurring = RecurringVendorDetector.detect(from: transactions)
        let vendor = try #require(recurring.first)
        #expect(recurring.count == 1)
        #expect(vendor.lastAmountChanged)
        #expect(vendor.averageAmount == Money(minorUnits: 5_000, currency: .usd))
    }

    @Test("missingAsOf flags a recurring vendor whose next expected charge is overdue")
    func flagsMissingVendor() throws {
        let transactions = [
            purchase(vendorName: "Adobe", day: (2026, 1, 1), amountMinorUnits: 5_000),
            purchase(vendorName: "Adobe", day: (2026, 2, 1), amountMinorUnits: 5_000),
            purchase(vendorName: "Adobe", day: (2026, 3, 1), amountMinorUnits: 5_000)
        ]
        let recurring = RecurringVendorDetector.detect(from: transactions)
        let missing = RecurringVendorDetector.missingAsOf(recurring, asOf: AccountingDate(year: 2026, month: 6, day: 1))
        let vendor = try #require(missing.first)
        #expect(missing.count == 1)
        #expect(vendor.vendorName == "Adobe")
    }

    @Test("missingAsOf does not flag a vendor still within its grace window")
    func doesNotFlagWithinGrace() {
        let transactions = [
            purchase(vendorName: "Adobe", day: (2026, 1, 1), amountMinorUnits: 5_000),
            purchase(vendorName: "Adobe", day: (2026, 2, 1), amountMinorUnits: 5_000),
            purchase(vendorName: "Adobe", day: (2026, 3, 1), amountMinorUnits: 5_000)
        ]
        let recurring = RecurringVendorDetector.detect(from: transactions)
        let missing = RecurringVendorDetector.missingAsOf(recurring, asOf: AccountingDate(year: 2026, month: 4, day: 3))
        #expect(missing.isEmpty)
    }

    @Test("Empty input produces an empty result, not a crash")
    func handlesEmptyInput() {
        #expect(RecurringVendorDetector.detect(from: []).isEmpty)
    }
}
