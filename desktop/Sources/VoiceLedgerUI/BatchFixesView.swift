import SwiftUI
import Core
import DesignSystem

/// docs/VOICE_LEDGER_SPEC.md Page 7 (Batch Fixes, Type A) — see
/// `Core/BatchFixPlan.swift`'s doc comment for exactly what's built (one
/// already-verified write operation applied to several findings in
/// sequence) and what isn't (any new entity/field write — those would need
/// live sandbox verification this app doesn't skip for "supported"
/// entities). Preview shows transactions affected, total dollars, old and
/// new category, and each item's reversal plan per spec — tax-period
/// consequences and before/after report impact are covered by each
/// finding's own `Consequence` list, not a separate computed projection.
public struct BatchFixesView: View {
    private let environment: VLEnvironmentTone
    private let writeAccessEnabled: Bool
    private let items: [BatchFixItem]
    private let selectedIDs: Set<String>
    private let applyingFindingIDs: Set<String>
    /// Only the MOST RECENT failure in a running batch — `AppState
    /// .applyFixError` is a single slot, not a per-finding dictionary
    /// (matching `FindingDetailView`'s single-finding-at-a-time posture),
    /// so if several selected items fail in one batch, earlier failures
    /// are overwritten here as the sequential loop proceeds. Each failure
    /// is still fully recorded in the Activity Log regardless — this is a
    /// live-display limitation only, not a data-loss one.
    private let applyFixError: (findingID: String, message: String)?
    private let isApplyingBatch: Bool
    private let onToggleSelection: (String) -> Void
    private let onSelectAll: () -> Void
    private let onDeselectAll: () -> Void
    private let onApplyBatch: () -> Void

    @State private var isConfirming = false

    public init(
        environment: VLEnvironmentTone,
        writeAccessEnabled: Bool,
        items: [BatchFixItem],
        selectedIDs: Set<String>,
        applyingFindingIDs: Set<String>,
        applyFixError: (findingID: String, message: String)?,
        isApplyingBatch: Bool,
        onToggleSelection: @escaping (String) -> Void,
        onSelectAll: @escaping () -> Void,
        onDeselectAll: @escaping () -> Void,
        onApplyBatch: @escaping () -> Void
    ) {
        self.environment = environment
        self.writeAccessEnabled = writeAccessEnabled
        self.items = items
        self.selectedIDs = selectedIDs
        self.applyingFindingIDs = applyingFindingIDs
        self.applyFixError = applyFixError
        self.isApplyingBatch = isApplyingBatch
        self.onToggleSelection = onToggleSelection
        self.onSelectAll = onSelectAll
        self.onDeselectAll = onDeselectAll
        self.onApplyBatch = onApplyBatch
    }

    private var selectedItems: [BatchFixItem] {
        items.filter { selectedIDs.contains($0.id) }
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VLSpacing.md) {
                HStack {
                    Text("Batch Fixes")
                        .font(VLTypography.pageTitle())
                        .foregroundStyle(VLColor.textPrimary)
                    Spacer()
                    VLEnvironmentBadge(environment)
                }

                Text("Applies Voice Ledger's one verified write operation — reclassifying a Purchase line's account — to several findings at once, each still individually round-trip-verified against QBO. Voice Ledger does not batch-write anything else (class, department, vendor, or other line detail): those aren't built here, since a write path only ships once it's verified against a live sandbox, never designed from documentation alone.")
                    .font(VLTypography.caption())
                    .foregroundStyle(VLColor.textMuted)

                if !writeAccessEnabled {
                    VLCard(accentRail: VLColor.violet) {
                        Text("Write access is off for this connection — enable it on the Connection page before applying any fix here.")
                            .font(VLTypography.caption())
                            .foregroundStyle(VLColor.textSecondary)
                    }
                }

                if items.isEmpty {
                    VLCard {
                        Text("No open findings currently have a verified batch fix available.")
                            .foregroundStyle(VLColor.textMuted)
                    }
                } else {
                    HStack {
                        Button("Select All") { onSelectAll() }
                        Button("Deselect All") { onDeselectAll() }
                        Spacer()
                        Text("\(selectedIDs.count) of \(items.count) selected")
                            .font(VLTypography.caption())
                            .foregroundStyle(VLColor.textMuted)
                    }

                    VLCard {
                        VStack(alignment: .leading, spacing: VLSpacing.xs) {
                            ForEach(items) { item in
                                itemRow(item)
                                if item.id != items.last?.id {
                                    Divider().overlay(VLColor.border)
                                }
                            }
                        }
                    }

                    if !selectedItems.isEmpty {
                        previewSection
                    }
                }
            }
            .padding(VLSpacing.pageGutter)
        }
        .background(VLColor.background)
    }

    private func itemRow(_ item: BatchFixItem) -> some View {
        VStack(alignment: .leading, spacing: VLSpacing.xxs) {
            HStack {
                Toggle(isOn: Binding(
                    get: { selectedIDs.contains(item.id) },
                    set: { _ in onToggleSelection(item.id) }
                )) {
                    Text(item.findingTitle)
                        .font(VLTypography.body())
                        .foregroundStyle(VLColor.textPrimary)
                }
                .toggleStyle(.checkbox)
                .disabled(isApplyingBatch)
                Spacer()
                Text(item.dollarExposure.description)
                    .font(VLTypography.tabularNumeric())
                    .foregroundStyle(VLColor.textPrimary)
            }
            HStack(spacing: VLSpacing.xs) {
                Text(item.currentAccountName)
                    .strikethrough()
                    .foregroundStyle(VLColor.textMuted)
                Text("→")
                    .foregroundStyle(VLColor.textMuted)
                Text(item.suggestedAccountName)
                    .foregroundStyle(VLColor.textSecondary)
            }
            .font(VLTypography.caption())

            if applyingFindingIDs.contains(item.findingID) {
                VLStatusPill(.reviewNeeded, label: "Applying…")
            } else if applyFixError?.findingID == item.findingID {
                Text(applyFixError?.message ?? "")
                    .font(VLTypography.caption())
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, VLSpacing.xxs)
    }

    private var previewSection: some View {
        VLCard {
            VStack(alignment: .leading, spacing: VLSpacing.sm) {
                Text("PREVIEW — BEFORE RUNNING THIS BATCH")
                    .font(VLTypography.eyebrow())
                    .tracking(VLTypography.eyebrowTracking)
                    .foregroundStyle(VLColor.textMuted)

                HStack {
                    Text("\(selectedItems.count) transaction(s) affected")
                        .font(VLTypography.body())
                        .foregroundStyle(VLColor.textPrimary)
                    Spacer()
                    Text("Total \(BatchFixPlan.totalExposure(selectedItems)?.description ?? "$0.00")")
                        .font(VLTypography.tabularNumericEmphasis())
                        .foregroundStyle(VLColor.textPrimary)
                }

                ForEach(selectedItems) { item in
                    VStack(alignment: .leading, spacing: VLSpacing.xxs) {
                        Text(item.findingTitle)
                            .font(VLTypography.caption())
                            .foregroundStyle(VLColor.textSecondary)
                        ForEach(consequenceLines(item.consequences), id: \.self) { line in
                            Text("· \(line)")
                                .font(VLTypography.caption())
                                .foregroundStyle(VLColor.textMuted)
                        }
                        Text("Reversal: \(reversalLine(item.reversal))")
                            .font(VLTypography.caption())
                            .foregroundStyle(VLColor.textMuted)
                    }
                }

                Divider().overlay(VLColor.border)

                if isConfirming {
                    Text("This sends \(selectedItems.count) real write(s) to QBO, one at a time, each independently verified. Confirm the changes above are correct.")
                        .font(VLTypography.caption())
                        .foregroundStyle(VLColor.textSecondary)
                    HStack(spacing: VLSpacing.sm) {
                        Button(isApplyingBatch ? "Applying…" : "Confirm — Apply \(selectedItems.count) Fix(es)") {
                            onApplyBatch()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isApplyingBatch)
                        Button("Cancel") { isConfirming = false }
                            .buttonStyle(.bordered)
                            .disabled(isApplyingBatch)
                    }
                } else {
                    Button("Apply Selected") { isConfirming = true }
                        .buttonStyle(.borderedProminent)
                        .disabled(!writeAccessEnabled || isApplyingBatch)
                }
            }
        }
    }

    private func consequenceLines(_ consequences: [Consequence]) -> [String] {
        consequences.map { consequence in
            switch consequence {
            case .reconciliation(let text): return "Reconciliation: \(text)"
            case .reporting(let text): return "Reporting: \(text)"
            case .auditTrail(let text): return "Audit trail: \(text)"
            }
        }
    }

    private func reversalLine(_ reversal: ReversalPlan) -> String {
        switch reversal {
        case .reversibleManually(let procedure): return procedure
        case .irreversible: return "This cannot be undone once done."
        }
    }
}
