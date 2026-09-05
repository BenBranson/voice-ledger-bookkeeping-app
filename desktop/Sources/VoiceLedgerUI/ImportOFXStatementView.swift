import SwiftUI
import Core
import DesignSystem

/// OFX/QFX's counterpart to `ImportBankStatementView` — no column mapping
/// needed at all (OFX tags are self-describing per
/// docs/phase-0/09_INGESTION_PIPELINE.md §9.3), so the only confirm step
/// left is "which QBO account is this statement for?"
public struct ImportOFXStatementView: View {
    private let filename: String
    private let transactionCount: Int
    private let statedEndingBalance: Money?
    private let statedAsOfDate: AccountingDate?
    private let accounts: [LedgerAccount]
    /// See `ImportBankStatementView`'s identical property — `true` while
    /// `AppState.confirmOFXImport` is awaiting.
    private let isConfirming: Bool
    private let onConfirm: (_ statementAccountID: String) -> Void
    private let onCancel: () -> Void

    @State private var selectedAccountID: String?

    public init(
        filename: String,
        transactionCount: Int,
        statedEndingBalance: Money? = nil,
        statedAsOfDate: AccountingDate? = nil,
        accounts: [LedgerAccount],
        isConfirming: Bool = false,
        onConfirm: @escaping (_ statementAccountID: String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.filename = filename
        self.transactionCount = transactionCount
        self.statedEndingBalance = statedEndingBalance
        self.statedAsOfDate = statedAsOfDate
        self.accounts = accounts
        self.isConfirming = isConfirming
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VLSpacing.md) {
                Text("Import Bank Statement (OFX/QFX)")
                    .font(VLTypography.pageTitle())
                    .foregroundStyle(VLColor.textPrimary)

                Text(filename)
                    .font(VLTypography.body())
                    .foregroundStyle(VLColor.textSecondary)

                Text("\(transactionCount) transaction\(transactionCount == 1 ? "" : "s") found — OFX/QFX is self-describing, so no column mapping is needed.")
                    .font(VLTypography.caption())
                    .foregroundStyle(VLColor.textMuted)

                if let statedEndingBalance {
                    VLCard {
                        VStack(alignment: .leading, spacing: VLSpacing.xs) {
                            Text("STATEMENT'S OWN ENDING BALANCE")
                                .font(VLTypography.eyebrow())
                                .tracking(VLTypography.eyebrowTracking)
                                .foregroundStyle(VLColor.textMuted)
                            Text(statedAsOfDate.map { "\(statedEndingBalance.description) as of \($0.year)-\($0.month)-\($0.day)" } ?? statedEndingBalance.description)
                                .font(VLTypography.tabularNumericEmphasis())
                                .foregroundStyle(VLColor.textPrimary)
                            Text("This is the file's own stated balance — compare it against your bank's statement yourself before confirming. Voice Ledger does not verify it against the imported transactions.")
                                .font(VLTypography.caption())
                                .foregroundStyle(VLColor.textMuted)
                        }
                    }
                }

                VLCard {
                    VStack(alignment: .leading, spacing: VLSpacing.xs) {
                        Text("WHICH ACCOUNT IS THIS STATEMENT FOR?")
                            .font(VLTypography.eyebrow())
                            .tracking(VLTypography.eyebrowTracking)
                            .foregroundStyle(VLColor.textMuted)
                        if accounts.isEmpty {
                            Text("No accounts loaded yet — sync first, then import.")
                                .font(VLTypography.caption())
                                .foregroundStyle(VLColor.textMuted)
                        } else {
                            Picker("", selection: $selectedAccountID) {
                                Text("Select an account").tag(String?.none)
                                ForEach(accounts) { account in
                                    Text(account.name).tag(String?.some(account.id))
                                }
                            }
                            .labelsHidden()
                        }
                    }
                }

                if isConfirming {
                    HStack(spacing: VLSpacing.xs) {
                        ProgressView().controlSize(.small)
                        Text("Importing…")
                            .font(VLTypography.caption())
                            .foregroundStyle(VLColor.textMuted)
                    }
                }

                HStack {
                    Button("Cancel") { onCancel() }
                        .disabled(isConfirming)
                    Spacer()
                    Button("Confirm & Import") {
                        guard let accountID = selectedAccountID else { return }
                        onConfirm(accountID)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedAccountID == nil || isConfirming)
                }
            }
            .padding(VLSpacing.pageGutter)
        }
        .background(VLColor.background)
    }
}
