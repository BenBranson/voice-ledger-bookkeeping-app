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

    @State private var query = ""

    public init(environment: VLEnvironmentTone, transactions: [LedgerTransaction], accounts: [LedgerAccount]) {
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

                Text("Searches every transaction from the last sync for an exact dollar amount — useful for spotting a duplicate posting, a split payment across accounts, or comparing two transactions you suspect share a typo. Matches a positive and negative amount of the same size together (e.g. a charge and its refund), since either direction can be the one worth a second look.")
                    .font(VLTypography.caption())
                    .foregroundStyle(VLColor.textMuted)

                TextField("Amount (e.g. 142.50)", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 260)

                if !query.trimmingCharacters(in: .whitespaces).isEmpty && parsedAmount == nil {
                    Text("Not a recognizable dollar amount — try something like 142.50 or 142.")
                        .font(VLTypography.caption())
                        .foregroundStyle(.red)
                } else if let parsedAmount {
                    VLCard {
                        VStack(alignment: .leading, spacing: VLSpacing.sm) {
                            HStack {
                                Text("\(matches.count) MATCH\(matches.count == 1 ? "" : "ES") FOR \(parsedAmount.description)")
                                    .font(VLTypography.eyebrow())
                                    .tracking(VLTypography.eyebrowTracking)
                                    .foregroundStyle(VLColor.textMuted)
                                Spacer()
                            }
                            if matches.isEmpty {
                                Text("No transactions from the last sync match this amount.")
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
                }
            }
            .padding(VLSpacing.pageGutter)
        }
        .background(VLColor.background)
    }

    private func row(_ transaction: LedgerTransaction) -> some View {
        VStack(alignment: .leading, spacing: VLSpacing.xxs) {
            HStack {
                Text(transaction.vendorName ?? "(no vendor)")
                    .font(VLTypography.body())
                    .foregroundStyle(VLColor.textPrimary)
                Spacer()
                Text(transaction.totalAmount.description)
                    .font(VLTypography.tabularNumeric())
                    .foregroundStyle(VLColor.textPrimary)
            }
            HStack(spacing: VLSpacing.sm) {
                Text(transaction.txnDate.formatted)
                Text("·")
                Text(transaction.entityKind.rawValue)
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
