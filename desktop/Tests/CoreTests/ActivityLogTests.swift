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
            .clientQuestionDrafted, .findingDismissed, .clientMemoryRuleCreated,
            .clientMemoryRuleRemoved, .findingAutoDismissedByClientMemory
        ]
        for kind in kinds {
            #expect(!kind.humanLabel.isEmpty)
            #expect(kind.humanLabel != kind.rawValue, "\(kind.rawValue) should not be shown to a user as its raw case name")
        }
    }

    @Test("Actor.displayLabel names the user, not just 'a user'")
    func actorDisplayLabelNamesTheUser() {
        #expect(Actor.user("Amy").displayLabel == "By Amy")
        #expect(Actor.system.displayLabel == "By Voice Ledger")
    }
}
