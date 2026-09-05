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

    private func jsonText(_ object: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}

enum ToolArgumentError: Error, CustomStringConvertible {
    case invalidSeverity(String)

    var description: String {
        switch self {
        case .invalidSeverity(let value):
            return "\"\(value)\" is not a valid severity — expected \"high\" or \"low\"."
        }
    }
}
