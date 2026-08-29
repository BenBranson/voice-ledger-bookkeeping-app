import Testing
import Foundation
@testable import Core

@Suite("ActivityLog")
struct ActivityLogTests {
    // Gauntlet Loop, Gauntlet B round 5 (2026-08-24): ActivityLogEntry
    // carried findingID/ruleID as data but no renderer ever displayed
    // either, so a dismissed/attested entry with no note was completely
    // unidentifiable in the Activity Log, the Close Package, and the
    // exported Activity Log alike. findingSummary is the fix — a snapshot
    // of Finding.title taken at write time.

    @Test("findingSummary defaults to nil — no regression for entries that predate this field")
    func findingSummaryDefaultsToNil() {
        let entry = ActivityLogEntry(realmID: RealmID(rawValue: "realm-a"), actor: .system, kind: .clientMemoryRuleCreated)
        #expect(entry.findingSummary == nil)
    }

    @Test("findingSummary round-trips through Codable")
    func findingSummaryRoundTripsThroughCodable() throws {
        let entry = ActivityLogEntry(
            realmID: RealmID(rawValue: "realm-a"),
            actor: .user("Amy"),
            kind: .findingDismissed,
            findingID: "f1",
            findingSummary: "Possible duplicate expense — Permian Supply, USD 486.20"
        )
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(ActivityLogEntry.self, from: data)
        #expect(decoded.findingSummary == entry.findingSummary)
    }

    @Test("Every ActivityKind has a human label distinct from its raw enum case name")
    func everyActivityKindHasAHumanLabel() {
        let kinds: [ActivityKind] = [
            .findingDetected, .manualCompletionAttested, .findingResolved, .apiWriteApplied,
            .apiWriteRejected, .apiWriteUnknown, .apiWriteUnknownResolved, .apiWriteAmbiguous,
            .clientQuestionDrafted, .clientQuestionAnswered, .findingDismissed,
            .clientMemoryRuleCreated, .clientMemoryRuleRemoved, .findingAutoDismissedByClientMemory,
            .findingCarriedForward, .findingCarryForwardRemoved
        ]
        for kind in kinds {
            #expect(!kind.humanLabel.isEmpty)
            #expect(kind.humanLabel != kind.rawValue, "\(kind.rawValue) should not be shown to a user as its raw case name")
        }
    }

    // Gauntlet Loop, Gauntlet B round 13 (2026-08-24): a rejected/unverified
    // staged write used to leave zero Activity Log record, so
    // ActivityLogView's own "can prove what Voice Ledger ... submitted"
    // claim was false for exactly the writes that mattered most to prove.
    @Test("apiWriteApplied and apiWriteRejected have distinct labels — a success is never confusable with a rejection in the log")
    func apiWriteAppliedAndRejectedAreDistinct() {
        #expect(ActivityKind.apiWriteApplied.humanLabel != ActivityKind.apiWriteRejected.humanLabel)
    }

    @Test("apiWriteRejected and apiWriteUnknown have distinct labels — a known clean failure is never confusable with a genuinely unknown outcome")
    func apiWriteRejectedAndUnknownAreDistinct() {
        #expect(ActivityKind.apiWriteRejected.humanLabel != ActivityKind.apiWriteUnknown.humanLabel)
    }

    @Test("apiWriteUnknownResolved and apiWriteAmbiguous have distinct labels — an automatically-resolved outcome is never confusable with one that needs a human")
    func apiWriteUnknownResolvedAndAmbiguousAreDistinct() {
        #expect(ActivityKind.apiWriteUnknownResolved.humanLabel != ActivityKind.apiWriteAmbiguous.humanLabel)
    }

    @Test("clientQuestionDrafted and clientQuestionAnswered have distinct labels — a sent question is never confusable with a recorded answer")
    func clientQuestionDraftedAndAnsweredAreDistinct() {
        #expect(ActivityKind.clientQuestionDrafted.humanLabel != ActivityKind.clientQuestionAnswered.humanLabel)
    }

    @Test("Actor.displayLabel names the user, not just 'a user'")
    func actorDisplayLabelNamesTheUser() {
        #expect(Actor.user("Amy").displayLabel == "By Amy")
        #expect(Actor.system.displayLabel == "By Voice Ledger")
    }

    @Test("isCorrection is true only for apiWriteApplied and manualCompletionAttested")
    func isCorrectionMatchesOnlyRealCorrections() {
        #expect(ActivityKind.apiWriteApplied.isCorrection)
        #expect(ActivityKind.manualCompletionAttested.isCorrection)
        let nonCorrections: [ActivityKind] = [
            .findingDetected, .findingResolved, .apiWriteRejected, .apiWriteUnknown,
            .apiWriteUnknownResolved, .apiWriteAmbiguous, .clientQuestionDrafted,
            .clientQuestionAnswered, .findingDismissed, .clientMemoryRuleCreated, .clientMemoryRuleRemoved,
            .findingAutoDismissedByClientMemory, .findingCarriedForward, .findingCarryForwardRemoved
        ]
        for kind in nonCorrections {
            #expect(!kind.isCorrection, "\(kind.rawValue) should not count as a correction")
        }
    }
}
