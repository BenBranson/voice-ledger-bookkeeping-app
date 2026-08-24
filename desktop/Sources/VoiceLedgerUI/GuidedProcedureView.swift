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
    @State private var note: String = ""
    private let onAttest: (String?) -> Void
    private let onCancel: () -> Void

    public init(procedure: GuidedProcedure, attestError: String? = nil, onAttest: @escaping (String?) -> Void, onCancel: @escaping () -> Void) {
        self.procedure = procedure
        self.attestError = attestError
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
                                Text("\(index + 1).")
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
                        TextField("Optional note", text: $note, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                        if let attestError {
                            Text(attestError)
                                .font(VLTypography.caption())
                                .foregroundStyle(.red)
                        }
                        HStack(spacing: VLSpacing.sm) {
                            Button("I completed this in QBO") {
                                onAttest(note.isEmpty ? nil : note)
                            }
                            .buttonStyle(.borderedProminent)
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
