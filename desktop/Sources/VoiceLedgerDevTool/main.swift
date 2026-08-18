import Foundation
import Core
import IntegrationsQuickBooks
import DB

// Verifies gate conditions against real data. Deliberately NOT the
// Connection Page or the real app (docs/VOICE_LEDGER_SPEC.md) — it's the
// smallest thing on the desktop that can prove a gate, text-only, no UI.
//
// Usage:
//   VOICE_LEDGER_BACKEND_URL=https://your-backend.example.com \
//   VOICE_LEDGER_SESSION_TOKEN=<token from /oauth/callback or mintDevSession.ts> \
//   VOICE_LEDGER_REALM_ID=<sandbox realmId> \
//   swift run voiceledger-devtool health
//   swift run voiceledger-devtool sync-check <year> <month>

let arguments = CommandLine.arguments
guard arguments.count >= 2, ["health", "sync-check"].contains(arguments[1]) else {
    print("""
    voiceledger-devtool — gate-verification CLI, not the app.

    Commands:
      health                 Run the live health check against a connected realm.
      sync-check <yr> <mo>   Sync + evaluate VL-DUP-EXP-001 against the live
                              sandbox for a period and print what was found.
                              Does not write to QBO. Persists findings/activity
                              log locally via ClientStore, same as the real app.

    Required environment variables:
      VOICE_LEDGER_BACKEND_URL     e.g. https://your-backend.onrender.com
      VOICE_LEDGER_SESSION_TOKEN   from the backend's /oauth/callback response
      VOICE_LEDGER_REALM_ID        the sandbox company's realmId
    """)
    exit(64) // EX_USAGE
}

guard let realmIDString = ProcessInfo.processInfo.environment["VOICE_LEDGER_REALM_ID"] else {
    FileHandle.standardError.write("VOICE_LEDGER_REALM_ID is not set.\n".data(using: .utf8)!)
    exit(2)
}
let realmID = RealmID(rawValue: realmIDString)

switch arguments[1] {
case "health":
    do {
        let configuration = try BackendConfiguration.fromEnvironment()
        let client = BackendClient(configuration: configuration)
        let result = try await client.healthCheck(realmID: realmID)

        print("realmId:    \(result.realmID)")
        print("status:     \(result.status.rawValue)")
        print("checkedAt:  \(result.checkedAt)")
        print("latencyMs:  \(result.latencyMs)")
        if let detail = result.detail {
            print("detail:     \(detail)")
        }

        switch result.status {
        case .green: exit(0)
        case .yellow, .gray: exit(1)
        case .red: exit(2)
        }
    } catch {
        FileHandle.standardError.write("Health check failed: \(error)\n".data(using: .utf8)!)
        exit(2)
    }

case "sync-check":
    guard arguments.count >= 4, let year = Int(arguments[2]), let month = Int(arguments[3]) else {
        FileHandle.standardError.write("Usage: sync-check <year> <month>\n".data(using: .utf8)!)
        exit(64)
    }
    do {
        let configuration = try BackendConfiguration.fromEnvironment()
        let backend = BackendClient(configuration: configuration)
        let syncClient = QBOSyncClient(backend: backend)
        let period = AccountingPeriod(year: year, month: month)

        let companyInfo = try await syncClient.fetchCompanyInfo(realmID: realmID)
        print("Company: \(companyInfo.companyName) (realmId \(companyInfo.realmID.rawValue))")

        let balanceSheetLines = try await syncClient.fetchBalanceSheet(realmID: realmID, period: period)
        print("Balance Sheet: \(balanceSheetLines.count) lines")
        for line in balanceSheetLines.prefix(8) {
            let indent = String(repeating: "  ", count: line.depth)
            print("  \(indent)\(line.label): \(line.amount?.description ?? "-")\(line.isSummary ? " [SUMMARY]" : "")")
        }

        let profitAndLossLines = try await syncClient.fetchProfitAndLoss(realmID: realmID, period: period)
        print("Profit & Loss: \(profitAndLossLines.count) lines")
        for line in profitAndLossLines.prefix(8) {
            let indent = String(repeating: "  ", count: line.depth)
            print("  \(indent)\(line.label): \(line.amount?.description ?? "-")\(line.isSummary ? " [SUMMARY]" : "")")
        }

        print("Syncing Purchase + Account + Preferences for \(realmID.rawValue), \(year)-\(month)...")
        let dataSet = try await syncClient.sync(realmID: realmID, period: period)
        print("  transactions read: \(dataSet.transactions.count)")
        print("  accounts read: \(dataSet.accounts.count)")
        print("  vendors read: \(dataSet.vendors.count)")
        print("  coverage: \(dataSet.coverage)")
        print("  customTxnNumbersForPurchases: \(dataSet.companyFacts.customTxnNumbersForPurchases)")
        for txn in dataSet.transactions.sorted(by: { $0.id < $1.id }) {
            print("    #\(txn.id) \(txn.vendorName ?? "?") \(txn.txnDate) \(txn.totalAmount) doc=\(txn.docNumber ?? "-") voided=\(txn.isVoided) acct=\(txn.paymentAccountID ?? "-") lineAccts=\(txn.lineAccountIDs)")
        }

        let engine = RuleEngine(rules: RuleRegistry.all)
        let context = RuleContext(period: period, materiality: .defaultPolicy, companyFacts: dataSet.companyFacts)
        let evaluation = await engine.evaluate(pages: [.page3Transactions, .cleanupAssessment, .bankFeedCleanup], input: dataSet, context: context)

        let tempStoreRoot = FileManager.default.temporaryDirectory.appending(path: "voiceledger-devtool-sync-check")
        let store = try ClientStore(realmID: realmID, rootDirectory: tempStoreRoot)

        for (ruleID, result) in evaluation.results {
            print("\nRule \(ruleID.rawValue):")
            switch result.outcome {
            case .pass(let coverage, let checked):
                print("  PASS — coverage=\(coverage), checked=\(checked)")
            case .cannotEvaluate(let reason):
                print("  CANNOT EVALUATE — \(reason)")
            case .findings(let findings):
                print("  \(findings.count) finding(s):")
                for f in findings {
                    print("    [\(f.id.prefix(12))...] \(f.title) — confidence=\(f.confidence.rawValue) severity=\(f.severity.rawValue) resolution=\(f.proposedActions.first?.resolution.rawValue ?? "-")")
                }
                try await store.upsertFindings(findings)
                try await store.reconcileAgainstLatestRun(currentRunFindingIDs: Set(findings.map(\.id)), ruleID: ruleID)
            }
        }
        print("\n(Findings persisted to \(tempStoreRoot.path) — temp store, not the real app's Application Support location.)")
        exit(0)
    } catch {
        FileHandle.standardError.write("sync-check failed: \(error)\n".data(using: .utf8)!)
        exit(2)
    }

default:
    exit(64)
}
