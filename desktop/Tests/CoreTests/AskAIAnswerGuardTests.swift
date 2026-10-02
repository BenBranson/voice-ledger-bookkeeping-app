import Testing
import Foundation
@testable import Core

@Suite("Typed Ask AI answers are number-checked")
struct AskAIAnswerGuardTests {
    let source = "Notes Payable: USD 25000.00\nChecking: USD 3063.76\nPeriod: 2026-07"

    @Test("A sentence with a made-up figure is removed, the rest kept")
    func removesUnknownFigure() {
        let answer = "Notes Payable is $25,000.00 negative. Opening Balance Equity is $9,247.50. Fix Notes Payable first."
        let r = NumberGuard.scrubProse(ClientText.polish(answer), source: ClientText.polish(source))
        #expect(r.removedSentences == 1)
        #expect(!r.text.contains("9,247.50"))
        #expect(r.text.contains("$25,000.00"))
        #expect(r.text.contains("Fix Notes Payable first."))
        #expect(r.text.contains("1 sentence removed"))
    }

    @Test("Answers whose figures all come from the context pass untouched")
    func passesVerified() {
        let answer = "Checking is overdrawn by USD 3063.76.\n\nNotes Payable is USD 25000.00."
        let r = NumberGuard.scrubProse(answer, source: source)
        #expect(r.removedSentences == 0)
        #expect(r.text == answer)
    }

    @Test("Paragraph breaks survive")
    func keepsParagraphs() {
        let answer = "First point about $25,000.00.\n\nSecond point with $1,111.11."
        let r = NumberGuard.scrubProse(answer, source: ClientText.polish(source))
        #expect(r.text.hasPrefix("First point about $25,000.00.\n\n"))
        #expect(!r.text.contains("1,111.11"))
    }

    @Test("A fully unverifiable answer is withheld, not replaced by raw context")
    func withholds() {
        let r = NumberGuard.scrubProse("It is $9,999.99.", source: source)
        #expect(r.text.contains("withheld"))
    }

    @Test("Engine USD text is shown as dollars")
    func polishesDollars() {
        #expect(ClientText.polish("Notes Payable is -USD 4000.00 and USD 25000.00") == "Notes Payable is ($4,000.00) and $25,000.00")
    }

    @Test("Entries record what the books looked like and flag older data")
    func staleNote() {
        let e = AskAIConversationEntry(contextLabel: "x", tier: .primary, question: "q", answer: "a", period: "2026-07", openFindingCount: 17)
        #expect(e.dataLabel == "2026-07, 17 open findings")
        #expect(e.staleNote(currentPeriod: "2026-07", currentOpenCount: 17) == nil)
        #expect(e.staleNote(currentPeriod: "2026-07", currentOpenCount: 7)?.contains("17 open findings then, 7 now") == true)
        #expect(e.staleNote(currentPeriod: "2026-08", currentOpenCount: 17)?.contains("answered for 2026-07") == true)
        let old = AskAIConversationEntry(contextLabel: "x", tier: .primary, question: "q", answer: "a")
        #expect(old.dataLabel == nil && old.staleNote(currentPeriod: "2026-07", currentOpenCount: 1) == nil)
    }

    @Test("Entries saved before v1.53 still decode")
    func oldEntriesDecode() throws {
        let json = #"{"id":"1","askedAt":0,"contextLabel":"x","tier":"primary","question":"q","answer":"a"}"#
        let e = try JSONDecoder().decode(AskAIConversationEntry.self, from: Data(json.utf8))
        #expect(e.period == nil && e.openFindingCount == nil)
    }
}
