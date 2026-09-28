import Foundation

/// A point-in-time local copy of everything the Dashboard's own sync
/// (`AppState.syncDashboard`) fetches from QuickBooks Online — accounts,
/// transactions, and the two reports the dashboard's KPI cards are built
/// from. Persisted per-realm in `ClientStore` and re-saved on every
/// dashboard sync.
///
/// **Why this exists at all:** `voiceledger-mcp`'s `get_chart_of_accounts`,
/// `get_recent_transactions`, and `get_financial_summary` tools need
/// something to read without a live backend connection — the physical
/// panel/voice-assistant integration (Talking Buddy) has no session-token
/// lifecycle of its own and shouldn't need one just to answer "what's my
/// cash balance." Owner directive (2026-09-28): read the same locally-
/// synced data `get_open_findings`/`get_finding_details` already do,
/// rather than requiring `VOICE_LEDGER_BACKEND_URL` for these three too.
///
/// **The honesty trade-off, stated plainly (not hidden):** this is only as
/// fresh as the last time someone opened the desktop app and synced the
/// Dashboard. `syncedAt` is carried through to every MCP tool that reads
/// this snapshot specifically so a caller can say "as of the last sync,
/// two hours ago" rather than silently presenting possibly-stale account
/// balances or transaction activity as if they were live. This is a
/// deliberately different posture from `Finding`/`ActivityLog`, which are
/// legitimately cache-forever workpaper artifacts, not live account state.
public struct FinancialSnapshot: Codable, Sendable {
    public let syncedAt: Date
    public let accounts: [LedgerAccount]
    public let transactions: [LedgerTransaction]
    public let balanceSheetLines: [ReportLine]
    public let profitAndLossLines: [ReportLine]

    public init(syncedAt: Date, accounts: [LedgerAccount], transactions: [LedgerTransaction], balanceSheetLines: [ReportLine], profitAndLossLines: [ReportLine]) {
        self.syncedAt = syncedAt
        self.accounts = accounts
        self.transactions = transactions
        self.balanceSheetLines = balanceSheetLines
        self.profitAndLossLines = profitAndLossLines
    }
}
