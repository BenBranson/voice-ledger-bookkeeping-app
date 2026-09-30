import Foundation
import Core

/// A UI action a voice turn wants to happen. Historically produced ONLY by
/// `VoiceIntentRouter`'s deterministic phrase matches — the direct fix for
/// a reference app's own verified hallucination bug, where a reasoning
/// response's spoken `speech` could say anything, INCLUDING claiming it
/// navigated/opened/staged something it never actually did.
///
/// Extended 2026-09-06 (`VoiceToolLoop`) to ALSO be producible by a real,
/// structured tool call the model made — this preserves the exact same
/// safety property through a different, still-real mechanism: the model
/// cannot fake having navigated by just SAYING so in its spoken text (that
/// text is narration only, same as before); it has to emit an actual
/// tool call, which this app's own code then executes deterministically
/// (`VoiceToolLoop`'s dispatch), same as `VoiceIntentRouter`'s matches
/// always have. What changed is WHICH mechanism can decide an action is
/// warranted (a phrase match, or a model's tool choice) — never whether
/// free prose alone can claim one happened, which stays categorically
/// impossible either way.
public enum VoiceUIAction: Equatable, Sendable {
    case navigate(VoiceDestination)
    case openFinding(id: String)
    /// Added 2026-09-06 for side-by-side comparison ("pull up these two
    /// transactions") — a real UI need `VoiceIntentRouter`'s single
    /// `.openFinding` could never express: several real rules
    /// (`DuplicatePostedExpenseRule`, `VendorDescriptionMismatchRule`,
    /// `VendorPriceIncreaseRule`) are inherently about comparing TWO
    /// things, and a bookkeeper investigating one wants both side by side,
    /// not one at a time.
    case openFindings(ids: [String])
    case goBack
    case goForward
    /// Added 2026-09-06 for `VoiceToolLoop`'s `generate_chart` tool — a
    /// popup, not a full-page navigation, matching the owner's own
    /// framing ("maybe for making charts it can make a pop up"). Renders
    /// one of the app's existing chart components; see `ChartRequest`'s
    /// own doc comment for why the DATA is always computed by `Core`
    /// before this case is ever produced, never by the model.
    case presentChart(ChartRequest)
}

/// What to render in the chart popup, and the REAL data to render —
/// always computed by `Core` (`TopExpenseDrivers`, `VendorSpendSummary`,
/// `BalanceSheetBreakdown`, `ProfitAndLossWaterfall`) before this value is
/// ever constructed. The model's `generate_chart` tool call only ever
/// names WHICH kind to show — never a number that ends up in it — same
/// CLAUDE.md rule 1 boundary as every other model-facing surface in this
/// app.
public enum ChartRequest: Equatable, Sendable {
    case expenseDrivers(title: String, drivers: [TopExpenseDrivers.Driver])
    case vendorSpend(title: String, vendors: [VendorSpendSummary.VendorTotal])
    case paretoCostDrivers(title: String, drivers: [TopExpenseDrivers.Driver])
    case incomeVsExpenses(title: String, segments: [ProfitAndLossWaterfall.Segment])
}

/// `speech` is always shown/spoken verbatim from whichever path (router or
/// reasoning) produced it. `uiAction` and `pendingAction` are the ONLY
/// things that change application state — see `VoiceUIAction`'s doc
/// comment for why the reasoning path can never populate either.
public struct VoiceTurn: Equatable, Sendable {
    public let speech: String
    public let uiAction: VoiceUIAction?
    /// Set only when this turn creates a NEW pending confirmation (e.g.
    /// "dismiss this finding?") — never for a turn that resolves one
    /// (`VoiceIntent.confirmPending`/`.rejectPending` clear it instead,
    /// handled by the caller, not represented here).
    public let newPendingAction: VoicePendingAction?

    public init(speech: String, uiAction: VoiceUIAction? = nil, newPendingAction: VoicePendingAction? = nil) {
        self.speech = speech
        self.uiAction = uiAction
        self.newPendingAction = newPendingAction
    }
}
