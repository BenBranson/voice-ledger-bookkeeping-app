import Foundation

/// Owner directive (2026-08-29): "when I open a client's books in QBO...
/// for every finding I can mark what I did to resolve it. The app should
/// keep and retain all those markings... and use that to help report the
/// actions I took." Deliberately NOT a new persisted field/database table
/// — the existing attestation `note` (already on `AppState.attestCompletion`,
/// already flowing into `AskAIContext.composeValueSummary`'s "ACTIONS
/// TAKEN" section via the Activity Log) is already the real record. This
/// is just a short, common-case label the UI offers alongside that free-
/// text field, so a quick "Mark as Done" isn't a bare, undescribed click —
/// combined with the owner's own free text into that same note, never a
/// second source of truth.
public enum ResolutionType: String, CaseIterable, Codable, Sendable, Identifiable {
    case matchedToBankFeed
    case reclassifiedTransaction
    case reconciledAccount
    case adjustedJournalEntry
    case correctedInQBO
    case clientClarificationNeeded
    case other

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .matchedToBankFeed: return "Matched to Bank Feed"
        case .reclassifiedTransaction: return "Reclassified Transaction"
        case .reconciledAccount: return "Reconciled Account"
        case .adjustedJournalEntry: return "Adjusted Journal Entry"
        case .correctedInQBO: return "Corrected in QBO"
        case .clientClarificationNeeded: return "Client Clarification Needed"
        case .other: return "Other"
        }
    }

    /// Combines a selected type with the bookkeeper's own free-text detail
    /// into the single string `attestCompletion`'s `note` parameter
    /// actually stores. `nil` when there's nothing to say at all (no type
    /// chosen and no text typed) — an empty note stays `nil`, not an empty
    /// string, matching how every other optional note in this app behaves.
    public static func combinedNote(type: ResolutionType?, detail: String) -> String? {
        let trimmedDetail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        switch (type, trimmedDetail.isEmpty) {
        case (nil, true): return nil
        case (nil, false): return trimmedDetail
        case (.some(let type), true): return type.label
        case (.some(let type), false): return "\(type.label): \(trimmedDetail)"
        }
    }
}

/// Why a finding was dismissed — required, so "not an error" is always
/// explained in the work log and the client report.
public enum DismissReason: String, CaseIterable, Codable, Sendable, Identifiable {
    case legitimate, immaterial, handledOutsideQBO, duplicateFinding, other

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .legitimate: return "Not an error — legitimate transaction"
        case .immaterial: return "Too small to be worth correcting"
        case .handledOutsideQBO: return "Handled outside QuickBooks"
        case .duplicateFinding: return "Already covered by another finding"
        case .other: return "Other"
        }
    }

    /// `nil` until the reason is complete (Other needs an explanation).
    public static func note(reason: DismissReason?, detail: String) -> String? {
        let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let reason else { return nil }
        if reason == .other { return trimmed.isEmpty ? nil : "Other: \(trimmed)" }
        return trimmed.isEmpty ? reason.label : "\(reason.label): \(trimmed)"
    }
}
