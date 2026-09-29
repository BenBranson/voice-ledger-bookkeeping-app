import Foundation
import Core
import IntegrationsQuickBooks
import IntegrationsImports
import IntegrationsVoice
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
guard arguments.count >= 2, ["health", "tax-check", "connections-check", "switch-session-check", "ask-ai-check", "sync-check", "history-check", "chart-samples", "balances-check", "agreement-sample", "sample-report", "monthly-report", "csv-import-check", "export-sample", "xlsx-import-check", "ocr-import-check", "voice-service-check"].contains(arguments[1]) else {
    print("""
    voiceledger-devtool — gate-verification CLI, not the app.

    Commands:
      health                 Run the live health check against a connected realm.
      tax-check              Fetch TaxCode/TaxRate/TaxAgency live and print
                              them (docs/VOICE_LEDGER_SPEC.md Page 9). Read-only.
      connections-check      Fetch the backend's connection registry live
                              (docs/VOICE_LEDGER_SPEC.md's Firm Cockpit). Read-only.
      switch-session-check   Mints a fresh session for VOICE_LEDGER_REALM_ID
                              via the Client Switcher's endpoint, then proves
                              the new token actually works with a follow-up
                              call.
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
      voice-service-check    Health-checks the local voice-service, then
                              runs a real synthesize -> transcribe round
                              trip against it (docs/VOICE_LEDGER_SPEC.md's
                              /voice module). No realm needed — voice-service
                              never sees bookkeeping data. Requires
                              voice-service running locally on port 8790.

    Required environment variables (not needed for export-sample/voice-service-check):
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

if arguments[1] == "voice-service-check" {
    do {
        let client = VoiceServiceClient()
        let healthy = try await client.healthCheck()
        print("voice-service health: \(healthy ? "OK" : "NOT OK")")
        guard healthy else { exit(2) }

        let speechText = "Cleanup Assessment. Two findings need attention."
        print("Synthesizing: \(speechText.debugDescription)")
        let wav = try await client.synthesize(text: speechText)
        print("  got \(wav.count) bytes of WAV audio")

        print("Transcribing that same audio back...")
        let transcribed = try await client.transcribe(audioData: wav)
        print("  heard: \(transcribed.debugDescription)")
        print("\nRound trip complete. voice-service is working.")
        exit(0)
    } catch {
        FileHandle.standardError.write("voice-service-check failed: \(error)\nIs voice-service running? (cd voice-service && .venv/bin/python -m uvicorn main:app --host 127.0.0.1 --port 8790)\n".data(using: .utf8)!)
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

case "switch-session-check":
    // docs/VOICE_LEDGER_SPEC.md's Client Switcher — live-verifies the
    // actual BackendClient.requestSession Swift code path, then proves
    // the returned token is a genuinely working session (not just a
    // 200 response) by using it for a real follow-up call.
    do {
        let configuration = try BackendConfiguration.fromEnvironment()
        let client = BackendClient(configuration: configuration)
        let newToken = try await client.requestSession(forRealmID: realmID)
        print("Minted a new session token (\(newToken.count) chars).")
        let newConfig = BackendConfiguration(baseURL: configuration.baseURL, sessionToken: newToken)
        let newClient = BackendClient(configuration: newConfig)
        let connections = try await newClient.getConnections()
        print("New token works — fetched \(connections.count) connection(s) with it.")
        exit(0)
    } catch {
        FileHandle.standardError.write("switch-session-check failed: \(error)\n".data(using: .utf8)!)
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

case "sample-report":
    let out = arguments.count >= 3 ? arguments[2] : "sample-snapshot.json"
    do {
        let sealed = try SampleMonthlyReport.build(generatedAt: Date()).sealedJSON()
        try sealed.json.write(to: URL(fileURLWithPath: out))
        print("SAMPLE snapshot \(sealed.snapshotID.prefix(12)) written to \(out)")
    } catch {
        FileHandle.standardError.write("sample-report failed: \(error)\n".data(using: .utf8)!)
        exit(1)
    }

case "monthly-report":
    guard arguments.count >= 5, let year = Int(arguments[2]), let month = Int(arguments[3]) else {
        FileHandle.standardError.write("Usage: monthly-report <year> <month> <out.json>\n".data(using: .utf8)!)
        exit(64)
    }
    do {
        let client = QBOSyncClient(backend: BackendClient(configuration: try BackendConfiguration.fromEnvironment()))
        let company = try await client.fetchCompanyInfo(realmID: realmID)
        // Optional 5th argument: a COPY of a client store root (never the
        // live one), to include its saved findings and activity log.
        var findings: [Finding] = []
        var activity: [ActivityLogEntry] = []
        if arguments.count >= 6 {
            let store = try ClientStore(realmID: realmID, rootDirectory: URL(fileURLWithPath: arguments[5]))
            findings = try await store.loadFindings()
            activity = try await store.loadActivityLog()
        }
        var inputs = try await client.loadMonthlyReportInputs(realmID: realmID, period: AccountingPeriod(year: year, month: month), clientName: company.companyName, environment: "sandbox", findings: findings, coverage: .complete, today: AccountingDate(date: Date()))
        inputs.activityLog = activity
        inputs.clientQuestions = ClientQuestionDrafter.threads(from: activity)
        let sealed = try MonthlyReportBuilder.build(inputs).sealedJSON()
        try sealed.json.write(to: URL(fileURLWithPath: arguments[4]))
        print("Snapshot \(sealed.snapshotID.prefix(12)) written to \(arguments[4])")
    } catch {
        FileHandle.standardError.write("monthly-report failed: \(error)\n".data(using: .utf8)!)
        exit(1)
    }

case "agreement-sample":
    // FICTIONAL client (Apex Peak Logistics) — writes the signing page and
    // the review/signed HTML for visual checks. No QuickBooks access.
    let dir = URL(fileURLWithPath: arguments.count >= 3 ? arguments[2] : ".")
    var intake = ClientIntake(legalBusinessName: "Apex Peak Logistics, LLC <b>", entityType: "Texas limited liability company", bankAccountCountAnswer: "2", creditCardCountAnswer: "2",
                              paymentProcessors: "Stripe", pointOfContactName: "Marcus Vance", pointOfContactRole: "Managing Member", pointOfContactEmail: "marcus@example.com", hourlyRateText: "75")
    intake.needsCleanup = true
    intake.monthsBehind = .threeToSix
    intake.cleanupIssues.multipleUncategorized = true
    intake.cleanupIssues.negativeBalances = true
    intake.monthlyFlags.payrollProcessing = true
    let agreement = EngagementAgreement.from(intake: intake, effectiveDate: AccountingDate(year: 2026, month: 10, day: 1))
    let on = AccountingDate(year: 2026, month: 9, day: 29)
    let sig = AgreementSignature(typedName: "Marcus Vance", title: "Managing Member", method: .typed, imageDataURL: nil, signedAtLabel: "September 29, 2026 at 3:14 PM CDT", signedAtISO: "2026-09-29T20:14:00Z", device: "In person on the bookkeeper's Mac (Voice Ledger)")
    try? Data(EngagementAgreementHTML.render(agreement, mode: .signing, providerSignedOn: on).utf8).write(to: dir.appending(path: "signing.html"))
    try? Data(EngagementAgreementHTML.render(agreement, mode: .review, providerSignedOn: on).utf8).write(to: dir.appending(path: "review.html"))
    try? Data(EngagementAgreementHTML.render(agreement, mode: .signed(sig), providerSignedOn: on).utf8).write(to: dir.appending(path: "signed.html"))
    print("Document ID \(EngagementAgreementTemplate.documentID(agreement)) — wrote signing.html, review.html, signed.html")

case "balances-check":
    // Read-only: each asset/liability account's live CurrentBalance next
    // to its period-end Balance Sheet amount (sign-convention check).
    guard arguments.count >= 4, let year = Int(arguments[2]), let month = Int(arguments[3]) else { exit(64) }
    do {
        let client = QBOSyncClient(backend: BackendClient(configuration: try BackendConfiguration.fromEnvironment()))
        let period = AccountingPeriod(year: year, month: month)
        let data = try await client.sync(realmID: realmID, period: period)
        let bs = try await client.fetchBalanceSheet(realmID: realmID, period: period)
        for account in data.accounts where account.accountType.isAssetOrLiability || account.accountType == .equity {
            let line = bs.first { $0.accountID == account.id && !$0.isSummary }
            print("\(account.accountType.rawValue.padding(toLength: 22, withPad: " ", startingAt: 0)) \(account.name.padding(toLength: 36, withPad: " ", startingAt: 0)) current=\(account.currentBalance.accountingDescription)  bs=\(line?.amount?.accountingDescription ?? "-")")
        }
    } catch {
        FileHandle.standardError.write("balances-check failed: \(error)\n".data(using: .utf8)!)
        exit(1)
    }

case "chart-samples":
    do {
        let client = QBOSyncClient(backend: BackendClient(configuration: try BackendConfiguration.fromEnvironment()))
        let history = try await client.syncHistory(realmID: realmID, months: 24, through: AccountingDate(date: Date()))
        let july = history.monthlyProfitAndLoss.first { $0.period == AccountingPeriod(year: 2026, month: 7) }?.lines ?? []
        let feeds = ClientDiagnostics.bankFeedActivity(history: history, asOf: history.through)
        let busiest = feeds.max { a, b in
            history.transactions.filter { $0.paymentAccountID == a.accountID }.count < history.transactions.filter { $0.paymentAccountID == b.accountID }.count
        }
        struct Samples: Encodable {
            let moneyFlow: MoneyFlowData?
            let sparklines: SparklineData?
            let trend: TrendData
            let calendar: PostingCalendar?
            let treemap: ExpenseTree?
        }
        let samples = Samples(
            moneyFlow: ChartData.moneyFlow(from: july, hubLabel: "July 2026", topExpenses: 6),
            sparklines: ChartData.sparklines(months: history.monthlyProfitAndLoss, monthEndCash: history.monthEndCash ?? []),
            trend: ChartData.trend(from: history.monthlyProfitAndLoss),
            calendar: busiest.flatMap { ChartData.postingCalendar(history: history, accountID: $0.accountID) },
            treemap: ChartData.expenseTree(from: july)
        )
        let encoder = JSONEncoder()
        try encoder.encode(samples).write(to: URL(fileURLWithPath: arguments.count >= 3 ? arguments[2] : "chart-samples.json"))
        print("flow:\(samples.moneyFlow != nil) spark:\(samples.sparklines?.rows.count ?? 0) trend:\(samples.trend.points.count) cal:\(samples.calendar?.days.count ?? -1) tree:\(samples.treemap?.nodes.count ?? -1)")
    } catch {
        FileHandle.standardError.write("chart-samples failed: \(error)\n".data(using: .utf8)!)
        exit(1)
    }

case "history-check":
    let months = arguments.count >= 3 ? Int(arguments[2]) ?? 24 : 24
    do {
        let backend = BackendClient(configuration: try BackendConfiguration.fromEnvironment())
        let started = Date()
        let history = try await QBOSyncClient(backend: backend).syncHistory(realmID: realmID, months: months, through: AccountingDate(date: Date()))
        print("History \(history.from.formatted) → \(history.through.formatted): \(history.monthsCovered) months in \(String(format: "%.1f", Date().timeIntervalSince(started)))s")
        let byKind = Dictionary(grouping: history.transactions, by: \.entityKind).mapValues(\.count)
        print("Transactions: \(history.transactions.count) \(byKind.sorted { $0.key.rawValue < $1.key.rawValue }.map { "\($0.key.rawValue)=\($0.value)" }.joined(separator: " "))")
        print("Deposits: \(history.deposits.count) (with date: \(history.deposits.filter { $0.txnDate != nil }.count)), vendor credits: \(history.vendorCredits.count), accounts: \(history.accounts.count)")
        let nonEmptyMonths = history.monthlyProfitAndLoss.filter { !$0.lines.isEmpty }.map { "\($0.period.year)-\($0.period.month)" }
        print("P&L months with data: \(nonEmptyMonths.count) [\(nonEmptyMonths.joined(separator: ", "))]")
        print("Balance sheet lines: \(history.latestBalanceSheet.count), cash flow lines: \(history.latestCashFlow.count)")
        print("Cash flow: " + history.latestCashFlow.map { "\($0.label)=\($0.amount?.description ?? "-")\($0.isSummary ? "*" : "")" }.joined(separator: " | "))
        print("Balance sheet summaries: " + history.latestBalanceSheet.filter(\.isSummary).map { "\($0.label)=\($0.amount?.description ?? "-")" }.joined(separator: " | "))
        print("P&L (latest) summaries: " + (history.monthlyProfitAndLoss.last?.lines.filter(\.isSummary).map { "\($0.label)=\($0.amount?.description ?? "-")" }.joined(separator: " | ") ?? ""))
        let asOf = AccountingDate(date: Date())
        for feed in ClientDiagnostics.bankFeedActivity(history: history, asOf: asOf) {
            print("Feed: \(feed.accountName) last=\(feed.lastActivity?.formatted ?? "none") stale=\(feed.isStale)")
        }
        for alert in ClientDiagnostics.fluxAlerts(history: history, asOf: asOf) {
            print("Flux: \(alert.label) \(alert.current.accountingDescription) vs \(alert.trailingAverage.accountingDescription)")
        }
        ClientDiagnostics.kpiSummary(history: history, asOf: asOf).emailBullets.forEach { print("KPI: \($0)") }
        let scope = ClientDiagnostics.scopeScore(history: history, openFindings: [], asOf: asOf, inputs: CleanupScopeInputs(unreconciledMonths: 3))
        print("Scope: \(scope.score)/100 \(scope.band) quote=\(scope.cleanupQuote.accountingDescription) undeposited=\(scope.undepositedPaymentCount) aged90=\(scope.agedOver90Count) dupAcctGroups=\(scope.duplicateAccountGroups) avg/mo=\(scope.averageMonthlyTransactions)")
    } catch {
        FileHandle.standardError.write("history-check failed: \(error)\n".data(using: .utf8)!)
        exit(1)
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

        // Prior period's Purchases, for VL-VEND-PRICE-001/VL-CAT-MISCODE-001.
        let priorPeriodTransactions = try await syncClient.fetchPurchases(realmID: realmID, period: period.previousMonth)
        print("Prior period (\(period.previousMonth.year)-\(period.previousMonth.month)) purchases: \(priorPeriodTransactions.count)")

        // Mirrors AppState.syncAndEvaluate(): `syncClient.sync()`'s dataset
        // doesn't carry the report lines already fetched above (they're a
        // separate call) — merge them in so rules that depend on
        // `.report` (VL-FORCED-RECON-001) actually see them here too. A
        // real bug (vendorCredits silently dropped the same way) was found
        // in AppState's copy of this exact reconstruction on 2026-08-18,
        // and trialBalanceLines/priorPeriodTransactions were found missing
        // from THIS devtool copy on 2026-08-28 while live-verifying
        // VL-BS-DRCR-001/VL-CAT-MISCODE-001/VL-VEND-PRICE-001 — same class
        // of bug, different field. This devtool command must not carry it
        // again; if AppState.swift's dataSet construction gains a new
        // field, this one needs the same field the same day.
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
            trialBalanceLines: trialBalanceLines,
            priorPeriodTransactions: priorPeriodTransactions,
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
