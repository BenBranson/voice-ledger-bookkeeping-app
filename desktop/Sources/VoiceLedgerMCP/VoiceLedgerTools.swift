import Foundation
import Core
import IntegrationsQuickBooks
import DB

/// The read-only tool surface an MCP client — Claude Code/Desktop today,
/// Moneypenny's own MCP client later once it exists — can call against a
/// real, already-synced Voice Ledger client.
///
/// CLAUDE.md rule 1 ("code computes and classifies") applies here exactly
/// as it does everywhere else in this codebase: every value returned below
/// is read straight from what Voice Ledger itself already computed and
/// persisted (`ClientStore`'s findings, the backend's live health check) —
/// this process never runs a rule, never computes a dollar figure or
/// severity, and never touches QBO. There is deliberately no tool here
/// that can write anything — the same "the type can't represent a write"
/// guarantee `Voice.VoiceIntent` already gives voice commands, applied to
/// what an MCP client can ask for instead of what a spoken phrase can mean.
/// A write tool is a later, separate decision once the CrowPanel's
/// physical-authorization flow exists to gate it — not something this
/// server can quietly grow by adding a case to `call(name:arguments:)`
/// without that decision being made explicitly.
struct VoiceLedgerTools {
    let realmID: RealmID
    let environment: QBOEnvironment
    let store: ClientStore
    /// `nil` when `VOICE_LEDGER_BACKEND_URL` isn't set in this process's
    /// environment — `get_client_status` then reports local data only
    /// rather than failing the whole server, since `get_open_findings`
    /// needs no backend at all and must keep working either way.
    let backendConfiguration: BackendConfiguration?

    /// `tools/list`'s result — one entry per tool, each a plain JSON
    /// Schema `inputSchema` an MCP client (or, one hop further out, an
    /// Ollama-tools adapter translating this into Ollama's own function-
    /// calling shape) can validate arguments against before ever calling
    /// `tools/call`.
    var definitions: [[String: Any]] {
        [
            [
                "name": "get_open_findings",
                "description": "Returns this Voice Ledger client's open bookkeeping findings — title, rule ID, severity, confidence, dollar exposure, and period. Every field is real, already-computed data already synced from QuickBooks Online; this tool never generates, estimates, or recalculates a figure.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "severity": [
                            "type": "string",
                            "enum": ["high", "low"],
                            "description": "Only return findings at this severity. Omit to return every open finding."
                        ]
                    ],
                    "required": [String]()
                ]
            ],
            [
                "name": "get_client_status",
                "description": "Returns this client's QuickBooks environment (sandbox or production), a live backend connection health check, and open/high-severity finding counts.",
                "inputSchema": [
                    "type": "object",
                    "properties": [String: Any](),
                    "required": [String]()
                ]
            ],
            [
                "name": "get_cleanup_assessment_summary",
                "description": "Returns this client's Cleanup Assessment: total dollar exposure and a category-by-category breakdown (Balance Sheet Integrity, Duplicates & Unresolved Items, Categorization & Coding, Vendor & Fee Anomalies) of open findings. Scoped to exactly the rule set the Cleanup Assessment page itself evaluates — the same real, already-computed findings as get_open_findings, just grouped for scoping/pricing a cleanup engagement.",
                "inputSchema": [
                    "type": "object",
                    "properties": [String: Any](),
                    "required": [String]()
                ]
            ],
            [
                "name": "get_pricing_quote",
                "description": "Computes a monthly retainer quote, and optionally a one-time cleanup project quote, using Voice Ledger's own pricing calculator — the exact same deterministic math the Pricing Calculator page uses. This is a live calculation from the arguments given, not a lookup of a saved quote; every figure is plain arithmetic, never an AI estimate.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "hourlyRate": ["type": "number", "description": "The bookkeeper's hourly rate in dollars, e.g. 100."],
                        "volumeTier": ["type": "string", "enum": ["light", "growth", "high"], "description": "Monthly transaction volume: light = under 200/mo, growth = 200-500/mo, high = 500+/mo."],
                        "payrollProcessing": ["type": "boolean", "description": "Adds 1.5 hrs/mo. Default false."],
                        "salesTaxManagement": ["type": "boolean", "description": "Adds 1 hr/mo. Default false."],
                        "multipleBankAccounts": ["type": "boolean", "description": "5+ bank/credit accounts. Adds 1 hr/mo. Default false."],
                        "inventoryTracking": ["type": "boolean", "description": "Adds 2 hrs/mo. Default false."],
                        "needsCleanup": ["type": "boolean", "description": "Whether this client also needs a one-time historical cleanup project quoted alongside the monthly retainer. Default false."],
                        "monthsBehind": ["type": "string", "enum": ["oneToThree", "threeToSix", "sixToTwelve", "twelvePlus"], "description": "Required when needsCleanup is true."],
                        "multipleUncategorized": ["type": "boolean", "description": "Cleanup issue flag. Default false."],
                        "personalBusinessMixed": ["type": "boolean", "description": "Cleanup issue flag. Default false."],
                        "payrollNotReconciled": ["type": "boolean", "description": "Cleanup issue flag. Default false."],
                        "salesTaxNotFiled": ["type": "boolean", "description": "Cleanup issue flag. Default false."],
                        "inventoryTrackingIssues": ["type": "boolean", "description": "Cleanup issue flag. Default false."],
                        "negativeBalances": ["type": "boolean", "description": "Cleanup issue flag. Default false."],
                        "duplicatedAccounts": ["type": "boolean", "description": "Cleanup issue flag. Default false."]
                    ],
                    "required": ["hourlyRate", "volumeTier"]
                ]
            ]
        ]
    }

    /// `tools/call`'s dispatch. Every branch is independently guarded by
    /// its own `do`/`catch` inside the helper it calls — a failure in one
    /// tool (e.g. the backend being unreachable) must surface as this
    /// ONE call's `isError: true` result, never crash the server process
    /// other in-flight or future tool calls depend on.
    func call(name: String, arguments: [String: Any]) async -> [String: Any] {
        do {
            let text: String
            switch name {
            case "get_open_findings":
                text = try await getOpenFindings(severityFilter: arguments["severity"] as? String)
            case "get_client_status":
                text = try await getClientStatus()
            case "get_cleanup_assessment_summary":
                text = try await getCleanupAssessmentSummary()
            case "get_pricing_quote":
                text = try getPricingQuote(arguments: arguments)
            default:
                return toolError("Unknown tool: \(name)")
            }
            return ["content": [["type": "text", "text": text]], "isError": false]
        } catch {
            return toolError("\(error)")
        }
    }

    private func toolError(_ message: String) -> [String: Any] {
        ["content": [["type": "text", "text": message]], "isError": true]
    }

    private func getOpenFindings(severityFilter: String?) async throws -> String {
        let openFindings = try await store.loadFindings().filter { $0.status == .open }
        let filtered: [Finding]
        if let severityFilter {
            guard let severity = Severity(rawValue: severityFilter) else {
                throw ToolArgumentError.invalidSeverity(severityFilter)
            }
            filtered = openFindings.filter { $0.severity == severity }
        } else {
            filtered = openFindings
        }

        guard !filtered.isEmpty else {
            let scope = severityFilter.map { " at severity \($0)" } ?? ""
            return "No open findings\(scope) for realm \(realmID.rawValue)."
        }

        let rows: [[String: Any]] = filtered.map { finding in
            [
                "title": finding.title,
                "ruleId": finding.ruleID.rawValue,
                "severity": finding.severity.rawValue,
                "confidence": finding.confidence.rawValue,
                "dollarExposure": finding.dollarExposure.description,
                "period": "\(finding.period.year)-\(String(format: "%02d", finding.period.month))"
            ]
        }
        return try jsonText(rows)
    }

    private func getClientStatus() async throws -> String {
        let openFindings = try await store.loadFindings().filter { $0.status == .open }
        let highSeverityCount = openFindings.filter { $0.severity == .high }.count

        var status: [String: Any] = [
            "realmId": realmID.rawValue,
            "environment": environment.rawValue,
            "openFindingsCount": openFindings.count,
            "highSeverityFindingsCount": highSeverityCount
        ]

        if let backendConfiguration {
            let client = BackendClient(configuration: backendConfiguration)
            do {
                let health = try await client.healthCheck(realmID: realmID)
                status["backendHealth"] = [
                    "status": health.status.rawValue,
                    "checkedAt": ISO8601DateFormatter().string(from: health.checkedAt),
                    "latencyMs": health.latencyMs,
                    "detail": (health.detail as Any?) ?? NSNull()
                ]
            } catch {
                status["backendHealth"] = "unreachable: \(error)"
            }
        } else {
            status["backendHealth"] = "not checked — VOICE_LEDGER_BACKEND_URL is not set for this process"
        }

        return try jsonText(status)
    }

    /// Scoped to exactly `CleanupCategory.ruleIDs` — the same single
    /// source of truth the Cleanup Assessment page itself now reads
    /// (`AppState.cleanupAssessmentRuleIDs` derives from this same
    /// property; see that property's own doc comment). A finding from a
    /// rule outside this set (e.g. `VL-CAT-UNCAT-001`) is real and would
    /// show up in `get_open_findings`, but is deliberately excluded here —
    /// this tool answers "what does the cleanup engagement need to cover,"
    /// not "every open finding."
    private func getCleanupAssessmentSummary() async throws -> String {
        let openFindings = try await store.loadFindings()
            .filter { $0.status == .open && CleanupCategory.ruleIDs.contains($0.ruleID.rawValue) }

        guard !openFindings.isEmpty else {
            return "No open Cleanup Assessment findings for realm \(realmID.rawValue)."
        }

        var byCategory: [CleanupCategory: [Finding]] = [:]
        for finding in openFindings {
            byCategory[CleanupCategory.category(forRuleID: finding.ruleID.rawValue), default: []].append(finding)
        }

        let categories: [[String: Any]] = CleanupCategory.allCases
            .sorted { $0.sortOrder < $1.sortOrder }
            .compactMap { category in
                guard let findings = byCategory[category], !findings.isEmpty else { return nil }
                var entry: [String: Any] = ["category": category.label, "findingCount": findings.count]
                if let total = sumSameCurrency(findings.map(\.dollarExposure)) {
                    entry["totalExposure"] = total.description
                }
                return entry
            }

        var summary: [String: Any] = [
            "realmId": realmID.rawValue,
            "openFindingCount": openFindings.count,
            "categories": categories
        ]
        if let total = sumSameCurrency(openFindings.map(\.dollarExposure)) {
            summary["totalExposure"] = total.description
        }
        return try jsonText(summary)
    }

    /// `nil` (rather than a fabricated total) when the amounts mix
    /// currencies — same same-currency guard used throughout `Core
    /// .AskAIContext`, applied here for the same reason: summing across
    /// currencies would be meaningless, and `Money.+` itself
    /// `precondition`-traps on a mismatch rather than silently coercing.
    private func sumSameCurrency(_ amounts: [Money]) -> Money? {
        guard let first = amounts.first, amounts.allSatisfy({ $0.currency == first.currency }) else { return nil }
        return amounts.dropFirst().reduce(first) { $0 + $1 }
    }

    /// Live arithmetic from the arguments given — reuses `PricingCalculator`
    /// directly, the exact same Core module the desktop app's Pricing
    /// Calculator page calls, so this can never drift from what a
    /// bookkeeper sees on screen. Synchronous (no `store`/network access
    /// at all) since every input is supplied by the caller.
    private func getPricingQuote(arguments: [String: Any]) throws -> String {
        guard let hourlyRateDollars = (arguments["hourlyRate"] as? NSNumber)?.doubleValue else {
            throw ToolArgumentError.missingOrInvalidNumber("hourlyRate")
        }
        guard let volumeTierRaw = arguments["volumeTier"] as? String else {
            throw ToolArgumentError.missingArgument("volumeTier")
        }
        guard let volumeTier = Self.volumeTier(from: volumeTierRaw) else {
            throw ToolArgumentError.invalidEnum("volumeTier", volumeTierRaw)
        }

        let hourlyRate = Money(minorUnits: Int64((hourlyRateDollars * 100).rounded()), currency: .usd)
        let monthlyFlags = PricingCalculator.MonthlyComplexityFlags(
            payrollProcessing: arguments["payrollProcessing"] as? Bool ?? false,
            salesTaxManagement: arguments["salesTaxManagement"] as? Bool ?? false,
            multipleBankAccounts: arguments["multipleBankAccounts"] as? Bool ?? false,
            inventoryTracking: arguments["inventoryTracking"] as? Bool ?? false
        )
        let monthlyQuote = PricingCalculator.monthlyQuote(tier: volumeTier, hourlyRate: hourlyRate, flags: monthlyFlags)

        var result: [String: Any] = [
            "volumeTier": volumeTier.label,
            "baseHours": monthlyQuote.baseHours,
            "addOnHours": monthlyQuote.addOnHours,
            "totalHours": monthlyQuote.totalHours,
            "hourlyRate": hourlyRate.description,
            "monthlyInvestment": monthlyQuote.monthlyInvestment.description
        ]

        let needsCleanup = arguments["needsCleanup"] as? Bool ?? false
        if needsCleanup {
            guard let monthsBehindRaw = arguments["monthsBehind"] as? String else {
                throw ToolArgumentError.missingArgument("monthsBehind (required when needsCleanup is true)")
            }
            guard let monthsBehind = Self.monthsBehindTier(from: monthsBehindRaw) else {
                throw ToolArgumentError.invalidEnum("monthsBehind", monthsBehindRaw)
            }
            let issues = PricingCalculator.CleanupIssueFlags(
                multipleUncategorized: arguments["multipleUncategorized"] as? Bool ?? false,
                personalBusinessMixed: arguments["personalBusinessMixed"] as? Bool ?? false,
                payrollNotReconciled: arguments["payrollNotReconciled"] as? Bool ?? false,
                salesTaxNotFiled: arguments["salesTaxNotFiled"] as? Bool ?? false,
                inventoryTrackingIssues: arguments["inventoryTrackingIssues"] as? Bool ?? false,
                negativeBalances: arguments["negativeBalances"] as? Bool ?? false,
                duplicatedAccounts: arguments["duplicatedAccounts"] as? Bool ?? false
            )
            let cleanupQuote = PricingCalculator.cleanupQuote(monthsBehind: monthsBehind, volumeTier: volumeTier, hourlyRate: hourlyRate, issues: issues)
            let combined = PricingCalculator.CombinedProposal(cleanup: cleanupQuote, monthly: monthlyQuote)

            result["cleanupProject"] = [
                "monthsBehind": monthsBehind.label,
                "issueCount": cleanupQuote.issueCount,
                "low": cleanupQuote.low.description,
                "high": cleanupQuote.high.description,
                "midpoint": cleanupQuote.midpoint.description
            ]
            result["dayOneTotal"] = combined.dayOneTotal.description
        }

        return try jsonText(result)
    }

    private static func volumeTier(from raw: String) -> PricingCalculator.VolumeTier? {
        switch raw {
        case "light": return .light
        case "growth": return .growth
        case "high": return .high
        default: return nil
        }
    }

    private static func monthsBehindTier(from raw: String) -> PricingCalculator.MonthsBehindTier? {
        switch raw {
        case "oneToThree": return .oneToThree
        case "threeToSix": return .threeToSix
        case "sixToTwelve": return .sixToTwelve
        case "twelvePlus": return .twelvePlus
        default: return nil
        }
    }

    private func jsonText(_ object: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}

enum ToolArgumentError: Error, CustomStringConvertible {
    case invalidSeverity(String)
    case missingArgument(String)
    case missingOrInvalidNumber(String)
    case invalidEnum(String, String)

    var description: String {
        switch self {
        case .invalidSeverity(let value):
            return "\"\(value)\" is not a valid severity — expected \"high\" or \"low\"."
        case .missingArgument(let name):
            return "Missing required argument: \(name)."
        case .missingOrInvalidNumber(let name):
            return "\(name) is required and must be a number."
        case .invalidEnum(let name, let value):
            return "\"\(value)\" is not a valid value for \(name)."
        }
    }
}
