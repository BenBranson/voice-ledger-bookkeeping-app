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
    You are Voice Ledger's own in-app voice assistant. You always have the current page's context and can talk about anything displayed on screen or any of this client's financial data. You have tools that can navigate the app, look up accounts, balances, transactions and reports from the client's loaded data,  look up specific vendors or accounts, find flagged issues, generate charts, refresh data, and switch to a different connected client.

    Rules:
    - Call a tool whenever the person's request needs one. Do not just describe what you would do — call the tool.
    - When the person asks about a SPECIFIC finding or transaction by dollar amount, description, or name ("tell me about this $500," "explain the duplicate invoice," "what's the Cool Cars payment"), IMMEDIATELY call `open_findings`, passing the exact [ID: ...] of the matching finding from the lists above (match on dollar amount, age, vendor, or title). Only pass a text description if no listed ID fits. Do not ask for clarification — match against what's on the current page. If only one item matches (e.g., only one $500 finding visible), that's the answer.
    - After calling `open_findings`, explain the finding they asked about using the full context that gets injected into your next turn.
    - If a request is genuinely ambiguous with MULTIPLE matches on screen (e.g., "the $500 one" when there are three $500 findings), ask which one. But almost never — be specific and search.
    - Use `search_transactions` (an exact dollar amount like "$1,420" or a vendor/memo word), `get_account_balance`, `get_vendor_details`, `get_chart_of_accounts`, and `get_report_summary` to answer from the client's loaded data. These use the SAME calculations as the app's pages, so their figures match what the person sees on screen. Each result ends with a data-status sentence (which month, how fresh, current sync vs. 24-month history) — repeat it briefly when the person might otherwise assume more than was searched, and if it says the data is saved or not yet synced, offer to call `refresh_client_data`.
    - This app computes a cash flow forecast (`get_cash_flow_forecast`) and recurring-vendor detection (`get_recurring_vendors`) — use those tools rather than declining. It still does NOT compute: missing-receipt detection, or anything about a client not already connected. If asked about those, say plainly that Voice Ledger doesn't compute that yet, rather than guessing or calling an unrelated tool.
    - Financial totals (spend by vendor, revenue, cash balance) reflect only the client's CURRENTLY LOADED accounting period, not necessarily a full year or quarter — say so plainly if the person asked for a longer range than that.
    - Never invent a dollar figure, date, or vendor name that wasn't in a tool's own result.
    """

    static let toolDefinitions: [[String: JSONValue]] = [
        tool(
            name: "navigate",
            description: "Navigate to any page in the app: dashboard, findings, cleanup, reports, search by amount, diagnostics, pricing calculator, intake questions, and more.",
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
                    "description": .string("One entry per finding to open: preferably its exact ID from the [ID: ...] tags in context; otherwise a short description.")
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
            name: "get_cash_flow_forecast",
            description: "Report the 30/60/90-day cash flow forecast for this client: today's real cash balance, expected receivables/payables/recurring-vendor charges in each window, and the projected ending cash. A disclosed projection from real aging and recurring-vendor data — not a guess.",
            properties: [:],
            required: []
        ),
        tool(
            name: "get_recurring_vendors",
            description: "List vendors this client is charged at a consistent recurring interval and amount (detected from Purchase history), including any that are overdue for their expected next charge — useful for \"any recurring subscriptions,\" \"what are we paying for regularly,\" or \"anything that stopped charging.\"",
            properties: [:],
            required: []
        ),
        tool(
            name: "switch_client",
            description: "Switch the active client to a different one of the bookkeeper's connected clients by company name.",
            properties: [
                "name": .object(["type": .string("string"), "description": .string("The company name (or part of it) to switch to.")])
            ],
            required: ["name"]
        ),
        tool(
            name: "get_chart_of_accounts",
            description: "Get a summary of this client's chart of accounts — list all active accounts with their types (Asset, Liability, Equity, Income, Expense) and current balances. Use for \"what accounts do they have,\" \"list all assets,\" or \"show me the expense accounts.\"",
            properties: [
                "type_filter": .object([
                    "type": .string("string"),
                    "enum": .array(["all", "assets", "liabilities", "equity", "income", "expenses"].map { .string($0) }),
                    "description": .string("Filter to a specific account type, or 'all' for everything.")
                ])
            ],
            required: []
        ),
        tool(
            name: "search_transactions",
            description: "Search this client's loaded transactions (current sync plus the 24-month history when loaded) by an exact dollar amount or by vendor/memo text. An amount that equals an account's balance is explained as a balance with its postings; if no single transaction matches, it also finds 2-3 that add up to it. Does NOT filter by date range or account — for those, open the relevant report or say it isn't supported.",
            properties: [
                "query": .object([
                    "type": .string("string"),
                    "description": .string("An exact dollar amount (e.g. '$500' or '1420.00') or vendor/memo text (e.g. 'Amazon').")
                ])
            ],
            required: ["query"]
        ),
        tool(
            name: "get_account_balance",
            description: "Look up the current balance of a specific account by name (e.g. 'Checking Account,' 'Accounts Receivable,' 'Office Supplies Expense'). Fetches live data from QuickBooks if not already cached.",
            properties: [
                "account_name": .object([
                    "type": .string("string"),
                    "description": .string("The account name to look up (e.g. 'Cash,' 'Operating Expenses,' 'Sales Revenue').")
                ])
            ],
            required: ["account_name"]
        ),
        tool(
            name: "get_vendor_details",
            description: "Look up details for a specific vendor: total spend for the current period, recent transaction count, and last transaction date. Useful for investigating a vendor's spending pattern or when they last charged.",
            properties: [
                "vendor_name": .object([
                    "type": .string("string"),
                    "description": .string("The vendor name to look up (e.g. 'Acme Corp,' 'AWS,' 'AT&T').")
                ])
            ],
            required: ["vendor_name"]
        ),
        tool(
            name: "get_report_summary",
            description: "Fetch and summarize a specific financial report. \"balance_sheet\" shows assets/liabilities/equity; \"income_statement\" shows revenue/expenses/net income; \"trial_balance\" shows all accounts with debit/credit totals; \"general_ledger_summary\" shows high-level account activity; \"cash_flow\" shows cash in/out for the period.",
            properties: [
                "report_type": .object([
                    "type": .string("string"),
                    "enum": .array(["balance_sheet", "income_statement", "trial_balance", "general_ledger_summary", "cash_flow"].map { .string($0) }),
                    "description": .string("Which report to fetch.")
                ])
            ],
            required: ["report_type"]
        ),
        tool(
            name: "get_finding_recommendation",
            description: "Get a smart, reasoned recommendation for how to fix the currently-open finding. Only works when a finding detail page is displayed. Returns actionable recommendations based on the finding's rule, severity, dollar exposure, and real evidence — each recommendation explains WHY it's recommended (because x, y, z) and WHAT to do next.",
            properties: [:],
            required: []
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
