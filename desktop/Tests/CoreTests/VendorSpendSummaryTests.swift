import Foundation
import Testing
@testable import Core

@Suite("VendorSpendSummary")
struct VendorSpendSummaryTests {
    func transaction(id: String, vendorName: String?, amountMinorUnits: Int64, isVoided: Bool = false) -> LedgerTransaction {
        LedgerTransaction(
            id: id,
            entityKind: .purchase,
            vendorName: vendorName,
            txnDate: AccountingDate(year: 2026, month: 7, day: 15),
            totalAmount: Money(minorUnits: amountMinorUnits, currency: .usd),
            paymentAccountID: "acct-1",
            docNumber: nil,
            isVoided: isVoided,
            memo: nil,
            provenance: .qboAPI(readAt: Date())
        )
    }

    @Test("Sums per vendor and sorts by total spend, descending")
    func sumsAndSorts() {
        let transactions = [
            transaction(id: "1", vendorName: "Acme Supply", amountMinorUnits: 10_000),
            transaction(id: "2", vendorName: "Acme Supply", amountMinorUnits: 5_000),
            transaction(id: "3", vendorName: "Zeta Vendor", amountMinorUnits: 50_000)
        ]
        let top = VendorSpendSummary.top(5, from: transactions)
        #expect(top.count == 2)
        #expect(top[0].vendorName == "Zeta Vendor")
        #expect(top[0].total == Money(minorUnits: 50_000, currency: .usd))
        #expect(top[1].vendorName == "Acme Supply")
        #expect(top[1].total == Money(minorUnits: 15_000, currency: .usd))
        #expect(top[1].transactionCount == 2)
    }

    @Test("Excludes voided transactions and transactions with no vendor name")
    func excludesVoidedAndUnnamed() {
        let transactions = [
            transaction(id: "1", vendorName: "Acme Supply", amountMinorUnits: 10_000, isVoided: true),
            transaction(id: "2", vendorName: nil, amountMinorUnits: 5_000),
            transaction(id: "3", vendorName: "Real Vendor", amountMinorUnits: 1_000)
        ]
        let top = VendorSpendSummary.top(5, from: transactions)
        #expect(top.count == 1)
        #expect(top[0].vendorName == "Real Vendor")
    }

    @Test("Caps at the requested count")
    func capsAtCount() {
        let transactions = (1...10).map { transaction(id: "\($0)", vendorName: "Vendor \($0)", amountMinorUnits: Int64($0) * 100) }
        #expect(VendorSpendSummary.top(3, from: transactions).count == 3)
    }

    @Test("Empty input produces an empty result, not a crash")
    func handlesEmptyInput() {
        #expect(VendorSpendSummary.top(5, from: []).isEmpty)
    }
}

@Suite("VendorSpendSummary counts vendors only")
struct VendorSpendVendorsOnlyTests {
    func txn(_ id: String, _ kind: QBOEntityKind, _ name: String, _ cents: Int64) -> LedgerTransaction {
        LedgerTransaction(id: id, entityKind: kind, vendorName: name, txnDate: AccountingDate(year: 2026, month: 7, day: 1),
                          totalAmount: Money(minorUnits: cents, currency: .usd), paymentAccountID: nil, docNumber: nil,
                          isVoided: false, memo: nil, provenance: .qboAPI(readAt: Date()))
    }

    @Test("Invoices (customer names) and bill payments are not vendor spend")
    func excludesCustomersAndPayments() {
        let rows = VendorSpendSummary.top(10, from: [
            txn("1", .purchase, "Gusto Payroll", 100_00),
            txn("2", .invoice, "Kate Whelan", 900_00),
            txn("3", .bill, "Norton Lumber", 50_00),
            txn("4", .billPayment, "Norton Lumber", 50_00),
            txn("5", .vendorCredit, "Norton Lumber", 10_00),
        ])
        #expect(rows.map(\.vendorName) == ["Gusto Payroll", "Norton Lumber"])
        #expect(rows.first { $0.vendorName == "Norton Lumber" }?.total.minorUnits == 40_00)
    }
}
