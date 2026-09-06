import Foundation
import Core
import Voice

/// The fixed tool surface `VoiceToolLoop` offers the model — see that
/// file's own doc comment for the overall design. Every tool here is
/// either a pure lookup over already-loaded data, or triggers a REAL,
/// already-existing `AppState` method (`syncAndEvaluate`, `loadBalanceSheet`,
/// `loadFirmCockpit`, `switchActiveClient`) — this file adds no new way
/// to reach QuickBooks that didn't already exist for the on-screen UI; it
/// only exposes the same real actions to natural language.
extension VoiceEngine {
    /// Deliberately short and free of any real client data — `AskAIContext`-
    /// style context strings (grounded in real numbers) are composed
    /// SEPARATELY once a tool actually runs; this is just the model's
    /// standing instructions for the tool-decision step itself.
    static let toolLoopSystemContext = """
    You are Voice Ledger's own in-app voice assistant. You have tools that can navigate the app, look up this client's real financial data, find flagged issues, generate charts, refresh data from QuickBooks, and switch to a different connected client.

    Rules:
    - Call a tool whenever the person's request needs one. Do not just describe what you would do — call the tool.
    - If a request is genuinely ambiguous (e.g. "show me a chart" with no clear subject), ask a short clarifying question instead of guessing which tool or argument to use.
    - This app does NOT compute: accounts receivable/payable aging insights, cash runway or burn-rate forecasts, recurring-subscription detection, or missing-receipt detection. If asked about any of these, say plainly that Voice Ledger doesn't compute that yet, rather than guessing or calling an unrelated tool.
    - Financial totals (spend by vendor, revenue, cash balance) reflect only the client's CURRENTLY LOADED accounting period, not necessarily a full year or quarter — say so plainly if the person asked for a longer range than that.
    - Never invent a dollar figure, date, or vendor name that wasn't in a tool's own result.
    """

    static let toolDefinitions: [[String: JSONValue]] = [
        tool(
            name: "navigate",
            description: "Navigate to a page in the app.",
            properties: [
                "page": .object([
                    "type": .string("string"),
                    "enum": .array(VoiceDestination.allCases.map { .string($0.rawValue) }),
                    "description": .string("Which page to open.")
                ])
            ],
            required: ["page"]
        ),
        tool(
            name: "open_findings",
            description: "Open one or more specific findings/transactions by describing them (e.g. vendor name, a keyword from the title, \"the duplicate invoice\"). Pass one query to open a single finding's full detail page; pass two or more queries to open them side by side for comparison — use this whenever the person asks to see, pull up, compare, or investigate specific transactions or findings.",
            properties: [
                "queries": .object([
                    "type": .string("array"),
                    "items": .object(["type": .string("string")]),
                    "description": .string("One description per finding/transaction to open.")
                ])
            ],
            required: ["queries"]
        ),
        tool(
            name: "find_findings",
            description: "Search this client's open findings by category — use this for questions like \"find duplicates,\" \"anything miscategorized,\" \"any negative balances,\" \"possible personal expenses,\" \"late fees or overdraft charges,\" or \"vendor price increases.\" Returns a count and the matching findings; it does not open anything on screen.",
            properties: [
                "category": .object([
                    "type": .string("string"),
                    "enum": .array(["duplicates", "miscategorized_or_uncategorized", "personal_expense", "negative_balance", "late_fees_or_overdrafts", "vendor_price_increase", "all_open"].map { .string($0) }),
                    "description": .string("Which category of finding to search for.")
                ])
            ],
            required: ["category"]
        ),
        tool(
            name: "get_financial_summary",
            description: "Look up a single real financial figure for this client: net income, total revenue, current cash/bank balance, or how many transactions are still uncategorized. Fetches fresh data from QuickBooks on demand if it isn't already loaded.",
            properties: [
                "metric": .object([
                    "type": .string("string"),
                    "enum": .array(["net_income", "revenue", "cash_balance", "uncategorized_count"].map { .string($0) })
                ]),
                "period": .object([
                    "type": .string("string"),
                    "enum": .array(["current", "prior_month"].map { .string($0) }),
                    "description": .string("\"current\" is the client's currently loaded accounting period. \"prior_month\" is the single immediately-preceding month — no other historical range is available.")
                ])
            ],
            required: ["metric", "period"]
        ),
        tool(
            name: "list_vendors_by_spend",
            description: "List this client's top vendors by total spend, for THIS client's currently loaded accounting period only (not a full year or quarter).",
            properties: [
                "limit": .object(["type": .string("number"), "description": .string("How many top vendors to return, e.g. 5.")])
            ],
            required: ["limit"]
        ),
        tool(
            name: "generate_chart",
            description: "Generate and display a chart popup for this client, using real already-computed data. \"expense_drivers\" and \"pareto_cost_drivers\" chart expense categories for the loaded period; \"vendor_spend\" charts top vendors by spend for the loaded period; \"income_vs_expenses\" charts revenue vs. expenses vs. net income as a waterfall.",
            properties: [
                "kind": .object([
                    "type": .string("string"),
                    "enum": .array(["expense_drivers", "pareto_cost_drivers", "vendor_spend", "income_vs_expenses"].map { .string($0) })
                ])
            ],
            required: ["kind"]
        ),
        tool(
            name: "refresh_client_data",
            description: "Pull the latest transactions and re-check for issues from QuickBooks right now for this client. Use for \"refresh,\" \"pull the latest,\" \"sync,\" or \"check again.\"",
            properties: [:],
            required: []
        ),
        tool(
            name: "get_sync_status",
            description: "Report when this client's data was last synced from QuickBooks.",
            properties: [:],
            required: []
        ),
        tool(
            name: "list_clients_needing_attention",
            description: "Across ALL of the bookkeeper's connected clients (not just the active one), list which clients have the most open or urgent (high-severity) findings, ranked by how much attention they need — also reports when each was last synced/checked, so this is also the right tool for \"which clients haven't been synced recently\" or \"did the sync fail for anyone.\" Does not include client-specific dollar detail for OTHER clients — for that, switch to the client first.",
            properties: [
                "limit": .object(["type": .string("number"), "description": .string("How many clients to return, e.g. 3.")])
            ],
            required: []
        ),
        tool(
            name: "switch_client",
            description: "Switch the active client to a different one of the bookkeeper's connected clients by company name.",
            properties: [
                "name": .object(["type": .string("string"), "description": .string("The company name (or part of it) to switch to.")])
            ],
            required: ["name"]
        )
    ]

    private static func tool(name: String, description: String, properties: [String: JSONValue], required: [String]) -> [String: JSONValue] {
        [
            "type": .string("function"),
            "function": .object([
                "name": .string(name),
                "description": .string(description),
                "parameters": .object([
                    "type": .string("object"),
                    "properties": .object(properties),
                    "required": .array(required.map { .string($0) })
                ])
            ])
        ]
    }
}
