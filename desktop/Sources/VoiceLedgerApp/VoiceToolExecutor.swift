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
            return ("Opening \(destination.menuTitle).", .navigate(destination))

        case "open_findings":
            guard let queriesValue = call.arguments["queries"], case .array(let queryValues) = queriesValue else {
                return ("No search terms given.", nil)
            }
            let queries: [String] = queryValues.compactMap { $0.stringValue }
            let openFindings = appState.findings.filter { $0.status == .open }
            var matchedIDs: [String] = []
            var lines: [String] = []
            for query in queries {
                let trimmed = query.trimmingCharacters(in: .whitespaces)
                if let match = openFindings.first(where: { $0.id == trimmed }) ?? Self.bestMatch(for: query, in: openFindings) {
                    matchedIDs.append(match.id)
                    lines.append("Found \"\(match.title)\" for \"\(query)\". Full record:\n" + AskAIContext.compose(finding: match))
                } else {
                    lines.append("No open finding matched \"\(query)\".")
                }
            }
            guard !matchedIDs.isEmpty else { return (lines.joined(separator: " "), nil) }
            return (lines.joined(separator: " "), .openFindings(ids: matchedIDs))

        case "find_findings":
            let category = call.arguments["category"]?.stringValue ?? "all_open"
            let group = FactFindingGroup(rawValue: category) ?? .allOpen
            let fact = ClientFacts.findings(appState.clientData, category: group)
            let matches = fact.value ?? []
            guard !matches.isEmpty else { return ("No open findings matched category \"\(category)\".", nil) }
            let lines = matches.prefix(50).map { "\(ClientText.polish($0.title)) (\($0.severity.rawValue), \($0.dollarExposure.accountingDescription))" }
            var text = "\(matches.count) matching finding(s): " + lines.joined(separator: "; ")
            if matches.count > 50 { text += "; and \(matches.count - 50) more" }
            return (text + " " + fact.scope.sentence(), .showFindingGroup(group))

        case "get_financial_summary":
            return await getFinancialSummary(
                metric: call.arguments["metric"]?.stringValue ?? "",
                period: call.arguments["period"]?.stringValue ?? "current"
            )

        case "list_vendors_by_spend":
            let limit = Self.intArgument(call.arguments["limit"], default: 5)
            let fact = ClientFacts.vendorsBySpend(appState.clientData, limit: limit)
            guard let top = fact.value, !top.isEmpty else { return ("No vendor spend data available for the currently loaded period.", nil) }
            let lines = top.map { "\($0.vendorName): \($0.total.accountingDescription) across \($0.transactionCount) transaction(s)" }
            return ("Top vendors by spend: " + lines.joined(separator: "; ") + ". " + fact.scope.sentence(), nil)

        case "generate_chart":
            return await generateChart(kind: call.arguments["kind"]?.stringValue ?? "")

        case "refresh_client_data":
            await appState.syncAndEvaluate()
            let openCount = appState.findings.filter { $0.status == .open }.count
            return ("Refreshed from QuickBooks. \(openCount) open finding(s) now.", nil)

        case "get_sync_status":
            return (ClientFacts.freshnessSentence(appState.clientData), nil)

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

        case "get_chart_of_accounts":
            let typeFilter = call.arguments["type_filter"]?.stringValue ?? "all"
            let types: Set<LedgerAccountType>?
            switch typeFilter {
            case "income": types = [.income, .otherIncome]
            case "expenses": types = [.expense, .otherExpense, .costOfGoodsSold]
            case "equity": types = [.equity]
            default: types = nil
            }
            let fact = ClientFacts.chartOfAccounts(appState.clientData, types: types)
            guard let filtered = fact.value, !filtered.isEmpty else { return ("No accounts found for filter '\(typeFilter)'.", nil) }
            var lines = ["Chart of Accounts (\(typeFilter)): \(filtered.count) accounts"]
            for account in filtered.prefix(40) { lines.append("- \(account.name) (\(account.type.rawValue)): \(account.balance.accountingDescription)") }
            if filtered.count > 40 { lines.append("...and \(filtered.count - 40) more accounts") }
            return (lines.joined(separator: "\n") + "\n" + fact.scope.sentence(), nil)

        case "search_transactions":
            let query = (call.arguments["query"]?.stringValue ?? "").trimmingCharacters(in: .whitespaces)
            guard !query.isEmpty else { return ("Please provide a search query (vendor name or an exact dollar amount).", nil) }
            let data = appState.clientData
            // An amount goes through the SAME search the Search by Amount page uses.
            if AmountSearch.parseAmount(query) != nil, query.contains(where: \.isNumber) {
                let fact = ClientFacts.searchAmount(data, text: query)
                guard let result = fact.value else { return (fact.note ?? "Couldn't read that amount.", nil) }
                var lines: [String] = []
                if !result.exact.isEmpty {
                    lines.append("\(result.exact.count) transaction(s) for exactly \(result.amount.accountingDescription):")
                    lines += result.exact.prefix(20).map { Self.transactionLine($0) }
                }
                for entry in result.balanceAccounts {
                    let n = entry.postings.count
                    lines.append("\(result.amount.accountingDescription) is the balance of \(entry.account.name), not a single transaction" + (n > 0 ? " — it's built from \(n) posting\(n == 1 ? "" : "s")." : "."))
                }
                if let combo = result.combination {
                    lines.append("No single transaction matches, but these \(combo.count) add up to \(result.amount.accountingDescription): " + combo.map { Self.transactionLine($0) }.joined(separator: " "))
                }
                if lines.isEmpty { lines.append("No transaction or account balance is exactly \(result.amount.accountingDescription).") }
                if let note = fact.note { lines.append(note) }
                return (lines.joined(separator: "\n") + "\n" + fact.scope.sentence(), nil)
            }
            let fact = ClientFacts.searchText(data, query: query)
            let hits = fact.value ?? []
            guard !hits.isEmpty else { return ("No transactions found matching '\(query)'. " + fact.scope.sentence(), nil) }
            var lines = ["Found \(hits.count) matching transactions:"] + hits.prefix(20).map { Self.transactionLine($0) }
            if hits.count > 20 { lines.append("...and \(hits.count - 20) more") }
            if let note = fact.note { lines.append(note) }
            return (lines.joined(separator: "\n") + "\n" + fact.scope.sentence(), nil)

        case "get_account_balance":
            let accountName = call.arguments["account_name"]?.stringValue ?? ""
            guard !accountName.isEmpty else { return ("Please provide an account name.", nil) }
            let fact = ClientFacts.accountBalance(appState.clientData, name: accountName)
            guard let account = fact.value else { return (fact.note ?? "Account not found.", nil) }
            return ("\(ClientFacts.balanceSentence(name: account.name, type: account.type, rawBalance: account.balance)) (\(account.type.rawValue).) \(fact.note ?? "") \(fact.scope.sentence())", nil)

        case "get_vendor_details":
            let vendorName = call.arguments["vendor_name"]?.stringValue ?? ""
            guard !vendorName.isEmpty else { return ("Please provide a vendor name.", nil) }
            let fact = ClientFacts.vendor(appState.clientData, name: vendorName)
            guard let vendor = fact.value else { return ((fact.note ?? "No transactions found for that vendor.") + " " + fact.scope.sentence(), nil) }
            let last = vendor.lastDate.map { ClientText.polish($0.formatted) } ?? "unknown"
            return ("Vendor: \(vendor.name). \(vendor.transactionCount) transaction(s) totaling \(vendor.total.accountingDescription); last on \(last). \(fact.scope.sentence())", nil)

        case "get_report_summary":
            let reportType = call.arguments["report_type"]?.stringValue ?? ""
            guard let kind = ReportKind(rawValue: reportType) else {
                return ("Report type '\(reportType)' isn't available. Use balance_sheet, income_statement, or cash_flow.", nil)
            }
            if kind == .balanceSheet, appState.balanceSheetLines.isEmpty { await appState.loadBalanceSheet() }
            if kind == .incomeStatement, appState.profitAndLossLines.isEmpty { await appState.loadProfitAndLoss() }
            if kind == .cashFlow, appState.cashFlowLines.isEmpty { await appState.loadCashFlow() }
            let fact = ClientFacts.reportLines(appState.clientData, kind: kind)
            guard let lines = fact.value else { return ((fact.note ?? "That report isn't loaded.") + " " + fact.scope.sentence(), nil) }
            // Section headings without an amount are noise; totals and account lines carry the figures.
            let rows = lines.compactMap { line -> String? in line.amount.map { "\(String(repeating: "  ", count: min(line.depth, 3)))\(line.label): \($0.accountingDescription)" } }
            return ("\(reportType.replacingOccurrences(of: "_", with: " ").capitalized):\n" + rows.prefix(60).joined(separator: "\n") + (rows.count > 60 ? "\n…and \(rows.count - 60) more lines" : "") + "\n" + fact.scope.sentence(), nil)

        case "get_finding_recommendation":
            guard let entityRef = self.context.currentEntity, entityRef.type == .finding, let finding = appState.finding(id: entityRef.id) else {
                return ("This tool only works when a finding detail page is open. Please click on a specific finding first.", nil)
            }
            var recommendation = "Recommendation for: \(finding.title)\n\n"
            recommendation += "WHY THIS MATTERS:\n"
            recommendation += "- Severity: \(finding.severity.rawValue) severity\n"
            recommendation += "- Dollar exposure: \(finding.dollarExposure.description)\n"
            recommendation += "- Status: \(finding.status.rawValue)\n\n"

            recommendation += "RECOMMENDED NEXT STEP:\n"
            switch finding.ruleID.rawValue {
            case _ where finding.ruleID.rawValue.contains("DUP"):
                recommendation += "Investigate and consolidate duplicates. Because: duplicate transactions inflate your accounting records and create confusion about true spend and balances. Consolidating ensures accurate financial reporting.\n\n"
                recommendation += "ACTION: Click 'Open in QBO' to compare and merge the duplicate transactions in QuickBooks."
            case _ where finding.ruleID.rawValue.contains("UNCAT"):
                recommendation += "Categorize uncategorized transactions. Because: uncategorized transactions hide expense patterns and make your P&L report incomplete. Proper categorization is required for accurate profit reporting and tax planning.\n\n"
                recommendation += "ACTION: Click 'Open in QBO' to assign the correct expense or income account."
            case _ where finding.ruleID.rawValue.contains("PERSONAL"):
                recommendation += "Remove personal expenses from business accounts. Because: personal expenses reduce reported business profit and inflate tax liability. Keeping them separate ensures clean business records.\n\n"
                recommendation += "ACTION: Click 'Open in QBO' to move this to a personal account or delete it from the business books."
            case _ where finding.ruleID.rawValue.contains("NEGBAL"):
                recommendation += "Resolve negative account balance. Because: negative balances in asset accounts (like bank accounts) indicate data entry errors or categorization mistakes. They make your balance sheet inaccurate.\n\n"
                recommendation += "ACTION: Click 'Open in QBO' to investigate which transaction caused the negative balance and correct it."
            case _ where finding.ruleID.rawValue.contains("UNDEPOSITED"):
                recommendation += "Record missing bank deposit. Because: payments sitting in Undeposited Funds for too long indicate they may have been forgotten or lost in the bank. Recording the deposit ensures cash is reconciled.\n\n"
                recommendation += "ACTION: Click 'Open in QBO' to either record the deposit in the bank account or investigate if it was actually deposited."
            case _ where finding.ruleID.rawValue.contains("PRICE"):
                recommendation += "Investigate vendor price increases. Because: unexpected price hikes from key vendors impact profitability. Understanding these changes helps you budget accurately and negotiate if needed.\n\n"
                recommendation += "ACTION: Click 'Open in QBO' to verify the new price is correct, or contact the vendor if it seems wrong."
            default:
                recommendation += "Review the evidence and take action in QuickBooks. Because: this finding was flagged by Voice Ledger's rules engine as needing attention for accurate financial records.\n\n"
                recommendation += "ACTION: Click 'Open in QBO' to make the necessary correction in QuickBooks Online."
            }
            return (recommendation, nil)

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
        let queryLower = query.lowercased()
        let queryWords = queryLower
            .split(separator: " ")
            .map(String.init)
            .filter { !queryFillerWords.contains($0) }

        func scoreWords(_ text: String?) -> Double {
            guard let text, !text.isEmpty else { return 0 }
            if queryWords.isEmpty { return 0 }
            let textWords = Set(text.lowercased().split(separator: " ").map(String.init))
            let matched = queryWords.filter { textWords.contains($0) }.count
            return Double(matched) / Double(queryWords.count)
        }

        func scoreSubstring(_ text: String?) -> Double {
            guard let text, !text.isEmpty else { return 0 }
            return text.lowercased().contains(queryLower) ? 1.0 : 0
        }

        func scoreDollarAmount(_ exposure: Money) -> Double {
            // If query looks like a dollar amount, try matching against dollar exposure
            // e.g., "500" should match "USD 500.00"
            let amountStr = exposure.description
            return amountStr.contains(queryLower) ? 1.0 : 0
        }

        let scored = findings.map { finding -> (Finding, Double) in
            // Scoring: dollar amount match > substring match > word match
            let wordScore = scoreWords(finding.title)
            let substringScore = scoreSubstring(finding.title)
            let dollarScore = scoreDollarAmount(finding.dollarExposure)
            let vendorScore = scoreWords(finding.vendorName)

            let bestScore = max(dollarScore, substringScore, wordScore, vendorScore)
            return (finding, bestScore)
        }

        guard let best = scored.max(by: { $0.1 == $1.1 ? abs($0.0.dollarExposure.minorUnits) < abs($1.0.dollarExposure.minorUnits) : $0.1 < $1.1 }),
              best.1 > 0 else { return nil }
        return best.0
    }

    private static func intArgument(_ value: JSONValue?, default defaultValue: Int) -> Int {
        guard case .number(let doubleValue)? = value else { return defaultValue }
        return Int(doubleValue)
    }


    private func getFinancialSummary(metric: String, period: String) async -> (resultText: String, uiAction: VoiceUIAction?) {
        let choice: PeriodChoice = period == "prior_month" ? .priorMonth : .current
        if choice == .priorMonth, appState.priorPeriodProfitAndLossLines.isEmpty || appState.priorPeriodBalanceSheetLines.isEmpty {
            await appState.loadVarianceAnalysis()
        }
        if choice == .current, appState.balanceSheetLines.isEmpty { await appState.loadBalanceSheet() }
        if choice == .current, appState.profitAndLossLines.isEmpty { await appState.loadProfitAndLoss() }
        let data = appState.clientData
        func say(_ label: String, _ fact: Fact<Money>) -> (resultText: String, uiAction: VoiceUIAction?) {
            guard let value = fact.value else { return ("\(label) isn't available. \(fact.note ?? "") \(fact.scope.sentence())", nil) }
            return ("\(label): \(value.accountingDescription). \(fact.scope.sentence())", nil)
        }
        switch metric {
        case "net_income": return say("Net income", ClientFacts.netIncome(data, choice))
        case "revenue": return say("Revenue", ClientFacts.revenue(data, choice))
        case "cash_balance": return say("Cash balance (total bank accounts)", ClientFacts.cashBalance(data, choice))
        // Same functions and inputs as the Dashboard cards, so the spoken
        // figure always equals the card.
        case "working_capital":
            return say("Working capital", ClientFacts.workingCapital(data, choice))
        case "current_ratio", "quick_ratio":
            let lines = choice == .current ? data.balanceSheet : data.priorBalanceSheet
            let value = metric == "current_ratio" ? FinancialKPIs.currentRatio(from: lines) : FinancialKPIs.quickRatio(from: lines)
            let label = metric == "current_ratio" ? "Current ratio" : "Quick ratio"
            let sc = ClientFacts.scope(data, "the Balance Sheet", prior: choice == .priorMonth)
            guard let value else { return ("\(label) isn't available. The Balance Sheet isn't loaded for this month. \(sc.sentence())", nil) }
            return ("\(label): \(String(format: "%.2f", value)) to 1. \(sc.sentence())", nil)
        case "gross_margin", "net_margin":
            let lines = choice == .current ? data.profitAndLoss : data.priorProfitAndLoss
            let value = metric == "gross_margin" ? FinancialKPIs.grossMarginPercent(from: lines) : FinancialKPIs.netMarginPercent(from: lines)
            let label = metric == "gross_margin" ? "Gross margin" : "Net margin"
            let sc = ClientFacts.scope(data, "the Profit & Loss", prior: choice == .priorMonth)
            guard let value else { return ("\(label) isn't available. The Profit & Loss isn't loaded for this month. \(sc.sentence())", nil) }
            return ("\(label): \(String(format: "%.1f", value)) percent. \(sc.sentence())", nil)
        case "uncategorized_count":
            let count = ClientFacts.findings(data, category: .miscategorizedOrUncategorized).value?.filter { $0.ruleID.rawValue == "VL-CAT-UNCAT-001" }.count ?? 0
            return ("\(count) transaction(s) still uncategorized. \(ClientFacts.freshnessSentence(data))", nil)
        default: return ("Unknown financial metric: \(metric).", nil)
        }
    }

    /// One transaction, spoken the same way the pages show it.
    static func transactionLine(_ t: LedgerTransaction) -> String {
        "- \(ClientText.polish(t.txnDate.formatted)): \(t.vendorName ?? "Unknown") \(t.totalAmount.accountingDescription)"
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
            guard let card = InsightCards.vendorSpend(vendors, footnote: ClientFacts.freshnessSentence(appState.clientData)) else { return ("No vendor spend data available to chart for the loaded period.", nil) }
            let top = vendors[0]
            return ("Showing vendor spend for \(ClientFacts.periodLabel(appState.period)). The largest is \(top.vendorName) at \(top.total.accountingDescription).", .presentChart(.insight(card)))
        case "receivables", "payables":
            let isAR = kind == "receivables"
            if isAR && appState.agedReceivablesLines.isEmpty { await appState.loadAgedReceivables() }
            if !isAR && appState.agedPayablesLines.isEmpty { await appState.loadAgedPayables() }
            guard let card = InsightCards.aging(isAR ? appState.agedReceivablesLines : appState.agedPayablesLines, receivables: isAR, footnote: ClientFacts.freshnessSentence(appState.clientData)) else {
                return ("The aged \(isAR ? "receivables" : "payables") report has nothing open.", nil)
            }
            return ("\(isAR ? "Customers owe" : "We owe vendors") \(card.headline ?? "") on the aging report.", .presentChart(.insight(card)))
        case "cash_outlook":
            if appState.balanceSheetLines.isEmpty { await appState.loadBalanceSheet() }
            if appState.agedReceivablesLines.isEmpty { await appState.loadAgedReceivables() }
            if appState.agedPayablesLines.isEmpty { await appState.loadAgedPayables() }
            if appState.trailingPurchases.isEmpty { await appState.loadTrailingPurchases() }
            guard let f = appState.thirteenWeekForecast else { return ("Today's cash balance isn't loaded; sync first.", nil) }
            let card = InsightCards.cashOutlook(f, receivablesOver60: nil, footnote: ClientFacts.freshnessSentence(appState.clientData))
            return ("Today's cash is \(f.startingCash.accountingDescription); the lowest projected week is \(f.lowestWeek.map { "week \($0.number) at \($0.endingCash.accountingDescription)" } ?? "not available").", .presentChart(.insight(card)))
        case "revenue_trend", "net_income_trend":
            let metric: InsightCards.TrendMetric = kind == "revenue_trend" ? .revenue : .netIncome
            guard let card = InsightCards.trend(metric, monthly: appState.historySnapshot?.monthlyProfitAndLoss ?? [], focus: appState.period, footnote: ClientFacts.freshnessSentence(appState.clientData)) else {
                return ("The monthly trend needs the 24-month history; load it on Client Diagnostics.", nil)
            }
            return ("Showing \(metric == .revenue ? "revenue" : "net income") by month.", .presentChart(.insight(card)))
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
