import SwiftUI
import Core
import DesignSystem

/// docs/phase-0/11_VERTICAL_SLICE.md §11.4's guided-procedure block, made
/// interactive: steps, pitfalls, done criteria, then an attestation form.
/// This replaces the staging-queue view Branch A would have needed — there
/// is no staging state to show in Branch B (§11.1).
public struct GuidedProcedureView: View {
    private let procedure: GuidedProcedure
    /// Gauntlet Loop, Gauntlet B round 15 (2026-08-24): `AppState
    /// .attestCompletion` used to navigate back to the finding's list
    /// unconditionally, even when the underlying write threw — the
    /// bookkeeper believed their attestation was recorded when it wasn't.
    /// Now the caller stays on this screen and shows this instead.
    private let attestError: String?
    /// Gauntlet Loop, Gauntlet B round 18 (2026-08-24): `attestCompletion`
    /// had no in-flight marker, so this button had nothing to disable — a
    /// rapid double-tap fired two concurrent calls, producing two
    /// `manualCompletionAttested` Activity Log entries for one click.
    private let isAttesting: Bool
    @State private var note: String = ""
    /// Owner directive (2026-08-29): "for every finding I can mark what I
    /// did to resolve it" — same category picker as `FindingDetailView`'s
    /// fast "Mark as Done" path, combined via `ResolutionType.combinedNote`
    /// into the same `note` this attestation already sends.
    @State private var resolutionType: ResolutionType?
    private let onAttest: (String?) -> Void
    private let onCancel: () -> Void

    public init(procedure: GuidedProcedure, attestError: String? = nil, isAttesting: Bool = false, onAttest: @escaping (String?) -> Void, onCancel: @escaping () -> Void) {
        self.procedure = procedure
        self.attestError = attestError
        self.isAttesting = isAttesting
        self.onAttest = onAttest
        self.onCancel = onCancel
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VLSpacing.md) {
                Text("Complete this in QuickBooks Online")
                    .font(VLTypography.pageTitle())
                    .foregroundStyle(VLColor.textPrimary)

                VLCard {
                    VStack(alignment: .leading, spacing: VLSpacing.sm) {
                        Text("STEPS")
                            .font(VLTypography.eyebrow())
                            .tracking(VLTypography.eyebrowTracking)
                            .foregroundStyle(VLColor.textMuted)
                        ForEach(Array(procedure.steps.enumerated()), id: \.offset) { index, step in
                            HStack(alignment: .top, spacing: VLSpacing.xs) {
                                Text(verbatim: "\(index + 1).")
                                    .foregroundStyle(VLColor.textMuted)
                                Text(step)
                                    .foregroundStyle(VLColor.textPrimary)
                            }
                            .font(VLTypography.body())
                        }
                    }
                }

                if !procedure.pitfalls.isEmpty {
                    VLCard(accentRail: VLColor.violet) {
                        VStack(alignment: .leading, spacing: VLSpacing.xs) {
                            Text("PITFALLS")
                                .font(VLTypography.eyebrow())
                                .tracking(VLTypography.eyebrowTracking)
                                .foregroundStyle(VLColor.textMuted)
                            ForEach(procedure.pitfalls, id: \.self) { pitfall in
                                Text("• \(pitfall)")
                                    .font(VLTypography.caption())
                                    .foregroundStyle(VLColor.textSecondary)
                            }
                        }
                    }
                }

                VLCard {
                    VStack(alignment: .leading, spacing: VLSpacing.sm) {
                        Text("DONE WHEN")
                            .font(VLTypography.eyebrow())
                            .tracking(VLTypography.eyebrowTracking)
                            .foregroundStyle(VLColor.textMuted)
                        Text(procedure.doneCriteria)
                            .font(VLTypography.body())
                            .foregroundStyle(VLColor.textPrimary)
                    }
                }

                VLCard {
                    VStack(alignment: .leading, spacing: VLSpacing.sm) {
                        Text("ATTESTATION")
                            .font(VLTypography.eyebrow())
                            .tracking(VLTypography.eyebrowTracking)
                            .foregroundStyle(VLColor.textMuted)
                        Text("I completed the steps above in QuickBooks Online.")
                            .font(VLTypography.body())
                            .foregroundStyle(VLColor.textPrimary)
                        Text("This records your attestation — it does not verify the result. The finding only resolves once the next sync confirms the change in QBO.")
                            .font(VLTypography.caption())
                            .foregroundStyle(VLColor.textMuted)
                        // Owner directive (2026-08-29): "the finding isn't
                        // resolved until I click or type in what I did to
                        // resolve it, the click could be like a dropdown
                        // list where I click on something like matched" —
                        // a category or a typed note, either is enough, but
                        // one of them is now required before this button
                        // will fire.
                        Text("What did you do? Pick a category, or type it out — the Client Value Report will quote this back to show your work.")
                            .font(VLTypography.caption())
                            .foregroundStyle(VLColor.textSecondary)
                        Picker("Type", selection: $resolutionType) {
                            Text("Choose a category (optional)").tag(ResolutionType?.none)
                            ForEach(ResolutionType.allCases) { type in
                                Text(type.label).tag(ResolutionType?.some(type))
                            }
                        }
                        .labelsHidden()
                        TextField("Or type what you did", text: $note, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                        if let attestError {
                            Text(attestError)
                                .font(VLTypography.caption())
                                .foregroundStyle(.red)
                        }
                        HStack(spacing: VLSpacing.sm) {
                            Button("I completed this in QBO") {
                                onAttest(ResolutionType.combinedNote(type: resolutionType, detail: note))
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isAttesting || (resolutionType == nil && note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
                            Button("Cancel") { onCancel() }
                                .buttonStyle(.bordered)
                        }
                    }
                }
            }
            .padding(VLSpacing.pageGutter)
        }
        .background(VLColor.background)
    }
}
