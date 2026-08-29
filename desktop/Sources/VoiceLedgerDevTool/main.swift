import Foundation
import Core
import IntegrationsQuickBooks
import IntegrationsImports
import DB
import Exporting

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
guard arguments.count >= 2, ["health", "tax-check", "connections-check", "ask-ai-check", "sync-check", "csv-import-check", "export-sample", "xlsx-import-check", "ocr-import-check"].contains(arguments[1]) else {
    print("""
    voiceledger-devtool — gate-verification CLI, not the app.

    Commands:
      health                 Run the live health check against a connected realm.
      tax-check              Fetch TaxCode/TaxRate/TaxAgency live and print
                              them (docs/VOICE_LEDGER_SPEC.md Page 9). Read-only.
      connections-check      Fetch the backend's connection registry live
                              (docs/VOICE_LEDGER_SPEC.md's Firm Cockpit). Read-only.
      ask-ai-check           Checks AI status, then asks a real OpenAI
                              question through the real BackendClient.askAI
                              code path. Costs a small amount of real API
                              usage.
      sync-check <yr> <mo>   Sync + evaluate all rules against the live
                              sandbox for a period and print what was found.
                              Does not write to QBO. Persists findings/activity
                              log locally via ClientStore, same as the real app.
      csv-import-check <csvPath> <statementAccountID> <yr> <mo>
                              Runs the REAL CSVParser -> BankStatementCSVImporter
                              -> ClientStore -> RuleEngine pipeline against a
                              real CSV file for a period (same code path
                              AppState.confirmCSVImport uses), then prints
                              VL-RECON-MISSING-001 and VL-VENDOR-MISMATCH-001
                              results. Does not write to QBO.
      export-sample <outputDir>
                              Writes sample.csv / sample.xlsx / sample.pdf to
                              outputDir using CSVReportExporter/
                              XLSXReportExporter/PDFReportExporter against a
                              small synthetic ExportTable. No network, no
                              realm needed — verifies the exporters produce
                              real, openable files.
      xlsx-import-check <xlsxPath>
                              Runs XLSXParser.parse against a real .xlsx file
                              on disk and prints every parsed row. No network,
                              no realm needed — verifies the ZIP/DEFLATE
                              reader and OOXML parsing against a real file,
                              not just this project's own writer's output.
      ocr-import-check <pdfOrImagePath>
                              Runs VisionDocumentOCR against a real PDF or
                              image file on disk and prints every extracted
                              table row (docs/VOICE_LEDGER_SPEC.md's
                              Universal Ingestion Tier 2). No network, no
                              realm needed, macOS 26+ only.

    Required environment variables (not needed for export-sample):
      VOICE_LEDGER_BACKEND_URL     e.g. https://your-backend.onrender.com
      VOICE_LEDGER_SESSION_TOKEN   from the backend's /oauth/callback response
      VOICE_LEDGER_REALM_ID        the sandbox company's realmId
    """)
    exit(64) // EX_USAGE
}

if arguments[1] == "export-sample" {
    guard arguments.count >= 3 else {
        FileHandle.standardError.write("Usage: export-sample <outputDir>\n".data(using: .utf8)!)
        exit(64)
    }
    let outputDir = URL(fileURLWithPath: arguments[2])
    try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

    let table = ExportTable(
        title: "Sample Balance Sheet",
        columns: ["Label", "Amount"],
        rows: [
            [ExportCell(text: "Checking"), ExportCell.money(Money(minorUnits: 1_234_567, currency: .usd))],
            [ExportCell(text: "Accounts Payable, Net"), ExportCell.money(Money(minorUnits: -50_000, currency: .usd))],
            [ExportCell(text: "Total Assets (Total)"), ExportCell.money(Money(minorUnits: 1_184_567, currency: .usd))]
        ]
    )

    try? CSVReportExporter.export(table).write(to: outputDir.appendingPathComponent("sample.csv"))
    try? XLSXReportExporter.export(table).write(to: outputDir.appendingPathComponent("sample.xlsx"))
    try? PDFReportExporter.export(table).write(to: outputDir.appendingPathComponent("sample.pdf"))
    print("Wrote sample.csv, sample.xlsx, sample.pdf to \(outputDir.path)")
    exit(0)
}

if arguments[1] == "ocr-import-check" {
    guard arguments.count >= 3 else {
        FileHandle.standardError.write("Usage: ocr-import-check <pdfOrImagePath>\n".data(using: .utf8)!)
        exit(64)
    }
    guard #available(macOS 26.0, *) else {
        FileHandle.standardError.write("ocr-import-check needs macOS 26 or later.\n".data(using: .utf8)!)
        exit(2)
    }
    let path = arguments[2]
    let url = URL(fileURLWithPath: path)
    let ext = url.pathExtension.lowercased()
    do {
        let rows = ext == "pdf" ? try await VisionDocumentOCR.extractRows(fromPDFAt: url) : try await VisionDocumentOCR.extractRows(fromImageFileAt: url)
        print("Extracted \(rows.count) rows:")
        for row in rows {
            print("  \(row)")
        }
        exit(0)
    } catch {
        FileHandle.standardError.write("ocr-import-check failed: \(error)\n".data(using: .utf8)!)
        exit(2)
    }
}

if arguments[1] == "xlsx-import-check" {
    guard arguments.count >= 3 else {
        FileHandle.standardError.write("Usage: xlsx-import-check <xlsxPath>\n".data(using: .utf8)!)
        exit(64)
    }
    do {
        let data = try Data(contentsOf: URL(fileURLWithPath: arguments[2]))
        let rows = try XLSXParser.parse(data)
        print("Parsed \(rows.count) rows:")
        for row in rows {
            print("  \(row)")
        }
        exit(0)
    } catch {
        FileHandle.standardError.write("xlsx-import-check failed: \(error)\n".data(using: .utf8)!)
        exit(2)
    }
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

case "connections-check":
    // docs/VOICE_LEDGER_SPEC.md's Firm Cockpit — live-verifies
    // BackendClient.getConnections against the real backend/database.
    do {
        let configuration = try BackendConfiguration.fromEnvironment()
        let client = BackendClient(configuration: configuration)
        let connections = try await client.getConnections()
        print("Connections (\(connections.count)):")
        for c in connections {
            print("  \(c.realmID.rawValue): \(c.companyName ?? "(no name)"), env=\(c.environment.rawValue), writeEnabled=\(c.writeEnabled), health=\(c.lastHealthCheckStatus.map { $0.rawValue } ?? "never checked")")
        }
        exit(0)
    } catch {
        FileHandle.standardError.write("connections-check failed: \(error)\n".data(using: .utf8)!)
        exit(2)
    }

case "ask-ai-check":
    // docs/VOICE_LEDGER_SPEC.md's Ask [AI] panel — live-verifies the
    // actual BackendClient.askAI Swift code path (not just the raw HTTP
    // route) against a real connected realm and a real OpenAI key.
    do {
        let configuration = try BackendConfiguration.fromEnvironment()
        let client = BackendClient(configuration: configuration)

        let status = try await client.getAIStatus()
        print("AI status: configured=\(status.configured) enabled=\(status.enabled)")
        guard status.configured, status.enabled else {
            print("Skipping ask-ai call — not configured and enabled.")
            exit(status.configured ? 1 : 0)
        }

        let answer = try await client.askAI(
            realmID: realmID,
            question: "Why does this matter?",
            context: "Finding: Possible duplicate expense. Vendor: Test Vendor. Amount: USD 100.00. Severity: high. Confidence: high."
        )
        print("Answer: \(answer)")
        exit(0)
    } catch {
        FileHandle.standardError.write("ask-ai-check failed: \(error)\n".data(using: .utf8)!)
        exit(2)
    }

case "tax-check":
    // docs/VOICE_LEDGER_SPEC.md Page 9 (Sales Tax Review) — live-verifies
    // the three new read operations against a real connected realm, same
    // "gate-verification, not the app" purpose as `health`/`sync-check`.
    do {
        let configuration = try BackendConfiguration.fromEnvironment()
        let client = BackendClient(configuration: configuration)
        let syncClient = QBOSyncClient(backend: client)

        let codes = try await syncClient.fetchTaxCodes(realmID: realmID)
        let rates = try await syncClient.fetchTaxRates(realmID: realmID)
        let agencies = try await syncClient.fetchTaxAgencies(realmID: realmID)

        print("Tax codes (\(codes.count)):")
        for code in codes { print("  \(code.id): \(code.name), taxable=\(String(describing: code.taxable))") }
        print("Tax rates (\(rates.count)):")
        for rate in rates { print("  \(rate.id): \(rate.name), \(String(describing: rate.ratePercent))%, active=\(rate.isActive), agency=\(rate.agencyID ?? "none")") }
        print("Tax agencies (\(agencies.count)):")
        for agency in agencies { print("  \(agency.id): \(agency.displayName)") }
        exit(0)
    } catch {
        FileHandle.standardError.write("tax-check failed: \(error)\n".data(using: .utf8)!)
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

        let cashFlowLines = try await syncClient.fetchCashFlow(realmID: realmID, period: period)
        print("Cash Flow: \(cashFlowLines.count) lines")
        for line in cashFlowLines.prefix(8) {
            let indent = String(repeating: "  ", count: line.depth)
            print("  \(indent)\(line.label): \(line.amount?.description ?? "-")\(line.isSummary ? " [SUMMARY]" : "")")
        }

        let trialBalanceLines = try await syncClient.fetchTrialBalance(realmID: realmID, period: period)
        print("Trial Balance: \(trialBalanceLines.count) lines")
        for line in trialBalanceLines.prefix(8) {
            print("  \(line.label): debit=\(line.debit?.description ?? "-") credit=\(line.credit?.description ?? "-")\(line.isSummary ? " [SUMMARY]" : "")")
        }
        if let total = trialBalanceLines.last(where: { $0.isSummary }) {
            print("  ...TOTAL: debit=\(total.debit?.description ?? "-") credit=\(total.credit?.description ?? "-")")
        }

        let agedReceivablesLines = try await syncClient.fetchAgedReceivables(realmID: realmID)
        print("Aged Receivables: \(agedReceivablesLines.count) lines")
        for line in agedReceivablesLines.prefix(6) {
            let indent = String(repeating: "  ", count: line.depth)
            print("  \(indent)\(line.label): total=\(line.total?.description ?? "-")\(line.isSummary ? " [SUMMARY]" : "")")
        }

        let agedPayablesLines = try await syncClient.fetchAgedPayables(realmID: realmID)
        print("Aged Payables: \(agedPayablesLines.count) lines")
        for line in agedPayablesLines.prefix(6) {
            let indent = String(repeating: "  ", count: line.depth)
            print("  \(indent)\(line.label): total=\(line.total?.description ?? "-")\(line.isSummary ? " [SUMMARY]" : "")")
        }

        let generalLedgerLines = try await syncClient.fetchGeneralLedger(realmID: realmID, period: period)
        print("General Ledger: \(generalLedgerLines.count) lines")
        for line in generalLedgerLines.prefix(10) {
            if line.isAccountHeader {
                print("  [\(line.label)]")
            } else {
                print("    \(line.label) \(line.transactionType ?? "") \(line.name ?? "") amount=\(line.amount?.description ?? "-") balance=\(line.balance?.description ?? "-")\(line.isSummary ? " [SUMMARY]" : "")")
            }
        }

        print("Syncing Purchase + Account + Preferences for \(realmID.rawValue), \(year)-\(month)...")
        let syncedDataSet = try await syncClient.sync(realmID: realmID, period: period)
        print("  transactions read: \(syncedDataSet.transactions.count)")
        print("  accounts read: \(syncedDataSet.accounts.count)")
        print("  vendors read: \(syncedDataSet.vendors.count)")
        print("  coverage: \(syncedDataSet.coverage)")
        print("  customTxnNumbersForPurchases: \(syncedDataSet.companyFacts.customTxnNumbersForPurchases)")
        for txn in syncedDataSet.transactions.sorted(by: { $0.id < $1.id }) {
            print("    #\(txn.id) \(txn.vendorName ?? "?") \(txn.txnDate) \(txn.totalAmount) doc=\(txn.docNumber ?? "-") voided=\(txn.isVoided) acct=\(txn.paymentAccountID ?? "-") lineAccts=\(txn.lineAccountIDs)")
        }

        // Mirrors AppState.syncAndEvaluate(): `syncClient.sync()`'s dataset
        // doesn't carry the report lines already fetched above (they're a
        // separate call) — merge them in so rules that depend on
        // `.report` (VL-FORCED-RECON-001) actually see them here too. A
        // real bug (vendorCredits silently dropped the same way) was found
        // in AppState's copy of this exact reconstruction on 2026-08-18;
        // this devtool command must not carry the same class of bug.
        let dataSet = NormalizedDataSet(
            realmID: syncedDataSet.realmID,
            period: syncedDataSet.period,
            transactions: syncedDataSet.transactions,
            accounts: syncedDataSet.accounts,
            vendors: syncedDataSet.vendors,
            deposits: syncedDataSet.deposits,
            vendorCredits: syncedDataSet.vendorCredits,
            profitAndLossLines: profitAndLossLines,
            balanceSheetLines: balanceSheetLines,
            agedReceivablesLines: agedReceivablesLines,
            agedPayablesLines: agedPayablesLines,
            coverage: syncedDataSet.coverage,
            companyFacts: syncedDataSet.companyFacts
        )

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

case "csv-import-check":
    guard arguments.count >= 6,
          let year = Int(arguments[4]), let month = Int(arguments[5]) else {
        FileHandle.standardError.write("Usage: csv-import-check <csvPath> <statementAccountID> <year> <month>\n".data(using: .utf8)!)
        exit(64)
    }
    let csvPath = arguments[2]
    let statementAccountID = arguments[3]
    do {
        let csvText = try String(contentsOfFile: csvPath, encoding: .utf8)
        let rows = CSVParser.parse(csvText)
        guard !rows.isEmpty else {
            FileHandle.standardError.write("\(csvPath) is empty.\n".data(using: .utf8)!)
            exit(2)
        }
        let mappings = [
            ColumnMapping(sourceColumn: 0, sourceHeader: rows[0][0], target: .date, origin: .userSpecified, confirmed: true),
            ColumnMapping(sourceColumn: 1, sourceHeader: rows[0][1], target: .description, origin: .userSpecified, confirmed: true),
            ColumnMapping(sourceColumn: 2, sourceHeader: rows[0][2], target: .amount, origin: .userSpecified, confirmed: true)
        ]
        let documentID = ImportedDocumentID(rawValue: "\(csvPath)-\(Date().timeIntervalSince1970)")
        let importResult = BankStatementCSVImporter.import(
            rows: rows, mappings: mappings, hasHeaderRow: true,
            realmID: realmID, documentID: documentID, importedAt: Date(),
            statementAccountID: statementAccountID
        )
        guard importResult.defects.isEmpty else {
            FileHandle.standardError.write("Import produced defects: \(importResult.defects)\n".data(using: .utf8)!)
            exit(2)
        }
        print("Imported \(importResult.transactions.count) statement line(s) from \(csvPath):")
        for line in importResult.transactions {
            print("  \(line.vendorName ?? "?") \(line.txnDate) \(line.totalAmount) acct=\(line.paymentAccountID ?? "-")")
        }

        let tempStoreRoot = FileManager.default.temporaryDirectory.appending(path: "voiceledger-devtool-csv-import-check")
        let store = try ClientStore(realmID: realmID, rootDirectory: tempStoreRoot)
        try await store.upsertImportedStatementLines(importResult.transactions)

        let configuration = try BackendConfiguration.fromEnvironment()
        let backend = BackendClient(configuration: configuration)
        let syncClient = QBOSyncClient(backend: backend)
        let period = AccountingPeriod(year: year, month: month)
        let syncedDataSet = try await syncClient.sync(realmID: realmID, period: period)

        let importedLines = try await store.loadImportedStatementLines()
        let dataSet = NormalizedDataSet(
            realmID: syncedDataSet.realmID, period: syncedDataSet.period,
            transactions: syncedDataSet.transactions + importedLines,
            accounts: syncedDataSet.accounts, vendors: syncedDataSet.vendors,
            deposits: syncedDataSet.deposits, coverage: syncedDataSet.coverage,
            companyFacts: syncedDataSet.companyFacts
        )

        let engine = RuleEngine(rules: RuleRegistry.all)
        let context = RuleContext(period: period, materiality: .defaultPolicy, companyFacts: dataSet.companyFacts)
        let evaluation = await engine.evaluate(pages: [.page3Transactions, .cleanupAssessment, .bankFeedCleanup], input: dataSet, context: context)

        for ruleID in ["VL-RECON-MISSING-001", "VL-VENDOR-MISMATCH-001"] {
            guard let result = evaluation.results[RuleID(rawValue: ruleID)] else { continue }
            print("\nRule \(ruleID):")
            switch result.outcome {
            case .pass(let coverage, let checked):
                print("  PASS — coverage=\(coverage), checked=\(checked)")
            case .cannotEvaluate(let reason):
                print("  CANNOT EVALUATE — \(reason)")
            case .findings(let findings):
                print("  \(findings.count) finding(s):")
                for f in findings {
                    print("    [\(f.id.prefix(12))...] \(f.title) — confidence=\(f.confidence.rawValue) severity=\(f.severity.rawValue)")
                }
            }
        }
        exit(0)
    } catch {
        FileHandle.standardError.write("csv-import-check failed: \(error)\n".data(using: .utf8)!)
        exit(2)
    }

default:
    exit(64)
}
