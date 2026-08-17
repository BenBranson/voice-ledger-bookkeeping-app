import SwiftUI
import Core
import DesignSystem

/// docs/VOICE_LEDGER_SPEC.md Page 4 (Type B): "analyzes posted QBO activity
/// and compares it against your imported CSV/OFX/QFX statement; detects
/// duplicates and missing postings." **Minimal read-only slice**: only
/// `VL-RECON-MISSING-001` (missing postings) — no file-import UI yet (no
/// drag-and-drop, no column-mapping confirm-and-correct screen per
/// docs/phase-0/09_INGESTION_PIPELINE.md §9.4), so this always shows the
/// "no statement imported" honest state until that UI exists. Not
/// theater: the rule and its data pipeline (`BankStatementCSVImporter`)
/// are real and tested — only the UI to actually drop a file in is missing.
public struct BankFeedCleanupView: View {
    private let environment: VLEnvironmentTone
    private let coverageStatus: VLStatus
    private let missingPostingOutcomeDetail: String
    private let findings: [Finding]
    private let onSelectFinding: (Finding) -> Void

    public init(
        environment: VLEnvironmentTone,
        coverageStatus: VLStatus,
        missingPostingOutcomeDetail: String,
        findings: [Finding],
        onSelectFinding: @escaping (Finding) -> Void
    ) {
        self.environment = environment
        self.coverageStatus = coverageStatus
        self.missingPostingOutcomeDetail = missingPostingOutcomeDetail
        self.findings = findings
        self.onSelectFinding = onSelectFinding
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

                Text("Statement import (drag-and-drop, column mapping, cross-foot validation) is not built yet — this page's data pipeline is real and tested, but there is no way to bring a file in through the UI yet.")
                    .font(VLTypography.caption())
                    .foregroundStyle(VLColor.textMuted)
            }
            .padding(VLSpacing.pageGutter)
        }
        .background(VLColor.background)
    }
}
