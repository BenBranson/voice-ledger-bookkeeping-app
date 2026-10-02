import Foundation

/// docs/VOICE_LEDGER_SPEC.md's `/voice` module, filled in 2026-08-29 —
/// previously an empty placeholder (`VoicePlaceholder`), deliberately
/// deferred per Build Order item 12 ("Voice layer last, so a voice bug
/// never blocks anything else").
///
/// Ported from a design the owner already battle-tested in a separate app
/// (`Claude Voice Ledger`, `server/voiceSession.js`'s `VoiceSessionContext`)
/// — persisted conversational context so "why", "next", "that one", "go
/// back" work without the bookkeeper re-stating IDs. `Voice` depends only
/// on `Core` (this type's own module), never on `VoiceLedgerApp` — the app
/// layer translates this into real `AppState`/`Finding` lookups, the same
/// "UI-only vocabulary, app layer translates" pattern
/// `VoiceLedgerUI.ReportExportFormat` already uses.
public enum VoiceEntityType: String, Codable, Sendable {
    case finding
}

public struct VoiceEntityRef: Codable, Sendable, Equatable {
    public let type: VoiceEntityType
    public let id: String
    public let label: String?

    public init(type: VoiceEntityType, id: String, label: String? = nil) {
        self.type = type
        self.id = id
        self.label = label
    }
}

public enum VoiceConversationGoal: String, Codable, Sendable {
    case general
    case cleanup
    case monthEnd
}

/// A voice-initiated action awaiting an explicit spoken yes/no —
/// deliberately a CLOSED set of two kinds, both Voice Ledger's own
/// low-stakes internal state (never a QBO write; see `VoiceIntentRouter`'s
/// doc comment for why that boundary is structural, not a runtime check).
public struct VoicePendingAction: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable {
        case dismissFinding
        case completeChecklistItem
        /// "Did you mean …?" — a "yes" runs `commandText` as if it had been
        /// said. Navigation and read-only answers only (it re-enters the router).
        case runCommand
    }
    public let kind: Kind
    public let findingID: String?
    public let checklistItemID: String?
    /// What gets spoken back before asking for confirmation, e.g. "dismiss
    /// this finding" — composed once when the pending action is created,
    /// not reconstructed at confirm time.
    public let summary: String
    public let commandText: String?

    public init(kind: Kind, findingID: String? = nil, checklistItemID: String? = nil, summary: String, commandText: String? = nil) {
        self.commandText = commandText
        self.kind = kind
        self.findingID = findingID
        self.checklistItemID = checklistItemID
        self.summary = summary
    }
}

/// A name for the four states `VoiceSessionContext`'s existing fields
/// already distinguish — added 2026-08-29 to make the conversation's
/// current stage explicit rather than something every caller re-derives
/// ad hoc. Deliberately a COMPUTED property below, not a stored one: a
/// stored `stage` field would be a second source of truth that could
/// drift from `currentEntity`/`reviewQueue`/`pendingAction` if a call site
/// updated one but not the other. `awaitingConfirmation` takes priority
/// over `activeFinding` — a pending yes/no question is the more specific,
/// more urgent state even while a finding is still open on screen.
public enum VoiceStage: String, Sendable {
    case idle
    case reviewingSummary
    case activeFinding
    case awaitingConfirmation
}

public struct VoiceSessionContext: Codable, Sendable, Equatable {
    public var candidateFindingIDs: [String]?
    public var currentEntity: VoiceEntityRef?
    /// Ordered finding IDs — `ReviewQueue.build` produces this from real
    /// `[Finding]` data (severity, then dollar exposure, descending).
    public var reviewQueue: [String]
    public var reviewQueueIndex: Int?
    /// Most-recent-first, capped at 10 — mirrors the reference app's own
    /// `pushViewedEntity` cap. Lets "that one"/"open it" resolve without a
    /// restated id.
    public var lastViewedEntities: [VoiceEntityRef]
    public var pendingAction: VoicePendingAction?
    public var conversationGoal: VoiceConversationGoal
    /// Index of the current month-end walkthrough step; nil when none is running.
    public var routineStep: Int?

    public init(
        currentEntity: VoiceEntityRef? = nil,
        reviewQueue: [String] = [],
        reviewQueueIndex: Int? = nil,
        lastViewedEntities: [VoiceEntityRef] = [],
        pendingAction: VoicePendingAction? = nil,
        conversationGoal: VoiceConversationGoal = .general,
        routineStep: Int? = nil
    ) {
        self.routineStep = routineStep
        self.currentEntity = currentEntity
        self.reviewQueue = reviewQueue
        self.reviewQueueIndex = reviewQueueIndex
        self.lastViewedEntities = lastViewedEntities
        self.pendingAction = pendingAction
        self.conversationGoal = conversationGoal
    }

    public static let empty = VoiceSessionContext()

    public var stage: VoiceStage {
        if pendingAction != nil { return .awaitingConfirmation }
        if currentEntity != nil { return .activeFinding }
        if !reviewQueue.isEmpty { return .reviewingSummary }
        return .idle
    }

    /// Records that `entity` was just looked at — moves it to the front of
    /// `lastViewedEntities` (no duplicate), sets it as `currentEntity`, caps
    /// at 10. Pure — returns a new context, same immutable-update pattern
    /// every other Core type in this app uses.
    public func viewingEntity(_ entity: VoiceEntityRef) -> VoiceSessionContext {
        var copy = self
        var rest = lastViewedEntities.filter { $0.id != entity.id }
        rest.insert(entity, at: 0)
        copy.lastViewedEntities = Array(rest.prefix(10))
        copy.currentEntity = entity
        return copy
    }

    public func clearingPendingAction() -> VoiceSessionContext {
        var copy = self
        copy.pendingAction = nil
        return copy
    }
}
