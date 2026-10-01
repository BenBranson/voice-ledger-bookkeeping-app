import Testing
import Core
@testable import IntegrationsQuickBooks

struct SyncCoverageTests {
    @Test func everyInputMustBeComplete() {
        for name in ["purchases", "bills", "invoices", "payments", "accounts", "vendors", "deposits", "vendor credits"] {
            #expect(QBOSyncClient.syncCoverage(pageCounts: [name: 999]) == .complete)
            if case .partial = QBOSyncClient.syncCoverage(pageCounts: [name: 1000]) {} else {
                Issue.record("Full \(name) page must not produce complete coverage")
            }
        }
    }
}
