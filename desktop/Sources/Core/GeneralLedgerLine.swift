import Foundation

/// docs/VOICE_LEDGER_SPEC.md Page 12. `GeneralLedger` — verified live
/// 2026-08-18. Not a label+amount section tree like BalanceSheet/P&L/
/// CashFlow, and not a debit/credit or aging-bucket table either: it's a
/// transaction-level ledger, grouped by account, 8 real columns (Date,
/// Transaction Type, Num, Name, Memo/Description, Split, Amount, Balance).
/// Each account section opens with a synthetic "Beginning Balance" row
/// (its `balance` is the account's opening balance for the period, all
/// other fields blank) followed by one row per posted transaction, closed
/// by a `Summary` "Total for <Account>" row. Leaf rows here ARE tagged
/// `"type": "Data"` (unlike Trial Balance/Aging), so `flattenGeneralLedger`
/// gates on that like `flatten` does for the other section-tree reports —
/// it's the column shape that's different, not the leaf-detection rule.
public struct GeneralLedgerLine: Identifiable, Hashable, Sendable {
    public let id: String
    /// The account name for a section header row; `"Beginning Balance"` or
    /// a real transaction date (`"2026-07-31"`) for a leaf row; `"Total for
    /// <Account>"` for a section's closing Summary row.
    public let label: String
    public let transactionType: String?
    public let docNumber: String?
    public let name: String?
    public let memo: String?
    public let split: String?
    public let amount: Money?
    public let balance: Money?
    public let depth: Int
    public let isSummary: Bool
    /// True only for the section's own opening row (`label` is the account
    /// name) — set explicitly by the decoder rather than inferred by the
    /// view from "no transactionType and depth 0," which would be a fragile
    /// heuristic a future column addition could silently break.
    public let isAccountHeader: Bool
    /// QBO transaction Id from the Transaction Type column, for a link
    /// straight to that transaction in QBO.
    public let transactionID: String?

    public init(
        label: String,
        transactionType: String?,
        docNumber: String?,
        name: String?,
        memo: String?,
        split: String?,
        amount: Money?,
        balance: Money?,
        depth: Int,
        isSummary: Bool,
        isAccountHeader: Bool = false,
        transactionID: String? = nil
    ) {
        self.transactionID = transactionID
        self.id = "\(depth)-\(label)-\(isSummary)-\(UUID().uuidString.prefix(8))"
        self.label = label
        self.transactionType = transactionType
        self.docNumber = docNumber
        self.name = name
        self.memo = memo
        self.split = split
        self.amount = amount
        self.balance = balance
        self.depth = depth
        self.isSummary = isSummary
        self.isAccountHeader = isAccountHeader
    }
}
