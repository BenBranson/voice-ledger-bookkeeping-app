import Testing
import Foundation
@testable import Core

@Suite("ClientQuestionDrafter")
struct ClientQuestionDrafterTests {
    func sampleFinding(ruleID: String = "VL-CC-PAYMENT-001") -> Finding {
        Finding(
            id: "abc123",
            ruleID: RuleID(rawValue: ruleID),
            ruleVersion: RuleVersion(major: 1, minor: 0, patch: 0),
            realmID: RealmID(rawValue: "realm-a"),
            period: AccountingPeriod(year: 2026, month: 7),
            title: "Credit card payment coded to Office Supplies — $750.00",
            severity: .high,
            confidence: .high,
            dollarExposure: Money(minorUnits: 75_000, currency: .usd),
            evidence: [],
            proposedActions: [],
            provenance: []
        )
    }

    @Test("The draft includes the finding's title and dollar exposure")
    func draftIncludesFindingDetails() {
        let text = ClientQuestionDrafter.draft(finding: sampleFinding(), clientName: nil)
        #expect(text.contains("Credit card payment coded to Office Supplies — $750.00"))
        #expect(text.contains("2026-07"))
    }

    @Test("A client name, when given, is used in the greeting")
    func clientNameUsedInGreeting() {
        let text = ClientQuestionDrafter.draft(finding: sampleFinding(), clientName: "Amy")
        #expect(text.hasPrefix("Hi Amy,"))
    }

    @Test("With no client name, the greeting has no trailing space before the comma")
    func noClientNameOmitsExtraSpace() {
        let text = ClientQuestionDrafter.draft(finding: sampleFinding(), clientName: nil)
        #expect(text.hasPrefix("Hi,"))
    }

    @Test("A recognized rule's accountingPrinciple is included")
    func includesAccountingPrincipleForKnownRule() {
        let text = ClientQuestionDrafter.draft(finding: sampleFinding(ruleID: "VL-CC-PAYMENT-001"), clientName: nil)
        #expect(text.contains("Why this matters:"))
    }

    @Test("An unrecognized ruleID does not crash — the principle line is simply omitted")
    func unknownRuleIDOmitsPrincipleLine() {
        let text = ClientQuestionDrafter.draft(finding: sampleFinding(ruleID: "VL-NOT-A-REAL-RULE"), clientName: nil)
        #expect(!text.contains("Why this matters:"))
    }

    // MARK: - Gauntlet Loop, Gauntlet B round 3 critic pass (2026-08-23) —
    // ClientQuestionDrafter is a second real consumer of Finding, and it
    // was still using the tier-invariant accountingPrinciple even after
    // narrative/riskIfIgnored/fieldValues were added for the finding
    // detail screen — for VL-DUP-EXP-001's T2 tier specifically, that meant
    // stating a date/account match to the CLIENT that never happened.

    func sampleFindingWithNarrative(narrative: String, title: String = "Possible duplicate expense — Permian Supply, USD 486.20") -> Finding {
        Finding(
            id: "abc123",
            ruleID: RuleID(rawValue: "VL-DUP-EXP-001"),
            ruleVersion: RuleVersion(major: 1, minor: 0, patch: 0),
            realmID: RealmID(rawValue: "realm-a"),
            period: AccountingPeriod(year: 2026, month: 7),
            title: title,
            severity: .high,
            confidence: .high,
            dollarExposure: Money(minorUnits: 48_620, currency: .usd),
            evidence: [],
            proposedActions: [],
            provenance: [],
            narrative: narrative
        )
    }

    @Test("When a finding has a narrative, the draft uses it instead of the tier-invariant accountingPrinciple — so a T2-style match never states a date/account overlap that didn't happen")
    func narrativePreferredOverAccountingPrinciple() {
        let narrative = "Two purchases from Permian Supply for USD 486.20 share the same reference number (REF-1) — dated 2026-7-1 and 2026-7-28."
        let text = ClientQuestionDrafter.draft(finding: sampleFindingWithNarrative(narrative: narrative), clientName: nil)
        #expect(text.contains(narrative))
        #expect(!text.contains("Why this matters:"), "the tier-invariant accountingPrinciple line should not appear when a tier-accurate narrative is available")
    }

    @Test("A finding with no narrative falls back to accountingPrinciple exactly as before — no regression for the other 16 rules")
    func fallsBackToAccountingPrincipleWhenNoNarrative() {
        let text = ClientQuestionDrafter.draft(finding: sampleFinding(), clientName: nil) // sampleFinding() has narrative: nil (default)
        #expect(text.contains("Why this matters:"))
    }

    @Test("A title that already embeds the dollar exposure (as VL-DUP-EXP-001's now does) is not followed by a duplicate dollar figure")
    func titleAlreadyContainingExposureIsNotDuplicated() {
        let narrative = "Two purchases from Permian Supply for USD 486.20 were both posted on 2026-7-14, from Checking — this looks like the same expense recorded twice."
        let text = ClientQuestionDrafter.draft(finding: sampleFindingWithNarrative(narrative: narrative), clientName: nil)
        #expect(!text.contains("USD 486.20 — USD 486.20"), "the dollar figure must not appear twice back-to-back")
    }

    @Test("A title that does NOT already embed the dollar exposure still gets it appended — no regression for rules whose title is amount-agnostic")
    func titleWithoutExposureStillGetsItAppended() {
        let text = ClientQuestionDrafter.draft(finding: sampleFinding(), clientName: nil) // "Credit card payment coded to Office Supplies — $750.00" doesn't contain "USD 750.00"
        #expect(text.contains("Credit card payment coded to Office Supplies — $750.00 — USD 750.00"))
    }
}

@Suite("ClientQuestionDrafter.Thread — Close Package Client Q&A aggregation")
struct ClientQuestionThreadTests {
    func entry(kind: ActivityKind, findingID: String?, findingSummary: String? = nil, note: String? = nil, recordedAt: Date) -> ActivityLogEntry {
        ActivityLogEntry(
            realmID: RealmID(rawValue: "realm-a"),
            recordedAt: recordedAt,
            actor: .user("Ben"),
            kind: kind,
            findingID: findingID,
            findingSummary: findingSummary,
            note: note
        )
    }

    @Test("A question with a matching answer pairs them into one thread")
    func questionAndAnswerPair() {
        let asked = Date(timeIntervalSince1970: 1000)
        let answered = Date(timeIntervalSince1970: 2000)
        let log = [
            entry(kind: .clientQuestionDrafted, findingID: "f1", findingSummary: "Duplicate expense", note: "Was this a duplicate?", recordedAt: asked),
            entry(kind: .clientQuestionAnswered, findingID: "f1", note: "No, two separate jobs.", recordedAt: answered)
        ]
        let threads = ClientQuestionDrafter.threads(from: log)
        #expect(threads.count == 1)
        #expect(threads[0].findingID == "f1")
        #expect(threads[0].question == "Was this a duplicate?")
        #expect(threads[0].answer == "No, two separate jobs.")
    }

    @Test("A question with no recorded answer yet still appears, with a nil answer")
    func questionAwaitingAnswer() {
        let log = [
            entry(kind: .clientQuestionDrafted, findingID: "f1", findingSummary: "Duplicate expense", note: "Was this a duplicate?", recordedAt: Date())
        ]
        let threads = ClientQuestionDrafter.threads(from: log)
        #expect(threads.count == 1)
        #expect(threads[0].answer == nil)
    }

    @Test("Only the most recent question and most recent answer per finding survive, not every historical round")
    func onlyLatestRoundPerFindingSurvives() {
        let log = [
            entry(kind: .clientQuestionDrafted, findingID: "f1", findingSummary: "Duplicate expense", note: "First question?", recordedAt: Date(timeIntervalSince1970: 100)),
            entry(kind: .clientQuestionAnswered, findingID: "f1", note: "First answer.", recordedAt: Date(timeIntervalSince1970: 200)),
            entry(kind: .clientQuestionDrafted, findingID: "f1", findingSummary: "Duplicate expense", note: "Second question?", recordedAt: Date(timeIntervalSince1970: 300)),
            entry(kind: .clientQuestionAnswered, findingID: "f1", note: "Second answer.", recordedAt: Date(timeIntervalSince1970: 400))
        ]
        let threads = ClientQuestionDrafter.threads(from: log)
        #expect(threads.count == 1)
        #expect(threads[0].question == "Second question?")
        #expect(threads[0].answer == "Second answer.")
    }

    @Test("Entries from two different findings produce two separate threads")
    func twoFindingsProduceTwoThreads() {
        let log = [
            entry(kind: .clientQuestionDrafted, findingID: "f1", findingSummary: "Finding One", note: "Q1?", recordedAt: Date(timeIntervalSince1970: 100)),
            entry(kind: .clientQuestionDrafted, findingID: "f2", findingSummary: "Finding Two", note: "Q2?", recordedAt: Date(timeIntervalSince1970: 200))
        ]
        let threads = ClientQuestionDrafter.threads(from: log)
        #expect(threads.count == 2)
    }

    @Test("Non-client-question activity log entries (e.g. findingResolved) are ignored entirely")
    func nonClientQuestionEntriesIgnored() {
        let log = [
            entry(kind: .findingResolved, findingID: "f1", findingSummary: "Finding One", recordedAt: Date())
        ]
        #expect(ClientQuestionDrafter.threads(from: log).isEmpty)
    }
}
