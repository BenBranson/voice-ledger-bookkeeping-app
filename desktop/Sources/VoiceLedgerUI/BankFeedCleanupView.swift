import SwiftUI
import Core
import DesignSystem

/// docs/VOICE_LEDGER_SPEC.md Page 4 (Type B): "analyzes posted QBO activity
/// and compares it against your imported CSV/OFX/QFX/Excel statement;
/// detects duplicates and missing postings." **Minimal slice**: only
/// `VL-RECON-MISSING-001` (missing postings), CSV/OFX/QFX/XLSX (no legacy
/// .xls), plus Universal Ingestion Tier 2: a PDF or photo of a statement,
/// via on-device Vision OCR (`VisionDocumentOCR`, macOS 26+) — table-only,
/// same confirm-and-correct pipeline as every other format, no separate
/// normalization path. No drag-and-drop (file picker only), no cross-foot
/// validation (§9.5, except OFX's informational stated-ending-balance
/// display).
/// The confirm-and-correct column-mapping step (§9.4) is real —
/// `ImportBankStatementView`, presented by the app layer after
/// `onImportTapped` picks a file.
public struct BankFeedCleanupView: View {
    private let environment: VLEnvironmentTone
    private let coverageStatus: VLStatus
    private let missingPostingOutcomeDetail: String
    private let findings: [Finding]
    private let ambiguousFindings: [Finding]
    private let reconciliationSummary: ReconciliationSummary?
    private let importError: String?
    private let onSelectFinding: (Finding) -> Void
    private let onImportTapped: () -> Void

    public init(
        environment: VLEnvironmentTone,
        coverageStatus: VLStatus,
        missingPostingOutcomeDetail: String,
        findings: [Finding],
        ambiguousFindings: [Finding] = [],
        reconciliationSummary: ReconciliationSummary? = nil,
        importError: String?,
        onSelectFinding: @escaping (Finding) -> Void,
        onImportTapped: @escaping () -> Void
    ) {
        self.environment = environment
        self.coverageStatus = coverageStatus
        self.missingPostingOutcomeDetail = missingPostingOutcomeDetail
        self.findings = findings
        self.ambiguousFindings = ambiguousFindings
        self.reconciliationSummary = reconciliationSummary
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
                    Button("Import Statement (CSV/OFX/QFX/XLSX/PDF/Photo)…") { onImportTapped() }
                        .buttonStyle(.borderedProminent)
                    if let importError {
                        VLStatusPill(.urgent, label: importError)
                    }
                }

                if let reconciliationSummary {
                    reconciliationSection(reconciliationSummary)
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

                if !ambiguousFindings.isEmpty {
                    VLCard {
                        VStack(alignment: .leading, spacing: VLSpacing.sm) {
                            HStack {
                                Text("AMBIGUOUS MATCHES (VL-RECON-AMBIGUOUS-001)")
                                    .font(VLTypography.eyebrow())
                                    .tracking(VLTypography.eyebrowTracking)
                                    .foregroundStyle(VLColor.textMuted)
                                Spacer()
                                VLStatusPill(.reviewNeeded)
                            }
                            Text("A statement line matched more than one posted transaction equally well — reconciliation can't tell which one it clears until a human picks.")
                                .font(VLTypography.body())
                                .foregroundStyle(VLColor.textSecondary)
                            Divider().overlay(VLColor.border)
                            ForEach(ambiguousFindings) { finding in
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

    /// docs/VOICE_LEDGER_SPEC.md Page 5's "calculates difference," computed
    /// from `VL-RECON-MISSING-001`'s own findings (`ReconciliationSummary`'s
    /// doc comment) — not a separate page, folded in here since it's the
    /// same underlying comparison this page already runs.
    private func reconciliationSection(_ summary: ReconciliationSummary) -> some View {
        VLCard {
            VStack(alignment: .leading, spacing: VLSpacing.xs) {
                Text("RECONCILIATION SUMMARY")
                    .font(VLTypography.eyebrow())
                    .tracking(VLTypography.eyebrowTracking)
                    .foregroundStyle(VLColor.textMuted)
                HStack(spacing: VLSpacing.md) {
                    VStack(alignment: .leading) {
                        Text("\(summary.totalStatementLines)")
                            .font(VLTypography.metricLarge())
                            .foregroundStyle(VLColor.textPrimary)
                        Text("Statement lines")
                            .font(VLTypography.caption())
                            .foregroundStyle(VLColor.textMuted)
                    }
                    VStack(alignment: .leading) {
                        Text("\(summary.matchedCount)")
                            .font(VLTypography.metricLarge())
                            .foregroundStyle(VLColor.textPrimary)
                        Text("Matched")
                            .font(VLTypography.caption())
                            .foregroundStyle(VLColor.textMuted)
                    }
                    VStack(alignment: .leading) {
                        Text("\(summary.unmatchedCount)")
                            .font(VLTypography.metricLarge())
                            .foregroundStyle(VLColor.textPrimary)
                        Text("Unmatched")
                            .font(VLTypography.caption())
                            .foregroundStyle(VLColor.textMuted)
                    }
                    VStack(alignment: .leading) {
                        Text(summary.unmatchedTotal?.description ?? "$0.00")
                            .font(VLTypography.metricLarge())
                            .foregroundStyle(VLColor.textPrimary)
                        Text("Difference")
                            .font(VLTypography.caption())
                            .foregroundStyle(VLColor.textMuted)
                    }
                    VStack(alignment: .leading) {
                        Text("\(summary.ambiguousCount)")
                            .font(VLTypography.metricLarge())
                            .foregroundStyle(summary.ambiguousCount > 0 ? .red : VLColor.textPrimary)
                        Text("Ambiguous")
                            .font(VLTypography.caption())
                            .foregroundStyle(VLColor.textMuted)
                    }
                }
            }
        }
    }
}
