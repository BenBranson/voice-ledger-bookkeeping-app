import Foundation
import Core

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
    case aiConversations
    case connection
    case scopeAndPeriodLock
    case audioSettings

    /// The exact label on the left-hand menu. Saying "go to <this>" always
    /// works (owner directive 2026-09-30); `VoiceIntentRouter` derives its
    /// aliases from these, so a renamed or new menu item is one edit here.
    public var menuTitle: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .findingsList: return "Findings"
        case .amountSearch: return "Search by Amount"
        case .pricingCalculator: return "Pricing Calculator"
        case .intakeQuestions: return "Intake Questions"
        case .firmCockpit: return "Firm Cockpit"
        case .cashFlowForecast: return "Cash Flow Forecast"
        case .clientDiagnostics: return "Client Diagnostics"
        case .cleanupAssessment: return "Cleanup Assessment"
        case .balanceSheetIntegrity: return "Balance Sheet Integrity"
        case .chartOfAccountsCleanup: return "Chart of Accounts"
        case .bankFeedCleanup: return "Bank Feed Cleanup"
        case .batchFixes: return "Batch Fixes"
        case .salesTaxReview: return "Sales Tax Review"
        case .recurringVendors: return "Recurring Vendors"
        case .monthEndClose: return "Month-End Close"
        case .closePackage: return "Close Package"
        case .activityLog: return "Activity Log"
        case .balanceSheetReport: return "Balance Sheet"
        case .profitAndLossReport: return "Profit & Loss"
        case .cashFlowReport: return "Cash Flow"
        case .trialBalanceReport: return "Trial Balance"
        case .agedReceivablesReport: return "Aged Receivables"
        case .agedPayablesReport: return "Aged Payables"
        case .generalLedgerReport: return "General Ledger"
        case .taxes: return "Taxes"
        case .clientMemory: return "Client Memory"
        case .aiConversations: return "AI Conversations"
        case .connection: return "Connection"
        case .scopeAndPeriodLock: return "Scope & Period Lock"
        case .audioSettings: return "Audio Settings"
        }
    }
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

    // MARK: Command grammar (2026-09-30) — resolved in code, never by the model.
    case goForward
    /// "pull up the duplicates" → the page that owns the group, plus its count/total spoken from ClientFacts.
    case findingsGroup(FactFindingGroup)
    /// "open the $1,420 one" / "pull up the Cool Cars payment" — resolved against open findings.
    case openFindingMatching(amount: Money?, text: String)
    case accountBalance(String)
    case searchAmount(Money)
    case searchVendor(String)
    case kpi(KPIMetric, PeriodChoice)
    case freshness
    case chart(ChartKind)
}

public enum KPIMetric: String, Equatable, Sendable { case revenue, netIncome, cashBalance }
public enum ChartKind: String, Equatable, Sendable { case expenseDrivers = "expense_drivers", vendorSpend = "vendor_spend", incomeVsExpenses = "income_vs_expenses", pareto = "pareto_cost_drivers" }
