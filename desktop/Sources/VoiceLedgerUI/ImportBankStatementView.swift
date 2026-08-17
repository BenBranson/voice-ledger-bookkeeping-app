import SwiftUI
import Core
import DesignSystem

/// docs/phase-0/09_INGESTION_PIPELINE.md §9.4: "column mapping with a
/// confirm-and-correct step, never a silent guess." The minimal real
/// version of that screen — one `Picker` per CSV column, defaulting every
/// column to `.unmapped` (never a suggested guess pre-selected as if
/// confirmed), Import disabled until `.date` and `.amount` are both
/// assigned. No learned-mapping suggestions yet (stage 6) — every import
/// starts from a blank slate.
public struct ImportBankStatementView: View {
    public struct ColumnPreview: Identifiable {
        public let index: Int
        public let header: String
        public let sampleValues: [String]
        public var id: Int { index }

        public init(index: Int, header: String, sampleValues: [String]) {
            self.index = index
            self.header = header
            self.sampleValues = sampleValues
        }
    }

    private let filename: String
    private let columns: [ColumnPreview]
    /// The client's chart of accounts (from the last sync) — you declare
    /// which one this statement is FOR; it is never inferred from the
    /// file. Required for `VL-RECON-MISSING-001`/`VL-VENDOR-MISMATCH-001`
    /// to compare an imported line against the right posted transactions
    /// at all (both match on `paymentAccountID`).
    private let accounts: [LedgerAccount]
    private let onConfirm: ([ColumnMapping], _ statementAccountID: String) -> Void
    private let onCancel: () -> Void

    @State private var selections: [MappedField]
    @State private var selectedAccountID: String?

    public init(
        filename: String,
        columns: [ColumnPreview],
        accounts: [LedgerAccount],
        onConfirm: @escaping ([ColumnMapping], _ statementAccountID: String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.filename = filename
        self.columns = columns
        self.accounts = accounts
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        self._selections = State(initialValue: Array(repeating: .unmapped, count: columns.count))
        self._selectedAccountID = State(initialValue: nil)
    }

    private var canImport: Bool {
        selections.contains(.date) && selections.contains(.amount) && selectedAccountID != nil
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VLSpacing.md) {
                Text("Import Bank Statement")
                    .font(VLTypography.pageTitle())
                    .foregroundStyle(VLColor.textPrimary)

                Text(filename)
                    .font(VLTypography.body())
                    .foregroundStyle(VLColor.textSecondary)

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

                Text("Assign each column below, then confirm. Nothing is guessed for you — an unmapped column is skipped, not silently dropped.")
                    .font(VLTypography.caption())
                    .foregroundStyle(VLColor.textMuted)

                VLCard {
                    VStack(alignment: .leading, spacing: VLSpacing.sm) {
                        ForEach(columns) { column in
                            HStack {
                                VStack(alignment: .leading, spacing: VLSpacing.xxs) {
                                    Text(column.header)
                                        .font(VLTypography.body())
                                        .foregroundStyle(VLColor.textPrimary)
                                    Text(column.sampleValues.joined(separator: " · "))
                                        .font(VLTypography.caption())
                                        .foregroundStyle(VLColor.textMuted)
                                }
                                Spacer()
                                Picker("", selection: Binding(
                                    get: { selections[column.index] },
                                    set: { selections[column.index] = $0 }
                                )) {
                                    Text("Unmapped").tag(MappedField.unmapped)
                                    Text("Date").tag(MappedField.date)
                                    Text("Description").tag(MappedField.description)
                                    Text("Amount").tag(MappedField.amount)
                                    Text("Reference #").tag(MappedField.referenceNumber)
                                    Text("Ignore").tag(MappedField.ignored)
                                }
                                .labelsHidden()
                                .frame(width: 160)
                            }
                            if column.index != columns.count - 1 {
                                Divider().overlay(VLColor.border)
                            }
                        }
                    }
                }

                if !canImport {
                    Text("Select an account, and assign both a Date column and an Amount column, to continue.")
                        .font(VLTypography.caption())
                        .foregroundStyle(VLColor.textMuted)
                }

                HStack {
                    Button("Cancel") { onCancel() }
                    Spacer()
                    Button("Confirm & Import") {
                        guard let accountID = selectedAccountID else { return }
                        let mappings = columns.enumerated().compactMap { index, column -> ColumnMapping? in
                            let field = selections[index]
                            guard field != .unmapped else { return nil }
                            return ColumnMapping(sourceColumn: column.index, sourceHeader: column.header, target: field, origin: .userSpecified, confirmed: true)
                        }
                        onConfirm(mappings, accountID)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canImport)
                }
            }
            .padding(VLSpacing.pageGutter)
        }
        .background(VLColor.background)
    }
}
