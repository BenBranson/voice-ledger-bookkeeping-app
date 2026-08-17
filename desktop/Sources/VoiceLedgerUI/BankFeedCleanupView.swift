import SwiftUI
import Core
import DesignSystem

/// docs/VOICE_LEDGER_SPEC.md Page 4 (Type B): "analyzes posted QBO activity
/// and compares it against your imported CSV/OFX/QFX statement; detects
/// duplicates and missing postings." **Minimal slice**: only
/// `VL-RECON-MISSING-001` (missing postings), CSV only (no OFX/QFX/Excel),
/// no drag-and-drop (file picker only), no cross-foot validation (§9.5).
/// The confirm-and-correct column-mapping step (§9.4) is real —
/// `ImportBankStatementView`, presented by the app layer after
/// `onImportTapped` picks a file.
public struct BankFeedCleanupView: View {
    private let environment: VLEnvironmentTone
    private let coverageStatus: VLStatus
    private let missingPostingOutcomeDetail: String
    private let findings: [Finding]
    private let importError: String?
    private let onSelectFinding: (Finding) -> Void
    private let onImportTapped: () -> Void

    public init(
        environment: VLEnvironmentTone,
        coverageStatus: VLStatus,
        missingPostingOutcomeDetail: String,
        findings: [Finding],
        importError: String?,
        onSelectFinding: @escaping (Finding) -> Void,
        onImportTapped: @escaping () -> Void
    ) {
        self.environment = environment
        self.coverageStatus = coverageStatus
        self.missingPostingOutcomeDetail = missingPostingOutcomeDetail
        self.findings = findings
        self.importError = importError
        self.onSelectFinding = onSelectFinding
        self.onImportTapped = onImportTapped
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VLSpacing.md) {
                HStack {
                    Text("Bank Feed Cleanup")
                        .font(VLTypography.pageTitle())
                        .foregroundStyle(VLColor.textPrimary)
                    Spacer()
                    VLEnvironmentBadge(environment)
                }

                Text("Type B — needs an imported bank/card statement. QBO's own \"For Review\" queue, suggested matches, and bank rules are not API-exposed, so this page cannot substitute for them; it can only compare what you import against what's posted.")
                    .font(VLTypography.caption())
                    .foregroundStyle(VLColor.textMuted)

                HStack {
                    Button("Import Statement (CSV)…") { onImportTapped() }
                        .buttonStyle(.borderedProminent)
                    if let importError {
                        VLStatusPill(.urgent, label: importError)
                    }
                }

                VLCard {
                    VStack(alignment: .leading, spacing: VLSpacing.sm) {
                        HStack {
                            Text("MISSING POSTINGS (VL-RECON-MISSING-001)")
                                .font(VLTypography.eyebrow())
                                .tracking(VLTypography.eyebrowTracking)
                                .foregroundStyle(VLColor.textMuted)
                            Spacer()
                            VLStatusPill(coverageStatus)
                        }
                        Text(missingPostingOutcomeDetail)
                            .font(VLTypography.body())
                            .foregroundStyle(VLColor.textSecondary)

                        if !findings.isEmpty {
                            Divider().overlay(VLColor.border)
                            ForEach(findings) { finding in
                                Button {
                                    onSelectFinding(finding)
                                } label: {
                                    HStack {
                                        Text(finding.title)
                                            .font(VLTypography.body())
                                            .foregroundStyle(VLColor.textSecondary)
                                        Spacer()
                                        Text(finding.dollarExposure.description)
                                            .font(VLTypography.tabularNumeric())
                                            .foregroundStyle(VLColor.textPrimary)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(VLSpacing.pageGutter)
        }
        .background(VLColor.background)
    }
}
