import SwiftUI
import Core
import DesignSystem

/// Owner directive (2026-09-06): "if I ask to see two different
/// transactions it should be able to pull both up... like looking at a
/// line of suspects and questioning them to find the real culprit" —
/// later expanded: "shouldn't be just limited to 2... it should be able to
/// pull up multiple findings." Presented from a real `Window` scene by
/// `VoiceLedgerApp`, bound to `AppState.comparedFindingIDs`. Each card is
/// independently closable, and a top-right "X" (plus the window's own
/// native close control) dismisses the whole comparison at once.
///
/// This is exactly the UI several real rules already call for:
/// `DuplicatePostedExpenseRule`/`VendorDescriptionMismatchRule`/
/// `VendorPriceIncreaseRule` are all inherently about comparing two or more
/// real things — this view is a more honest presentation of what those
/// rules already assert, not a new kind of claim.
public struct FindingComparisonView: View {
    private let findings: [Finding]
    private let onSelectFinding: (Finding) -> Void
    private let onClose: (Finding) -> Void
    private let onCloseAll: () -> Void
    /// Owner directive (2026-09-06): "you can use a scroll bar to see them
    /// all but also their should be a clickable box on each one and i
    /// should be able to press compare and analyze these findings that are
    /// checked in the box and the app should be able to find similarites
    /// and detect if they are a duplicate or explain and justify when they
    /// are totally different." The similarity/duplicate analysis itself —
    /// same free/second-opinion pairing as every other Ask AI surface in
    /// this app (`FindingDetailView`, the Findings-page health report).
    private let analysisAnswer: String?
    private let isGeneratingAnalysis: Bool
    private let analysisError: String?
    private let onAnalyze: () -> Void
    private let onAskFollowUp: (String) -> Void
    private let secondOpinionConfigured: Bool
    private let analysisSecondOpinionAnswer: String?
    private let isGeneratingAnalysisSecondOpinion: Bool
    private let analysisSecondOpinionError: String?
    private let onAnalyzeSecondOpinion: () -> Void
    private let onAskFollowUpSecondOpinion: (String) -> Void

    /// Owner directive (2026-09-07): "add a analyze button with claude
    /// button and a ask a question field on the compare findings screen" —
    /// a third tier alongside Gemma (free) and OpenAI (second opinion),
    /// same shape as both.
    private let claudeConfigured: Bool
    private let analysisClaudeAnswer: String?
    private let isGeneratingAnalysisClaude: Bool
    private let analysisClaudeError: String?
    private let onAnalyzeClaude: () -> Void
    private let onAskFollowUpClaude: (String) -> Void

    public init(
        findings: [Finding],
        onSelectFinding: @escaping (Finding) -> Void,
        onClose: @escaping (Finding) -> Void,
        onCloseAll: @escaping () -> Void,
        analysisAnswer: String? = nil,
        isGeneratingAnalysis: Bool = false,
        analysisError: String? = nil,
        onAnalyze: @escaping () -> Void = {},
        onAskFollowUp: @escaping (String) -> Void = { _ in },
        secondOpinionConfigured: Bool = false,
        analysisSecondOpinionAnswer: String? = nil,
        isGeneratingAnalysisSecondOpinion: Bool = false,
        analysisSecondOpinionError: String? = nil,
        onAnalyzeSecondOpinion: @escaping () -> Void = {},
        onAskFollowUpSecondOpinion: @escaping (String) -> Void = { _ in },
        claudeConfigured: Bool = false,
        analysisClaudeAnswer: String? = nil,
        isGeneratingAnalysisClaude: Bool = false,
        analysisClaudeError: String? = nil,
        onAnalyzeClaude: @escaping () -> Void = {},
        onAskFollowUpClaude: @escaping (String) -> Void = { _ in }
    ) {
        self.findings = findings
        self.onSelectFinding = onSelectFinding
        self.onClose = onClose
        self.onCloseAll = onCloseAll
        self.analysisAnswer = analysisAnswer
        self.isGeneratingAnalysis = isGeneratingAnalysis
        self.analysisError = analysisError
        self.onAnalyze = onAnalyze
        self.onAskFollowUp = onAskFollowUp
        self.secondOpinionConfigured = secondOpinionConfigured
        self.analysisSecondOpinionAnswer = analysisSecondOpinionAnswer
        self.isGeneratingAnalysisSecondOpinion = isGeneratingAnalysisSecondOpinion
        self.analysisSecondOpinionError = analysisSecondOpinionError
        self.onAnalyzeSecondOpinion = onAnalyzeSecondOpinion
        self.onAskFollowUpSecondOpinion = onAskFollowUpSecondOpinion
        self.claudeConfigured = claudeConfigured
        self.analysisClaudeAnswer = analysisClaudeAnswer
        self.isGeneratingAnalysisClaude = isGeneratingAnalysisClaude
        self.analysisClaudeError = analysisClaudeError
        self.onAnalyzeClaude = onAnalyzeClaude
        self.onAskFollowUpClaude = onAskFollowUpClaude
    }

    /// Card width * 2 + inter-card spacing + page gutters — owner-reported
    /// bug (2026-09-06): the sheet used to size to fit exactly one card,
    /// so comparing two findings (the whole point of this view) meant
    /// scrolling to see the second one. Sized so two cards are visible
    /// with no scrolling at the sheet's default size; a third+ still
    /// scrolls horizontally rather than growing the sheet unboundedly.
    private static let defaultWidth: CGFloat = 760
    private static let defaultHeight: CGFloat = 620

    public var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: VLSpacing.md) {
                HStack {
                    Text("Comparing \(findings.count) Finding\(findings.count == 1 ? "" : "s")")
                        .font(VLTypography.pageTitle())
                        .foregroundStyle(VLColor.textPrimary)
                    Spacer()
                    // Owner-reported bug (2026-09-06): "an x at the top right
                    // to close" the whole comparison — each card's own X only
                    // removed that one card, with no way to dismiss the
                    // window itself short of closing every card individually.
                    Button(action: onCloseAll) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(VLColor.textMuted)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)
                    .help("Close comparison")
                }

                // Owner directive (2026-09-06): not capped at two — any
                // number of pulled-up findings scroll horizontally here,
                // exactly the owner's own suggested affordance ("you can
                // use a scroll bar to see them all").
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: VLSpacing.md) {
                        ForEach(findings) { finding in
                            card(for: finding)
                                .frame(width: 320)
                        }
                    }
                    .padding(.bottom, VLSpacing.sm)
                }

                if findings.count >= 2 {
                    Divider().overlay(VLColor.border)
                    analysisSection
                }
            }
            .padding(VLSpacing.pageGutter)
        }
        // Owner-reported bug (2026-09-06): with only a `minWidth`/
        // `minHeight` (no `maxWidth`/`maxHeight`), SwiftUI reported this
        // view's ideal size as equal to its minimum, so the window had no
        // flexible dimension to grow along and macOS showed no resize
        // affordance at all. `maxWidth`/`maxHeight: .infinity` gives it
        // real flexibility. Presented from a real `Window` scene, not a
        // `.sheet` — confirmed live (2026-09-06) that a macOS `.sheet`'s
        // attached window doesn't get a resize grip regardless of frame
        // flexibility; a `Window` scene does, plus real traffic-light
        // controls in place of the hand-rolled "X."
        .frame(minWidth: Self.defaultWidth, idealWidth: Self.defaultWidth, maxWidth: .infinity,
               minHeight: Self.defaultHeight, idealHeight: Self.defaultHeight, maxHeight: .infinity)
        .background(VLColor.background)
    }

    private var analysisSection: some View {
        VStack(alignment: .leading, spacing: VLSpacing.sm) {
            AskAIPanelView(
                title: "SIMILARITY & DUPLICATE ANALYSIS (GEMMA — FREE)",
                disclaimer: "Grounded in the finding details and computed comparison signals above (same vendor, same amount, same period, same category) — never asserts a similarity the numbers don't support.",
                aiStatus: nil,
                answer: analysisAnswer,
                isAsking: isGeneratingAnalysis,
                error: analysisError,
                onAsk: onAskFollowUp,
                quickAskLabel: "Compare & Analyze",
                onQuickAsk: onAnalyze
            )
            if secondOpinionConfigured {
                AskAIPanelView(
                    title: "SIMILARITY & DUPLICATE ANALYSIS (OPENAI — MORE THOROUGH)",
                    disclaimer: "Same real data, sent to OpenAI for a more thorough read. Costs money per analysis and only runs when you ask.",
                    aiStatus: nil,
                    answer: analysisSecondOpinionAnswer,
                    isAsking: isGeneratingAnalysisSecondOpinion,
                    error: analysisSecondOpinionError,
                    onAsk: onAskFollowUpSecondOpinion,
                    quickAskLabel: "Analyze (OpenAI)",
                    onQuickAsk: onAnalyzeSecondOpinion
                )
            }
            if claudeConfigured {
                AskAIPanelView(
                    title: "SIMILARITY & DUPLICATE ANALYSIS (CLAUDE HAIKU 4.5)",
                    disclaimer: "Same real data, sent to Claude Haiku 4.5 for a fast cloud read. Costs a fraction of a cent per analysis and only runs when you ask.",
                    aiStatus: nil,
                    answer: analysisClaudeAnswer,
                    isAsking: isGeneratingAnalysisClaude,
                    error: analysisClaudeError,
                    onAsk: onAskFollowUpClaude,
                    quickAskLabel: "Analyze (Claude)",
                    onQuickAsk: onAnalyzeClaude
                )
            }
        }
    }

    private func card(for finding: Finding) -> some View {
        VLCard(accentRail: finding.severity == .high ? VLColor.violet : nil) {
            VStack(alignment: .leading, spacing: VLSpacing.sm) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: VLSpacing.xxs) {
                        Text(finding.title)
                            .font(VLTypography.cardTitle())
                            .foregroundStyle(VLColor.textPrimary)
                        if let vendorName = finding.vendorName {
                            Text(vendorName)
                                .font(VLTypography.caption())
                                .foregroundStyle(VLColor.textSecondary)
                        }
                    }
                    Spacer()
                    Button {
                        onClose(finding)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(VLColor.textMuted)
                    }
                    .buttonStyle(.plain)
                }

                HStack(spacing: VLSpacing.sm) {
                    VLStatusPill(finding.severity == .high ? .urgent : .verified, label: finding.severity.rawValue)
                    Text("Confidence: \(finding.confidence.rawValue)")
                        .font(VLTypography.caption())
                        .foregroundStyle(VLColor.textMuted)
                }

                Text(finding.dollarExposure.description)
                    .font(VLTypography.metricLarge())
                    .foregroundStyle(VLColor.textPrimary)

                if let narrative = finding.narrative {
                    Text(narrative)
                        .font(VLTypography.caption())
                        .foregroundStyle(VLColor.textSecondary)
                        .lineLimit(4)
                }

                if !finding.proposedActions.isEmpty {
                    Divider().overlay(VLColor.border)
                    Text("RECOMMENDATIONS")
                        .font(VLTypography.eyebrow())
                        .tracking(VLTypography.eyebrowTracking)
                        .foregroundStyle(VLColor.textMuted)
                    ForEach(Array(finding.proposedActions.enumerated()), id: \.offset) { _, action in
                        Text("• \(action.title)")
                            .font(VLTypography.caption())
                            .foregroundStyle(VLColor.textSecondary)
                    }
                }

                Button("View Full Detail") { onSelectFinding(finding) }
                    .buttonStyle(.bordered)
            }
        }
    }
}
