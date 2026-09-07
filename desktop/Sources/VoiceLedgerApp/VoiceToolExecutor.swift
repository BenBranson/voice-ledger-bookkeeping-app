import Foundation
import Core
import Voice
import IntegrationsQuickBooks

/// Dispatches one tool call the model made into a real `AppState`
/// mutation/read — see `VoiceToolLoop`'s own doc comment for the overall
/// design. Every branch here either reads already-loaded state, or calls
/// an `AppState` method that already exists for the on-screen UI
/// (`loadBalanceSheet`, `syncAndEvaluate`, `loadFirmCockpit`,
/// `switchActiveClient`) — nothing here invents a new way to reach
/// QuickBooks.
extension VoiceEngine {
    /// `resultText` is plain, factual, narration-ready text — never
    /// spoken directly to the user (the caller always runs it through one
    /// more model call to phrase it naturally), but never anything BUT
    /// real computed values either.
    func execute(_ call: AIToolCall) async -> (resultText: String, uiAction: VoiceUIAction?) {
        switch call.name {
        case "navigate":
            guard let pageRaw = call.arguments["page"]?.stringValue, let destination = VoiceDestination(rawValue: pageRaw) else {
                return ("Unknown page.", nil)
            }
            return ("Navigated to \(destination.rawValue).", .navigate(destination))

        case "open_findings":
            guard let queriesValue = call.arguments["queries"], case .array(let queryValues) = queriesValue else {
                return ("No search terms given.", nil)
            }
            let queries: [String] = queryValues.compactMap { $0.stringValue }
            let openFindings = appState.findings.filter { $0.status == .open }
            var matchedIDs: [String] = []
            var lines: [String] = []
            for query in queries {
                if let match = Self.bestMatch(for: query, in: openFindings) {
                    matchedIDs.append(match.id)
                    lines.append("Found \"\(match.title)\" (severity \(match.severity.rawValue), \(match.dollarExposure.description)) for \"\(query)\".")
                } else {
                    lines.append("No open finding matched \"\(query)\".")
                }
            }
            guard !matchedIDs.isEmpty else { return (lines.joined(separator: " "), nil) }
            return (lines.joined(separator: " "), .openFindings(ids: matchedIDs))

        case "find_findings":
            let category = call.arguments["category"]?.stringValue ?? "all_open"
            let ruleIDs = Self.ruleIDs(for: category)
            let matches = appState.findings.filter { finding in
                finding.status == .open && (ruleIDs == nil || ruleIDs!.contains(finding.ruleID.rawValue))
            }
            guard !matches.isEmpty else { return ("No open findings matched category \"\(category)\".", nil) }
            let lines = matches.prefix(8).map { "\($0.title) (\($0.severity.rawValue), \($0.dollarExposure.description))" }
            var text = "\(matches.count) matching finding(s): " + lines.joined(separator: "; ")
            if matches.count > 8 { text += "; and \(matches.count - 8) more" }
            return (text, nil)

        case "get_financial_summary":
            return await getFinancialSummary(
                metric: call.arguments["metric"]?.stringValue ?? "",
                period: call.arguments["period"]?.stringValue ?? "current"
            )

        case "list_vendors_by_spend":
            let limit = Self.intArgument(call.arguments["limit"], default: 5)
            let top = VendorSpendSummary.top(limit, from: appState.transactions)
            guard !top.isEmpty else { return ("No vendor spend data available for the currently loaded period.", nil) }
            let lines = top.map { "\($0.vendorName): \($0.total.description) across \($0.transactionCount) transaction(s)" }
            return ("Top vendors by spend, this loaded period only: " + lines.joined(separator: "; "), nil)

        case "generate_chart":
            return await generateChart(kind: call.arguments["kind"]?.stringValue ?? "")

        case "refresh_client_data":
            await appState.syncAndEvaluate()
            let openCount = appState.findings.filter { $0.status == .open }.count
            return ("Refreshed from QuickBooks. \(openCount) open finding(s) now.", nil)

        case "get_sync_status":
            guard let lastSyncedAt = appState.lastSyncedAt else {
                return ("This client hasn't been synced yet this session.", nil)
            }
            return ("Last synced \(lastSyncedAt.formatted(date: .abbreviated, time: .shortened)).", nil)

        case "list_clients_needing_attention":
            if appState.firmCockpitSummaries.isEmpty { await appState.loadFirmCockpit() }
            let limit = Self.intArgument(call.arguments["limit"], default: 3)
            let ranked = appState.firmCockpitSummaries.sorted { $0.urgentFindingsCount > $1.urgentFindingsCount }.prefix(limit)
            guard !ranked.isEmpty else { return ("No other connected clients found.", nil) }
            let lines = ranked.map { summary -> String in
                let syncLabel = summary.client.lastHealthCheckAt.map { "last checked \($0.formatted(date: .abbreviated, time: .omitted))" } ?? "never checked"
                return "\(summary.client.companyName ?? "(unnamed)"): \(summary.urgentFindingsCount) urgent, \(summary.openFindingsCount) open finding(s) total, \(syncLabel)"
            }
            return (lines.joined(separator: "; "), nil)

        case "get_cash_flow_forecast":
            if appState.balanceSheetLines.isEmpty { await appState.loadBalanceSheet() }
            if appState.agedReceivablesLines.isEmpty { await appState.loadAgedReceivables() }
            if appState.agedPayablesLines.isEmpty { await appState.loadAgedPayables() }
            if appState.trailingPurchases.isEmpty { await appState.loadTrailingPurchases() }
            let forecast = appState.cashFlowForecast
            guard forecast.startingCash != nil else { return ("No balance sheet or aging data available yet to build a forecast — try syncing first.", nil) }
            var lines = ["Starting cash: \(forecast.startingCash?.description ?? "not available")"]
            for horizon in forecast.horizons {
                lines.append("In \(horizon.days) days: expected in \(horizon.expectedInflow?.description ?? "not available"), expected out \(horizon.expectedOutflow?.description ?? "not available"), projected ending cash \(horizon.projectedEndingCash?.description ?? "not available")")
            }
            if let atRisk = forecast.atRiskReceivables, atRisk.minorUnits != 0 {
                lines.append("At-risk receivables (91+ days overdue, not counted as expected cash): \(atRisk.description)")
            }
            return (lines.joined(separator: "; "), .navigate(.cashFlowForecast))

        case "get_recurring_vendors":
            if appState.trailingPurchases.isEmpty { await appState.loadTrailingPurchases() }
            let recurring = appState.recurringVendors
            guard !recurring.isEmpty else { return ("No recurring vendors detected in the trailing \(AppState.trailingPurchasesMonths) months of purchase history.", .navigate(.recurringVendors)) }
            let missing = appState.missingRecurringVendors
            var lines = recurring.map { vendor -> String in
                let changedNote = vendor.lastAmountChanged ? " (last charge's amount changed)" : ""
                let overdueNote = missing.contains(where: { $0.id == vendor.id }) ? " — OVERDUE for expected charge" : ""
                return "\(vendor.vendorName): \(vendor.averageAmount.description) roughly every \(Int(vendor.averageIntervalDays.rounded())) days, next expected \(vendor.expectedNextChargeDate.formatted)\(changedNote)\(overdueNote)"
            }
            if lines.count > 10 {
                lines = Array(lines.prefix(10)) + ["...and \(recurring.count - 10) more not listed here"]
            }
            return (lines.joined(separator: "; "), .navigate(.recurringVendors))

        case "switch_client":
            let name = call.arguments["name"]?.stringValue ?? ""
            if appState.firmCockpitSummaries.isEmpty { await appState.loadFirmCockpit() }
            guard let match = appState.firmCockpitSummaries.first(where: { ($0.client.companyName ?? "").localizedCaseInsensitiveContains(name) }) else {
                return ("No connected client matching \"\(name)\" was found.", nil)
            }
            await appState.switchActiveClient(to: match.client.realmID, environment: match.client.environment)
            return ("Switching to \(match.client.companyName ?? name)'s books now.", nil)

        default:
            return ("Unknown tool: \(call.name).", nil)
        }
    }

    /// Case-insensitive substring match against a finding's title or
    /// vendor name — deliberately simple (no fuzzy/edit-distance
    /// matching): a wrong "best guess" match here would open the WRONG
    /// transaction, a worse failure than asking the person to be more
    /// specific. Ties broken by highest dollar exposure, since that's the
    /// one most likely to be "the" thing someone's asking about.
    /// Owner-reported bug (2026-09-07), found live testing Claude Haiku
    /// 4.5 as a tool-loop option: "pull up the Notes Payable finding and
    /// the Checking finding" failed to match either, even though both
    /// were plainly visible in the open findings list. Root cause: the
    /// query has to be a substring of the finding's TITLE — Gemma
    /// happened to pass bare keywords ("Notes Payable"), which matched;
    /// Claude phrased the same request more naturally ("the Notes Payable
    /// finding," "the Checking finding"), and the extra filler words broke
    /// a strict one-directional substring check that never needed to be
    /// that strict — confirmed root cause (2026-09-07, via a temporary
    /// debug log of the model's actual `queries` arguments): a paraphrasing
    /// model (Claude Haiku 4.5) sends queries like "Notes Payable negative
    /// liability balance" for a finding titled "Notes Payable has a
    /// negative liability balance" — the words aren't contiguous in the
    /// title (it has "has a" and "asset" inserted), so no substring check
    /// can ever match it, filler-word stripping included. Scoring by
    /// fraction of query words found anywhere in the title handles
    /// reordering and inserted words from any model's phrasing, not just
    /// exact substrings.
    private static let queryFillerWords: Set<String> = ["the", "a", "an", "finding", "findings", "transaction", "account", "entry"]

    private static func bestMatch(for query: String, in findings: [Finding]) -> Finding? {
        let queryWords = query.lowercased()
            .split(separator: " ")
            .map(String.init)
            .filter { !queryFillerWords.contains($0) }
        guard !queryWords.isEmpty else { return nil }

        func score(_ text: String?) -> Double {
            guard let text, !text.isEmpty else { return 0 }
            let textWords = Set(text.lowercased().split(separator: " ").map(String.init))
            let matched = queryWords.filter { textWords.contains($0) }.count
            return Double(matched) / Double(queryWords.count)
        }

        let scored = findings.map { finding -> (Finding, Double) in
            (finding, max(score(finding.title), score(finding.vendorName)))
        }
        guard let best = scored.max(by: { $0.1 == $1.1 ? abs($0.0.dollarExposure.minorUnits) < abs($1.0.dollarExposure.minorUnits) : $0.1 < $1.1 }),
              best.1 >= 0.5 else { return nil }
        return best.0
    }

    private static func intArgument(_ value: JSONValue?, default defaultValue: Int) -> Int {
        guard case .number(let doubleValue)? = value else { return defaultValue }
        return Int(doubleValue)
    }

    private static func ruleIDs(for category: String) -> Set<String>? {
        switch category {
        case "duplicates": return ["VL-DUP-EXP-001", "VL-DUP-EXP-002", "VL-DUP-VEND-001", "VL-DUP-BILL-001", "VL-DUP-INV-001", "VL-DUP-PAY-001"]
        case "miscategorized_or_uncategorized": return ["VL-CAT-MISCODE-001", "VL-CAT-UNCAT-001"]
        case "personal_expense": return ["VL-PERSONAL-001"]
        case "negative_balance": return ["VL-BS-NEGBAL-001"]
        case "late_fees_or_overdrafts": return ["VL-FEE-AVOIDABLE-001"]
        case "vendor_price_increase": return ["VL-VEND-PRICE-001"]
        default: return nil // "all_open" — every open finding, no rule filter
        }
    }

    private func getFinancialSummary(metric: String, period: String) async -> (resultText: String, uiAction: VoiceUIAction?) {
        if period == "prior_month", appState.priorPeriodProfitAndLossLines.isEmpty || appState.priorPeriodBalanceSheetLines.isEmpty {
            await appState.loadVarianceAnalysis()
        }
        if period == "current", appState.balanceSheetLines.isEmpty { await appState.loadBalanceSheet() }
        if period == "current", appState.profitAndLossLines.isEmpty { await appState.loadProfitAndLoss() }

        let balanceSheetLines = period == "prior_month" ? appState.priorPeriodBalanceSheetLines : appState.balanceSheetLines
        let profitAndLossLines = period == "prior_month" ? appState.priorPeriodProfitAndLossLines : appState.profitAndLossLines
        let periodLabel = period == "prior_month" ? "the prior month" : "the currently loaded period"

        switch metric {
        case "net_income":
            guard let value = TaxEstimate.netIncome(from: profitAndLossLines) else { return ("Net income isn't available for \(periodLabel).", nil) }
            return ("Net income for \(periodLabel): \(value.description).", nil)
        case "revenue":
            guard let value = FinancialKPIs.totalIncome(from: profitAndLossLines) else { return ("Revenue isn't available for \(periodLabel).", nil) }
            return ("Revenue for \(periodLabel): \(value.description).", nil)
        case "cash_balance":
            guard let value = FinancialKPIs.cashBalance(from: balanceSheetLines) else { return ("Cash balance isn't available for \(periodLabel).", nil) }
            return ("Cash balance as of \(periodLabel): \(value.description).", nil)
        case "uncategorized_count":
            let count = appState.findings.filter { $0.status == .open && $0.ruleID.rawValue == "VL-CAT-UNCAT-001" }.count
            return ("\(count) transaction(s) still uncategorized.", nil)
        default:
            return ("Unknown financial metric: \(metric).", nil)
        }
    }

    private func generateChart(kind: String) async -> (resultText: String, uiAction: VoiceUIAction?) {
        if appState.profitAndLossLines.isEmpty { await appState.loadProfitAndLoss() }

        switch kind {
        case "expense_drivers":
            let drivers = TopExpenseDrivers.top(8, from: appState.profitAndLossLines)
            guard !drivers.isEmpty else { return ("No expense data available to chart for the loaded period.", nil) }
            let request: ChartRequest = .expenseDrivers(title: "Top Expense Categories", drivers: drivers)
            let action: VoiceUIAction = .presentChart(request)
            return ("Showing the top expense categories for the loaded period.", action)
        case "pareto_cost_drivers":
            let drivers = TopExpenseDrivers.top(15, from: appState.profitAndLossLines)
            guard !drivers.isEmpty else { return ("No expense data available to chart for the loaded period.", nil) }
            let request: ChartRequest = .paretoCostDrivers(title: "Biggest Cost Drivers", drivers: drivers)
            let action: VoiceUIAction = .presentChart(request)
            return ("Showing a Pareto chart of the biggest cost drivers for the loaded period.", action)
        case "vendor_spend":
            let vendors = VendorSpendSummary.top(10, from: appState.transactions)
            guard !vendors.isEmpty else { return ("No vendor spend data available to chart for the loaded period.", nil) }
            let request: ChartRequest = .vendorSpend(title: "Spend by Vendor", vendors: vendors)
            let action: VoiceUIAction = .presentChart(request)
            return ("Showing vendor spend for the loaded period.", action)
        case "income_vs_expenses":
            guard let segments = ProfitAndLossWaterfall.segments(from: appState.profitAndLossLines) else {
                return ("Income vs. expenses data isn't available to chart for the loaded period.", nil)
            }
            let request: ChartRequest = .incomeVsExpenses(title: "Income vs. Expenses", segments: segments)
            let action: VoiceUIAction = .presentChart(request)
            return ("Showing income versus expenses for the loaded period.", action)
        default:
            return ("Unknown chart kind: \(kind).", nil)
        }
    }
}
