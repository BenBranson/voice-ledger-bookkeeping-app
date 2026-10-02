import Foundation
import Core

/// The guided month-end walkthrough ("start month-end"). The steps mirror
/// docs/MONTHLY_ROUTINE.md section A: data in → categorize → reconcile →
/// review exceptions → report. Each step is either something Moneypenny
/// does and reads out (an `intent` resolved by the same code as saying it),
/// or a manual step (`manual`) that only the bookkeeper can do in QuickBooks.
public struct MonthEndStep: Equatable, Sendable {
    public let title: String
    /// What she does at this step (nil for manual steps).
    public let intent: VoiceIntent?
    /// What the bookkeeper must do herself/himself in QuickBooks.
    public let manual: String?
}

public enum MonthEndRoutine {
    public static let steps: [MonthEndStep] = [
        MonthEndStep(title: "Check the data is fresh", intent: .freshness, manual: nil),
        MonthEndStep(title: "Bank feed cleanup", intent: .navigate(.bankFeedCleanup), manual: nil),
        MonthEndStep(title: "Add or match missing bank lines", intent: nil,
                     manual: "In QuickBooks, add or match every bank line that's missing, then press Sync here."),
        MonthEndStep(title: "Uncategorized transactions", intent: .findingsGroup(.miscategorizedOrUncategorized), manual: nil),
        MonthEndStep(title: "Reconcile the accounts", intent: nil,
                     manual: "In QuickBooks, reconcile each bank and credit card account to its statement. The app can't confirm this for you."),
        MonthEndStep(title: "Status overview", intent: .statusOverview, manual: nil),
        MonthEndStep(title: "Duplicates", intent: .findingsGroup(.duplicates), manual: nil),
        MonthEndStep(title: "Negative balances", intent: .findingsGroup(.negativeBalance), manual: nil),
        MonthEndStep(title: "Suspense and clearing accounts", intent: .findingsGroup(.balanceSheetIntegrity), manual: nil),
        MonthEndStep(title: "What customers owe", intent: .totalReceivable, manual: nil),
        MonthEndStep(title: "What we owe", intent: .totalOwed, manual: nil),
        MonthEndStep(title: "Cash balance", intent: .kpi(.cashBalance, .current), manual: nil),
        MonthEndStep(title: "Revenue", intent: .kpi(.revenue, .current), manual: nil),
        MonthEndStep(title: "Net income", intent: .kpi(.netIncome, .current), manual: nil),
        MonthEndStep(title: "Month-end close checklist", intent: .navigate(.monthEndClose), manual: nil),
        MonthEndStep(title: "Close package (the client report)", intent: .navigate(.closePackage), manual: nil)
    ]

    public static var count: Int { steps.count }

    /// "Step 3 of 16: …"
    public static func heading(_ index: Int) -> String { "Step \(index + 1) of \(count): \(steps[index].title)." }

    // MARK: Phrases (only active while a walkthrough is running)

    public static let advancePhrases: Set<String> = ["next", "next step", "done", "i'm done", "im done", "continue", "go on", "keep going", "move on", "skip", "skip this", "skip it", "ok", "okay", "got it", "ready", "all done", "finished", "i did that", "that's done", "thats done"]
    public static let repeatPhrases: Set<String> = ["repeat", "repeat that", "say that again", "again", "one more time", "read that again", "what was that"]
    public static let previousPhrases: Set<String> = ["previous step", "last step", "go back a step", "step back", "previous"]
    public static let stopPhrases: Set<String> = ["stop", "stop the routine", "end the routine", "end routine", "stop month end", "end month end", "cancel the routine", "exit routine", "i'm done for now", "pause", "quit", "stop the walkthrough", "end the walkthrough"]
    public static let wherePhrases: Set<String> = ["where are we", "what step is this", "what step are we on", "how many steps are left", "how much is left", "what's left", "whats left", "progress"]
    public static let startPhrases: Set<String> = [
        "start month end", "start the month end", "start month end review", "start the month end review", "begin month end", "begin the month end", "month end walkthrough", "start the monthly routine",
        "start the routine", "start monthly routine", "walk me through month end", "walk me through the month", "walk me through the month end", "start the walkthrough", "month end routine", "do the month end", "run the month end routine"
    ]

    public enum Command: Equatable, Sendable { case advance, `repeat`, previous, stop, `where` }

    /// Phrases recognized only while a walkthrough is active.
    public static func command(for text: String) -> Command? {
        let t = CommandGrammar.normalize(text)
        if advancePhrases.contains(t) { return .advance }
        if repeatPhrases.contains(t) { return .repeat }
        if previousPhrases.contains(t) { return .previous }
        if stopPhrases.contains(t) { return .stop }
        if wherePhrases.contains(t) { return .where }
        return nil
    }

    public static func isStart(_ text: String) -> Bool { startPhrases.contains(CommandGrammar.normalize(text)) }
}
