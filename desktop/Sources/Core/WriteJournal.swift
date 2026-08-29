import Foundation

/// docs/VOICE_LEDGER_HANDOFF.md D4: "Three-phase write journal with
/// explicit `UNKNOWN`." Built 2026-08-29 — previously "still fully
/// PLANNED... this machinery has no caller yet."
///
/// **The real gap this closes**: before this, `AppState.applyStagedFix`'s
/// `catch` block treated EVERY thrown error identically — a clean HTTP
/// rejection and "the network dropped after the request was sent, before
/// any response arrived" were both logged as `.apiWriteRejected` with the
/// SAME "the call failed before QBO could respond" message. That message
/// is simply not knowable to be true for the second case: the request may
/// have reached QBO and applied before the connection died. Treating that
/// as a known-clean failure invited a retry that could double-apply the
/// write. `.unknown` is the honest third state D4 describes — and it
/// BLOCKS further writes to the same entity until a resolution probe
/// settles it, rather than leaving that judgment to whoever clicks retry.
public enum WriteJournalState: String, Codable, Sendable {
    /// Persisted BEFORE the network call is made — the record that a
    /// write was ABOUT to be attempted survives even a crash between
    /// writing this and the call returning.
    case submitted
    /// The network call returned and confirmed the write landed as
    /// intended (QBO's own round-trip verification, `WriteVerificationResult
    /// .verified == true`).
    case success
    /// The network call returned an answer that is NOT ambiguous — either
    /// QBO's round-trip check found `verified == false`, or a resolution
    /// probe found the entity's `SyncToken` unchanged from before the
    /// write attempt (D4's load-bearing evidence: an unchanged SyncToken
    /// means nothing landed). Safe to retry.
    case failed
    /// The network call never returned an answer at all — thrown before
    /// `WriteVerificationResult` could be parsed. Genuinely don't know
    /// whether the write landed. **Never retried automatically.** Blocks
    /// all further writes to the same entity until a resolution probe
    /// (`WriteJournalResolution.resolve`) settles it.
    case unknown
    /// A resolution probe found the entity's `SyncToken` DID change since
    /// the write attempt, but not to the intended target value — something
    /// happened, but not what was expected. D4: "escalates to the human —
    /// never guessed." Terminal: nothing auto-resolves an `.ambiguous`
    /// entry.
    case ambiguous
}

/// One pending or resolved write attempt against a specific Purchase line.
/// `id` is `"<purchaseID>:<lineID>"` — deliberately the entity key, not a
/// random UUID, so a lookup for "is there already a pending write against
/// THIS line" is a dictionary/array lookup by a value the caller already
/// has, not a separate index to keep in sync.
public struct WriteJournalEntry: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public let findingID: String
    public let purchaseID: String
    public let lineID: String
    /// The `SyncToken` read BEFORE the write attempt — the probe's
    /// baseline. Never the token from any later read.
    public let syncTokenBeforeWrite: String
    public let targetAccountID: String
    public let submittedAt: Date
    public var state: WriteJournalState
    public var resolvedAt: Date?
    /// Set only when a resolution probe (not the original network call)
    /// determined the final state — a plain-English note of what the
    /// probe found, for the Activity Log entry this produces.
    public var resolutionNote: String?

    public init(
        findingID: String, purchaseID: String, lineID: String, syncTokenBeforeWrite: String,
        targetAccountID: String, submittedAt: Date = Date(), state: WriteJournalState = .submitted,
        resolvedAt: Date? = nil, resolutionNote: String? = nil
    ) {
        self.id = "\(purchaseID):\(lineID)"
        self.findingID = findingID
        self.purchaseID = purchaseID
        self.lineID = lineID
        self.syncTokenBeforeWrite = syncTokenBeforeWrite
        self.targetAccountID = targetAccountID
        self.submittedAt = submittedAt
        self.state = state
        self.resolvedAt = resolvedAt
        self.resolutionNote = resolutionNote
    }
}

/// Pure resolution logic — no I/O. The caller fetches the entity's
/// CURRENT `SyncToken`/account and passes them in; this function only
/// decides what they mean.
public enum WriteJournalResolution {
    /// docs/VOICE_LEDGER_HANDOFF.md D4: "The probe's load-bearing step: an
    /// unchanged SyncToken is strong evidence the write did not land,
    /// since any successful write increments it. An AMBIGUOUS outcome
    /// escalates to the human — never guessed."
    ///
    /// - `currentSyncToken == nil`: the entity couldn't be found at all on
    ///   resync (deleted? never existed at that ID?) — not safely
    ///   resolvable automatically, so `.ambiguous`, not a guess either way.
    /// - unchanged `SyncToken`: `.failed` — the write did not land, safe
    ///   to retry.
    /// - changed `SyncToken` AND the current account matches what was
    ///   intended: `.success` — it landed, just too late for the original
    ///   call to observe it.
    /// - changed `SyncToken` but the account does NOT match what was
    ///   intended: `.ambiguous` — something else happened to this line
    ///   (a human edit, a different write) between the attempt and the
    ///   probe; guessing which is wrong is worse than asking.
    public static func resolve(entry: WriteJournalEntry, currentSyncToken: String?, currentAccountID: String?) -> WriteJournalState {
        guard let currentSyncToken else { return .ambiguous }
        guard currentSyncToken != entry.syncTokenBeforeWrite else { return .failed }
        return currentAccountID == entry.targetAccountID ? .success : .ambiguous
    }
}
