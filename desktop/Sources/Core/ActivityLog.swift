import Foundation

/// docs/phase-0/10_STAGING_APPROVAL_AUDIT.md §10.8. Terminology deliberate
/// (`CLAUDE.md`): *Voice Ledger Activity & Correction Log*, not "Audit Log."
public enum Actor: Hashable, Codable, Sendable {
    case user(String)
    case system

    public var displayLabel: String {
        switch self {
        case .user(let name): return "By \(name)"
        case .system: return "By Voice Ledger"
        }
    }
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
    /// The human recorded the client's reply to a previously-sent question
    /// — the answer-recording half `ClientQuestionDrafter`'s doc comment
    /// used to say wasn't built yet (closed 2026-08-28). Same "recorded,
    /// not verified by the app" posture: Voice Ledger has no channel to
    /// receive the client's actual reply, this only logs that a human
    /// heard back and what they said. The `note` field carries the answer
    /// text.
    case clientQuestionAnswered
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
    /// A `.stagedAPI` write was attempted but QBO either did not confirm it
    /// (`verified: false`) or the call itself threw — distinct from
    /// `apiWriteApplied` the same way `findingDismissed` is distinct from
    /// `findingResolved`: this is "an attempt happened and did NOT
    /// succeed," not silence. Gauntlet Loop, Gauntlet B round 13
    /// (2026-08-24): a fresh critic found `applyStagedFix`'s rejected/
    /// thrown branches produced zero Activity Log record at all, so
    /// `ActivityLogView`'s own claim to "prove what Voice Ledger ...
    /// submitted" was false for exactly the writes that mattered most to
    /// prove (the ones that didn't go through). The `note` field carries
    /// the rejection/error detail.
    case apiWriteRejected

    /// docs/VOICE_LEDGER_SPEC.md's Firm Cockpit Close Package section:
    /// "carry-forward items" — a human's explicit decision to defer an
    /// open finding to next period rather than resolve or dismiss it now.
    /// The `note` field carries the reason. Distinct from `findingDismissed`
    /// (that finding is judged not worth acting on at all); a carried-
    /// forward finding stays `.open` and keeps appearing on its normal
    /// pages — this mark only adds it to the Close Package's carry-forward
    /// list, it never changes `Finding.status`.
    case findingCarriedForward
    /// The reversal for `findingCarriedForward`.
    case findingCarryForwardRemoved

    /// A human-readable label, shared by every renderer of this enum.
    /// Gauntlet Loop, Gauntlet B round 5 (2026-08-24): `ClosePackageView`
    /// was rendering `entry.kind.rawValue` directly — the raw case name
    /// (e.g. "findingDismissed"), not even a formatted label — so this
    /// centralizes the mapping `ActivityLogView` already had.
    public var humanLabel: String {
        switch self {
        case .findingDetected: return "Finding detected"
        case .manualCompletionAttested: return "Manual completion attested"
        case .findingResolved: return "Finding resolved"
        case .apiWriteApplied: return "API write applied"
        case .apiWriteRejected: return "API write not confirmed"
        case .clientQuestionDrafted: return "Client question sent"
        case .clientQuestionAnswered: return "Client question answered"
        case .findingDismissed: return "Finding dismissed"
        case .clientMemoryRuleCreated: return "Client memory rule created"
        case .clientMemoryRuleRemoved: return "Client memory rule removed"
        case .findingAutoDismissedByClientMemory: return "Auto-dismissed (client memory)"
        case .findingCarriedForward: return "Carried forward to next period"
        case .findingCarryForwardRemoved: return "Carry-forward mark removed"
        }
    }

    /// docs/VOICE_LEDGER_SPEC.md's Firm Cockpit Close Package section:
    /// "corrections made" — a tracked ledger distinct from the full
    /// Activity Log. Single source of truth for which entry kinds actually
    /// represent a correction being made (not just detected, questioned,
    /// or administratively recorded), so `ClosePackageView`'s corrections
    /// section and any future caller agree on the same definition.
    /// `.manualCompletionAttested` counts even though it's attestation, not
    /// QBO-verified proof (`CLAUDE.md`: attestation is recorded, not
    /// treated as proof) — it's still the record of a real Branch B
    /// correction having been made, same as `.apiWriteApplied` is for
    /// Branch A.
    public var isCorrection: Bool {
        switch self {
        case .apiWriteApplied, .manualCompletionAttested:
            return true
        case .findingDetected, .findingResolved, .apiWriteRejected, .clientQuestionDrafted,
             .clientQuestionAnswered, .findingDismissed, .clientMemoryRuleCreated, .clientMemoryRuleRemoved,
             .findingAutoDismissedByClientMemory, .findingCarriedForward, .findingCarryForwardRemoved:
            return false
        }
    }
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
    /// A snapshot of `Finding.title` (or `.vendorName`) taken at the moment
    /// this entry is written — not a live lookup. Gauntlet Loop, Gauntlet B
    /// round 5 (2026-08-24): every entry carried `findingID`/`ruleID` as
    /// data, but no renderer (`ActivityLogView`, `ClosePackageView`, the
    /// exported Activity Log) ever displayed either, so a "Finding
    /// dismissed" row with no `note` was completely unidentifiable — two
    /// dismissals on the same day looked identical, in-app and in the
    /// exported Close Package alike. `nil` for entries that predate this
    /// field or aren't about a specific finding (e.g. `clientMemoryRuleCreated`).
    public let findingSummary: String?
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
        findingSummary: String? = nil,
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
        self.findingSummary = findingSummary
        self.note = note
        self.beforeSnapshotJSON = beforeSnapshotJSON
        self.afterSnapshotJSON = afterSnapshotJSON
    }
}
