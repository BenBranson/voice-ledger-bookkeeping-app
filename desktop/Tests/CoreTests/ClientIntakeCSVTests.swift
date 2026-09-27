import Testing
@testable import Core
import Foundation

@Suite("ClientIntakeCSV")
struct ClientIntakeCSVTests {
    @Test("A fully-populated intake round-trips through fields(for:)/intake(from:) unchanged")
    func roundTripFullyPopulated() {
        let original = ClientIntake(
            id: "abc-123",
            savedAt: Date(timeIntervalSince1970: 1_700_000_000),
            legalBusinessName: "Permian Supply, LLC",
            entityType: "LLC",
            industry: "Oilfield services",
            primaryRevenueSources: "Equipment rental, parts sales",
            yearsInBusiness: "6 years",
            accountingSoftware: "QuickBooks Online",
            bankAccountCountAnswer: "2",
            creditCardCountAnswer: "1",
            monthlyTransactionCountAnswer: "~220",
            booksUpToDateAnswer: "About 4 months behind",
            whoManagesARAP: "Office manager handles both",
            paymentProcessors: "Square, Stripe",
            pointOfContactName: "Jamie Rivera",
            pointOfContactRole: "Office Manager",
            pointOfContactEmail: "jamie@example.com",
            pointOfContactPhone: "555-0100",
            communicationPreference: "Monthly video update",
            frustrations: "Never know where cash stands",
            desiredMetrics: "Cash runway, job profitability",
            financialsUse: "Bank line renewal",
            hourlyRateText: "125",
            volumeTier: .growth,
            monthlyFlags: .init(payrollProcessing: true, salesTaxManagement: false, multipleBankAccounts: true, inventoryTracking: false),
            needsCleanup: true,
            monthsBehind: .threeToSix,
            cleanupIssues: .init(multipleUncategorized: true, personalBusinessMixed: false, payrollNotReconciled: true, salesTaxNotFiled: false, inventoryTrackingIssues: false, negativeBalances: true, duplicatedAccounts: false),
            includeFindingsSummary: false
        )

        let fields = ClientIntakeCSV.fields(for: original)
        let restored = ClientIntakeCSV.intake(from: fields)

        #expect(restored?.id == original.id)
        #expect(restored?.legalBusinessName == original.legalBusinessName)
        #expect(restored?.entityType == original.entityType)
        #expect(restored?.accountingSoftware == original.accountingSoftware)
        #expect(restored?.pointOfContactEmail == original.pointOfContactEmail)
        #expect(restored?.pointOfContactPhone == original.pointOfContactPhone)
        #expect(restored?.volumeTier == original.volumeTier)
        #expect(restored?.monthsBehind == original.monthsBehind)
        #expect(restored?.monthlyFlags == original.monthlyFlags)
        #expect(restored?.needsCleanup == original.needsCleanup)
        #expect(restored?.cleanupIssues == original.cleanupIssues)
        #expect(restored?.includeFindingsSummary == original.includeFindingsSummary)
        // Same second precision as ISO8601 encodes, not exact `Date` equality.
        #expect(abs((restored?.savedAt.timeIntervalSince1970 ?? 0) - original.savedAt.timeIntervalSince1970) < 1)
    }

    @Test("Every declared column has a value in fields(for:) — export never silently drops a column")
    func everyColumnPresent() {
        let fields = ClientIntakeCSV.fields(for: ClientIntake())
        for column in ClientIntakeCSV.columns {
            #expect(fields[column] != nil, "Missing column: \(column)")
        }
    }

    @Test("A row missing columns (simulating a hand-edited file with a deleted column) falls back to defaults instead of failing the whole row")
    func missingColumnsFallBackToDefaults() {
        let sparse: [String: String] = ["id": "xyz", "legalBusinessName": "Test Co"]
        let restored = ClientIntakeCSV.intake(from: sparse)
        #expect(restored?.id == "xyz")
        #expect(restored?.legalBusinessName == "Test Co")
        #expect(restored?.entityType == "")
        #expect(restored?.volumeTier == .light)
        #expect(restored?.monthsBehind == .threeToSix)
        #expect(restored?.needsCleanup == false)
        #expect(restored?.includeFindingsSummary == true)
    }

    @Test("A row with no id at all is rejected rather than producing a phantom record")
    func missingIDRejected() {
        let restored = ClientIntakeCSV.intake(from: ["legalBusinessName": "No ID Co"])
        #expect(restored == nil)
    }

    @Test("Reordered columns (simulating a column dragged to a new position in Sheets) still parse correctly — lookup is by name, not position")
    func columnOrderIndependent() {
        // Deliberately NOT in `ClientIntakeCSV.columns` order.
        let fields: [String: String] = [
            "monthlyInvestment": "USD 800.00",
            "legalBusinessName": "Reordered Co",
            "id": "reorder-1",
            "volumeTier": "2",
            "needsCleanup": "true"
        ]
        let restored = ClientIntakeCSV.intake(from: fields)
        #expect(restored?.legalBusinessName == "Reordered Co")
        #expect(restored?.volumeTier == .high)
        #expect(restored?.needsCleanup == true)
    }
}
