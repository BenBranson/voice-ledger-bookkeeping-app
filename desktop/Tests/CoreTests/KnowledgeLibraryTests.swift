import Testing
import Foundation
@testable import Core

@Suite("Bookkeeping knowledge library (ported from Talking Buddy)")
struct KnowledgeLibraryTests {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Knowledge")
    let library = KnowledgeLibrary.load(from: root)

    @Test("The notes load")
    func loads() { #expect(library.sectionCount > 60) }

    @Test("QuickBooks how-to questions find the right note")
    func finds() {
        #expect(library.search("how do I record a vendor credit or refund").contains { $0.note.lowercased().contains("vendor credit") })
        #expect(library.search("payments stuck in undeposited funds").contains { $0.note.lowercased().contains("undeposited") })
        #expect(library.search("do I need to file a 1099 for a contractor").contains { $0.note.contains("1099") })
    }

    @Test("Ordinary commands pull in no notes")
    func quietOnCommands() {
        #expect(library.search("go to dashboard").isEmpty)
        #expect(library.search("what's our revenue").isEmpty)
    }

    @Test("The reference block says client figures never come from the notes")
    func framing() {
        let block = KnowledgeLibrary.referenceBlock(library.search("how do I merge duplicate vendors"))
        #expect(block?.contains("never from these notes") == true)
    }

    @Test("Bookkeeping fundamentals answer everyday questions")
    func fundamentals() {
        func top(_ q: String) -> String { library.search(q).first?.note.lowercased() ?? "" }
        #expect(top("how long do I have to keep business records for the IRS").contains("records"))
        #expect(top("when is texas sales tax due for quarterly filers").contains("texas"))
        #expect(top("bank reconciliation difference divisible by 9 transposition").contains("reconciliation") || top("bank reconciliation difference divisible by 9 transposition").contains("error"))
        #expect(top("how do I split a loan payment between principal and interest").contains("loan") || top("how do I split a loan payment between principal and interest").contains("adjusting"))
        #expect(top("should this equipment purchase be capitalized or expensed de minimis").contains("capitalize"))
        #expect(top("what is the normal balance of accounts payable liability").contains("normal balance") || top("what is the normal balance of accounts payable liability").contains("double-entry"))
    }
}
