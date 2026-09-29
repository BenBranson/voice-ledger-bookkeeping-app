import SwiftUI
import Core
import DesignSystem

/// Owner directive (2026-08-31): "search for a specific dollar amount and
/// it brings back all the transactions that are that amount, so I can
/// pinpoint matches or duplicates or miscategorized transactions." Searches
/// `transactions` — already synced, already in memory — client-side, with
/// no new QBO call. See `AmountSearch` (Core) for the exact-cents matching
/// itself; this view only renders whatever it's handed.
public struct AmountSearchView: View {
    private let environment: VLEnvironmentTone
    private let transactions: [LedgerTransaction]
    private let accounts: [LedgerAccount]
    /// What was searched, e.g. "the last sync (Jul 2026) and 24-month history".
    private let scopeDescription: String
    private let hasHistory: Bool
    private let isSynced: Bool
    private let onSync: (() -> Void)?
    private let onLoadHistory: (() -> Void)?
    private let qboURL: ((LedgerTransaction) -> URL?)?

    @State private var query = ""

    public init(environment: VLEnvironmentTone, transactions: [LedgerTransaction], accounts: [LedgerAccount],
                scopeDescription: String = "the last sync", hasHistory: Bool = false, isSynced: Bool = true,
                onSync: (() -> Void)? = nil, onLoadHistory: (() -> Void)? = nil, qboURL: ((LedgerTransaction) -> URL?)? = nil) {
        self.scopeDescription = scopeDescription
        self.hasHistory = hasHistory
        self.isSynced = isSynced
        self.onSync = onSync
        self.onLoadHistory = onLoadHistory
        self.qboURL = qboURL
        self.environment = environment
        self.transactions = transactions
        self.accounts = accounts
    }

    private var parsedAmount: Money? {
        AmountSearch.parseAmount(query)
    }

    private var matches: [LedgerTransaction] {
        guard let parsedAmount else { return [] }
        return AmountSearch.findTransactions(matching: parsedAmount, in: transactions)
            .sorted { $0.txnDate < $1.txnDate }
    }

    private var balanceAccounts: [LedgerAccount] {
        guard let parsedAmount else { return [] }
        return AmountSearch.accountsWithBalance(parsedAmount, in: accounts)
    }

    private var combination: [LedgerTransaction]? {
        guard let parsedAmount, matches.isEmpty else { return nil }
        return AmountSearch.combination(matching: parsedAmount, in: transactions)
    }

    private func accountName(_ accountID: String?) -> String {
        guard let accountID else { return "—" }
        return accounts.first { $0.id == accountID }?.name ?? accountID
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VLSpacing.md) {
                HStack {
                    Text("Search by Amount")
                        .font(VLTypography.pageTitle())
                        .foregroundStyle(VLColor.textPrimary)
                    Spacer()
                    VLEnvironmentBadge(environment)
                }

                Text("Searches every loaded transaction for an exact dollar amount — useful for spotting a duplicate posting, a split payment across accounts, or comparing two transactions you suspect share a typo. Matches a positive and negative amount of the same size together (e.g. a charge and its refund), since either direction can be the one worth a second look.")
                    .font(VLTypography.caption())
                    .foregroundStyle(VLColor.textMuted)

                TextField("Amount (e.g. 142.50)", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 260)

                HStack(spacing: VLSpacing.sm) {
                    Text(transactions.isEmpty ? "Nothing loaded to search yet." : "Searching \(transactions.count.formatted()) transactions from \(scopeDescription).")
                        .font(VLTypography.caption())
                        .foregroundStyle(transactions.isEmpty ? .orange : VLColor.textMuted)
                    if !isSynced, let onSync { Button("Sync now", action: onSync).controlSize(.small) }
                    if !hasHistory, let onLoadHistory { Button("Load 24-month history", action: onLoadHistory).controlSize(.small) }
                }
                if !hasHistory {
                    Text("Only the current month is searched until the 24-month history is loaded — an older transaction (like one from March) won't be found.")
                        .font(VLTypography.caption())
                        .foregroundStyle(VLColor.textMuted)
                }

                if !query.trimmingCharacters(in: .whitespaces).isEmpty && parsedAmount == nil {
                    Text("Not a recognizable dollar amount — try something like 142.50 or 142.")
                        .font(VLTypography.caption())
                        .foregroundStyle(.red)
                } else if let parsedAmount {
                    VLCard {
                        VStack(alignment: .leading, spacing: VLSpacing.sm) {
                            HStack {
                                Text(verbatim: "\(matches.count) MATCH\(matches.count == 1 ? "" : "ES") FOR \(parsedAmount.accountingDescription)")
                                    .font(VLTypography.eyebrow())
                                    .tracking(VLTypography.eyebrowTracking)
                                    .foregroundStyle(VLColor.textMuted)
                                Spacer()
                            }
                            if matches.isEmpty && (!balanceAccounts.isEmpty || combination != nil) {
                                Text("No single transaction is this amount — but see below.")
                                    .font(VLTypography.caption())
                                    .foregroundStyle(VLColor.textMuted)
                            } else if matches.isEmpty {
                                Text(transactions.isEmpty ? "Nothing to search yet — sync first." : "No transaction for this exact amount in \(scopeDescription). Account balances (like a clearing account's total) aren't transactions, so they won't match unless a single transaction had that amount.")
                                    .font(VLTypography.caption())
                                    .foregroundStyle(VLColor.textMuted)
                            } else {
                                ForEach(matches) { transaction in
                                    row(transaction)
                                    if transaction.id != matches.last?.id {
                                        Divider().overlay(VLColor.border)
                                    }
                                }
                            }
                        }
                    }
                    ForEach(balanceAccounts, id: \.id) { account in
                        balanceCard(account, amount: parsedAmount)
                    }
                    if let combination {
                        VLCard(accentRail: VLColor.violet) {
                            VStack(alignment: .leading, spacing: VLSpacing.sm) {
                                Text(verbatim: "\(combination.count) TRANSACTIONS THAT ADD UP TO \(parsedAmount.accountingDescription)")
                                    .font(VLTypography.eyebrow()).tracking(VLTypography.eyebrowTracking).foregroundStyle(VLColor.violet)
                                Text("Possibly one payment split into parts, or a total posted as pieces. This is a match on amounts only — check before relying on it.")
                                    .font(VLTypography.caption()).foregroundStyle(VLColor.textMuted)
                                ForEach(combination) { row($0) }
                            }
                        }
                    }
                }
            }
            .padding(VLSpacing.pageGutter)
        }
        .background(VLColor.background)
    }

    private func balanceCard(_ account: LedgerAccount, amount: Money) -> some View {
        let postings = AmountSearch.transactions(for: account, in: transactions)
        let register = qboURL.flatMap { make in
            // Reuse the transaction link's base to reach the account register.
            postings.first.flatMap(make).map { url -> URL in
                var parts = url.absoluteString.components(separatedBy: "/app/")
                parts[parts.count - 1] = "register?accountId=\(account.id)"
                return URL(string: parts.joined(separator: "/app/")) ?? url
            }
        }
        return VLCard(accentRail: VLColor.cyan) {
            VStack(alignment: .leading, spacing: VLSpacing.sm) {
                HStack {
                    Text(verbatim: "THIS IS THE BALANCE OF \(account.name.uppercased())")
                        .font(VLTypography.eyebrow()).tracking(VLTypography.eyebrowTracking).foregroundStyle(VLColor.cyan)
                    Spacer()
                    if let register {
                        Link(destination: register) { Label("Open account in QBO", systemImage: "arrow.up.right.square") }.font(VLTypography.caption())
                    }
                }
                Text("\(account.name) currently shows \(account.currentBalance.accountingDescription). A balance is the running total of many postings, so no single transaction matches it. \(postings.isEmpty ? "No postings to this account are in the loaded data — load the 24-month history to see them." : "The \(postings.count) posting\(postings.count == 1 ? "" : "s") paid from or into it in the loaded data:")")
                    .font(VLTypography.caption()).foregroundStyle(VLColor.textSecondary)
                ForEach(postings.suffix(25)) { transaction in
                    row(transaction)
                    Divider().overlay(VLColor.border)
                }
                if postings.count > 25 {
                    Text("Showing the latest 25 of \(postings.count).").font(VLTypography.caption()).foregroundStyle(VLColor.textMuted)
                }
                if !postings.isEmpty {
                    let total = postings.map(\.totalAmount).reduce(Money.zero, +)
                    Text("These postings total \(total.accountingDescription)\(total.minorUnits == abs(account.currentBalance.minorUnits) ? " — they account for the whole balance." : "; the rest of the balance comes from activity not in the loaded data (e.g. deposits, transfers, or journal entries).")")
                        .font(VLTypography.caption()).foregroundStyle(VLColor.textMuted)
                }
            }
        }
    }

    static func kindLabel(_ kind: QBOEntityKind) -> String {
        switch kind {
        case .purchase: return "Expense"
        case .billPayment: return "Bill payment"
        case .journalEntry: return "Journal entry"
        case .vendorCredit: return "Vendor credit"
        case .payment: return "Customer payment"
        case .importedBankStatementLine: return "Imported statement line"
        default:
            let spaced = kind.rawValue.replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
            return spaced.prefix(1).uppercased() + spaced.dropFirst().lowercased()
        }
    }

    private func row(_ transaction: LedgerTransaction) -> some View {
        VStack(alignment: .leading, spacing: VLSpacing.xxs) {
            HStack {
                Text(transaction.vendorName ?? "(no vendor)")
                    .font(VLTypography.body())
                    .foregroundStyle(VLColor.textPrimary)
                Spacer()
                Text(transaction.totalAmount.accountingDescription)
                    .font(VLTypography.tabularNumeric())
                    .foregroundStyle(VLColor.textPrimary)
                if let url = qboURL?(transaction) {
                    Link(destination: url) { Label("Open in QBO", systemImage: "arrow.up.right.square") }
                        .font(VLTypography.caption())
                }
            }
            HStack(spacing: VLSpacing.sm) {
                Text(ClientText.polish(transaction.txnDate.formatted))
                Text("·")
                Text(Self.kindLabel(transaction.entityKind))
                Text("·")
                Text(accountName(transaction.paymentAccountID))
                if transaction.isVoided {
                    Text("·")
                    Text("VOIDED")
                }
            }
            .font(VLTypography.caption())
            .foregroundStyle(VLColor.textMuted)
        }
    }
}
