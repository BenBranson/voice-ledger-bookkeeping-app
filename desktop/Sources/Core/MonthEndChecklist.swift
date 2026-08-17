import Foundation

/// docs/VOICE_LEDGER_SPEC.md Page 11 (Type A + C): "App: maintains the
/// checklist, dependencies, approvals, and carry-forward items; reads the
/// QBO close date where available; runs a full validation scan." **This is
/// the checklist/dependencies/approvals slice only** — "reads the QBO close
/// date" stays out of scope: `BookCloseDate`'s real field name was checked
/// live and found absent from this sandbox's `Preferences` response (see
/// `VL-PERIOD-CLOSED-001`'s note in `08_RULE_ENGINE.md` §8.8), so there is
/// no verified field to read yet. "Runs a full validation scan" is also not
/// attempted here — it would mean re-evaluating every rule and rendering a
/// pass/fail summary, a real feature but a separate one from the checklist
/// itself. No new QBO catalog operation was needed for what IS built here.
public struct ChecklistItemID: Hashable, Codable, Sendable, RawRepresentable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

public struct ChecklistItem: Identifiable, Hashable, Codable, Sendable {
    public let id: ChecklistItemID
    public let title: String
    public let description: String
    /// Items that must be marked complete before this one can be. Ordering
    /// is a real dependency graph, not just display order — `MonthEndChecklist
    /// .isUnlocked` walks this.
    public let prerequisiteIDs: [ChecklistItemID]

    public init(id: ChecklistItemID, title: String, description: String, prerequisiteIDs: [ChecklistItemID] = []) {
        self.id = id
        self.title = title
        self.description = description
        self.prerequisiteIDs = prerequisiteIDs
    }
}

/// A human's attestation that a checklist item is done — the same
/// "recorded, not proof" posture as `docs/phase-0/11_VERTICAL_SLICE.md`
/// §11.4's finding-completion attestation. Nothing here re-verifies that
/// the underlying work actually happened; it's a record that a person said
/// so, with their name and when.
public struct ChecklistItemCompletion: Codable, Sendable, Equatable {
    public let itemID: ChecklistItemID
    public let period: AccountingPeriod
    public let completedAt: Date
    public let completedBy: String
    public let note: String?

    public init(itemID: ChecklistItemID, period: AccountingPeriod, completedAt: Date = Date(), completedBy: String, note: String? = nil) {
        self.itemID = itemID
        self.period = period
        self.completedAt = completedAt
        self.completedBy = completedBy
        self.note = note
    }
}

public enum MonthEndChecklist {
    /// A fixed, real checklist for the pages already built — not a
    /// generic placeholder. `readiness` for each item (whether its
    /// underlying condition is actually met right now) is computed by the
    /// app layer from real `Finding` data (`CLAUDE.md` rule 1: code
    /// classifies, never a manual guess) — this type only defines
    /// structure and ordering, not readiness logic, since `Core` has no
    /// per-rule-ID knowledge of which rules belong to which checklist item
    /// beyond what's encoded in the item's own `id`.
    public static let defaultItems: [ChecklistItem] = [
        ChecklistItem(
            id: ChecklistItemID(rawValue: "resolve-cleanup-assessment"),
            title: "Resolve open Cleanup Assessment findings",
            description: "Every open finding from the Cleanup Assessment page (duplicate vendors, bills, invoices, payments; miscoded credit-card payments and payroll; uncategorized transactions) is reviewed and resolved."
        ),
        ChecklistItem(
            id: ChecklistItemID(rawValue: "review-balance-sheet-integrity"),
            title: "Review Balance Sheet Integrity findings",
            description: "Negative asset/liability balances, nonzero Opening Balance Equity, and aged Undeposited Funds are reviewed and resolved.",
            prerequisiteIDs: [ChecklistItemID(rawValue: "resolve-cleanup-assessment")]
        ),
        ChecklistItem(
            id: ChecklistItemID(rawValue: "review-bank-feed"),
            title: "Review Bank Feed Cleanup findings",
            description: "Every imported statement line either matches posted QBO activity or has been entered/matched. Statement descriptions that don't match QBO's vendor names are confirmed correct."
        ),
        ChecklistItem(
            id: ChecklistItemID(rawValue: "reconcile-bank-accounts"),
            title: "Reconcile bank and credit card accounts",
            description: "Complete reconciliation for every bank and credit card account in QBO — Voice Ledger cannot verify this itself (no reconciliation-completion API); this step is your own attestation.",
            prerequisiteIDs: [ChecklistItemID(rawValue: "review-bank-feed")]
        ),
        ChecklistItem(
            id: ChecklistItemID(rawValue: "set-qbo-closing-date"),
            title: "Set the official closing date in QBO",
            description: "Set QuickBooks Online's own closing date once the period is fully reviewed — Voice Ledger cannot set this itself (no write path) and cannot read it back yet either (BookCloseDate's field name is unverified in this sandbox).",
            prerequisiteIDs: [
                ChecklistItemID(rawValue: "resolve-cleanup-assessment"),
                ChecklistItemID(rawValue: "review-balance-sheet-integrity"),
                ChecklistItemID(rawValue: "reconcile-bank-accounts")
            ]
        )
    ]

    /// An item is unlocked (may be marked complete) once every prerequisite
    /// is present in `completedItemIDs`. The final item's prerequisites are
    /// a real AND-of-three, not a flattened linear chain — completing item
    /// 2 alone does not unlock the closing-date step.
    public static func isUnlocked(_ item: ChecklistItem, completedItemIDs: Set<ChecklistItemID>) -> Bool {
        item.prerequisiteIDs.allSatisfy { completedItemIDs.contains($0) }
    }
}
