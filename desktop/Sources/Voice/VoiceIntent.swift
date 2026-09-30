import Foundation

/// The app's own screen vocabulary, in voice's terms — deliberately NOT
/// `AppState.Screen` itself (`Voice` depends only on `Core`; `AppState`
/// lives in `VoiceLedgerApp`, a layer up). `VoiceEngine` (VoiceLedgerApp)
/// is the one place that maps this to a real `AppState.screen` assignment
/// — the same "UI-only vocabulary, app layer translates" split
/// `VoiceLedgerUI.ReportExportFormat` already uses for exports. Omits
/// `.detail`/`.procedure` (need a finding id, not a bare destination) and
/// `.connection` (not a page a bookkeeper "navigates to" mid-session).
public enum VoiceDestination: String, Codable, Sendable, CaseIterable {
    case dashboard
    case findingsList
    case cleanupAssessment
    case balanceSheetIntegrity
    case bankFeedCleanup
    case chartOfAccountsCleanup
    case batchFixes
    case salesTaxReview
    case taxes
    case firmCockpit
    case monthEndClose
    case activityLog
    case closePackage
    case clientMemory
    case balanceSheetReport
    case profitAndLossReport
    case cashFlowReport
    case trialBalanceReport
    case agedReceivablesReport
    case agedPayablesReport
    case generalLedgerReport
    case cashFlowForecast
    case recurringVendors
    case amountSearch
    case clientDiagnostics
    case pricingCalculator
    case intakeQuestions
}

/// A closed set of what a voice command can ever mean. Deliberately has NO
/// case that applies a staged QBO fix — `VoiceIntentRouter` cannot produce
/// what this enum cannot represent, so "voice never finalizes a QBO write"
/// (docs/VOICE_LEDGER_SPEC.md's Voice Guardrails line) is a property of the
/// type system, not a runtime check someone could forget to add. The two
/// mutating cases this DOES carry (`confirmPending`/`rejectPending`) only
/// ever resolve a `VoicePendingAction`, which is itself restricted to
/// Voice Ledger's own low-stakes internal state (dismiss/complete —
/// see `VoicePendingAction.Kind`), never a QBO entity.
public enum VoiceIntent: Equatable, Sendable {
    case navigate(VoiceDestination)
    case goBack
    /// "Hi"/"status update" — a greeting that gets a real, deterministic
    /// answer (open-findings count + total dollar exposure, both already-
    /// computed data) instead of falling through to the reasoning path
    /// with nothing to say. Real, requested phrase (2026-08-29).
    case statusOverview
    case startReviewQueue
    /// Re-syncs and re-evaluates against QBO, then starts a fresh review
    /// queue from whatever is open afterward — "check again"/"any new
    /// anomalies" after a batch has already been cleared. Handled by
    /// calling the same `AppState.syncAndEvaluate()` the sidebar's own
    /// refresh button already calls, not a new sync mechanism.
    case recheckAnomalies
    case queueNext
    case queueSkip
    case queueStatus
    case openLastEntity
    case explainCurrent
    case recapContext
    case confirmPending
    case rejectPending
    /// Didn't match any deterministic pattern — the caller falls through
    /// to the reasoning path (`AskAIContext` + the existing OpenAI Ask AI
    /// route), carrying the ORIGINAL text, not a guess at what was meant.
    case unrecognized(String)
}
