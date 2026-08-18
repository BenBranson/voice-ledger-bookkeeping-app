import Foundation

/// docs/phase-0/10_STAGING_APPROVAL_AUDIT.md §10.8. Terminology deliberate
/// (`CLAUDE.md`): *Voice Ledger Activity & Correction Log*, not "Audit Log."
public enum Actor: Hashable, Codable, Sendable {
    case user(String)
    case system
}

/// Only the cases this slice's Branch B path produces — the full spec's
/// `ActivityKind` enumerates many more (§10.8), added when the code paths
/// that produce them exist.
public enum ActivityKind: String, Codable, Sendable {
    case findingDetected
    case manualCompletionAttested
    case findingResolved
    /// A `.stagedAPI` `ProposedAction` was executed via `updatePurchaseLineAccount`
    /// and QBO's round-trip verification confirmed the change (`verified: true`).
    /// Unlike `manualCompletionAttested`, this IS QBO-confirmed — the `note`
    /// field carries the verification summary, not just a human's say-so.
    case apiWriteApplied
    /// A client question was drafted (`ClientQuestionDrafter`) and the human
    /// recorded it as sent — the `note` field carries the actual question
    /// text. This records that a question was asked, not an answer; see
    /// `ClientQuestionDrafter`'s doc comment for what's not built yet.
    case clientQuestionDrafted
    /// The human decided a finding isn't worth acting on — distinct from
    /// `findingResolved` (the underlying problem is actually fixed). The
    /// `note` field carries the reason, when one was given.
    case findingDismissed
    /// A `ClientMemoryRule` was created — an explicit, separate action, per
    /// spec's "never silently." The `note` field carries the rule's vendor
    /// name and covered ruleID for a readable log entry.
    case clientMemoryRuleCreated
    /// A `ClientMemoryRule` was removed — the reversal path.
    case clientMemoryRuleRemoved
    /// A finding was auto-dismissed because it matched an existing
    /// `ClientMemoryRule` — distinct from a human dismissing one finding at
    /// a time (`findingDismissed`), so the Activity Log can tell the two
    /// apart. Never silent: this entry IS the record that it happened.
    case findingAutoDismissedByClientMemory
}

/// docs/phase-0/11_VERTICAL_SLICE.md §11.4's worked example. Branch B never
/// stages a QBO write, so this entry has no `qboResponse` — attestation is
/// a statement by you, not a QBO-confirmed result (acceptance criterion 14:
/// attestation is not treated as proof; the finding only resolves once a
/// resync shows the void actually happened).
public struct ActivityLogEntry: Identifiable, Codable, Sendable {
    public let id: String
    public let realmID: RealmID
    public let recordedAt: Date
    public let actor: Actor
    public let kind: ActivityKind
    public let findingID: String?
    public let ruleID: RuleID?
    public let ruleVersion: RuleVersion?
    public let procedure: GuidedProcedure?
    public let note: String?
    /// The QBO entity's full state immediately before/after a `.stagedAPI`
    /// write — `WriteVerificationResult.beforeSnapshotJSON`/
    /// `afterSnapshotJSON`, carried through to the permanent record. `nil`
    /// for every entry that isn't an `apiWriteApplied` write (which is
    /// most of them) — additive fields, same pattern used repeatedly
    /// elsewhere in this project.
    public let beforeSnapshotJSON: String?
    public let afterSnapshotJSON: String?

    public init(
        id: String = UUID().uuidString,
        realmID: RealmID,
        recordedAt: Date = Date(),
        actor: Actor,
        kind: ActivityKind,
        findingID: String? = nil,
        ruleID: RuleID? = nil,
        ruleVersion: RuleVersion? = nil,
        procedure: GuidedProcedure? = nil,
        note: String? = nil,
        beforeSnapshotJSON: String? = nil,
        afterSnapshotJSON: String? = nil
    ) {
        self.id = id
        self.realmID = realmID
        self.recordedAt = recordedAt
        self.actor = actor
        self.kind = kind
        self.findingID = findingID
        self.ruleID = ruleID
        self.ruleVersion = ruleVersion
        self.procedure = procedure
        self.note = note
        self.beforeSnapshotJSON = beforeSnapshotJSON
        self.afterSnapshotJSON = afterSnapshotJSON
    }
}
