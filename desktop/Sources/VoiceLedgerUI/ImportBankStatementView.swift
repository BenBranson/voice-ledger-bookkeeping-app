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
    private let onConfirm: ([ColumnMapping]) -> Void
    private let onCancel: () -> Void

    @State private var selections: [MappedField]

    public init(filename: String, columns: [ColumnPreview], onConfirm: @escaping ([ColumnMapping]) -> Void, onCancel: @escaping () -> Void) {
        self.filename = filename
        self.columns = columns
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        self._selections = State(initialValue: Array(repeating: .unmapped, count: columns.count))
    }

    private var canImport: Bool {
        selections.contains(.date) && selections.contains(.amount)
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
                    Text("Assign both a Date column and an Amount column to continue.")
                        .font(VLTypography.caption())
                        .foregroundStyle(VLColor.textMuted)
                }

                HStack {
                    Button("Cancel") { onCancel() }
                    Spacer()
                    Button("Confirm & Import") {
                        let mappings = columns.enumerated().compactMap { index, column -> ColumnMapping? in
                            let field = selections[index]
                            guard field != .unmapped else { return nil }
                            return ColumnMapping(sourceColumn: column.index, sourceHeader: column.header, target: field, origin: .userSpecified, confirmed: true)
                        }
                        onConfirm(mappings)
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
