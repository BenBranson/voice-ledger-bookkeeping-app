import Testing
@testable import Core

@Suite("ResolutionType.combinedNote")
struct ResolutionTypeTests {
    @Test("No type and no text produces nil, not an empty string")
    func noTypeNoTextIsNil() {
        #expect(ResolutionType.combinedNote(type: nil, detail: "") == nil)
        #expect(ResolutionType.combinedNote(type: nil, detail: "   ") == nil)
    }

    @Test("Text with no type is used verbatim, trimmed")
    func textOnlyIsUsedVerbatim() {
        #expect(ResolutionType.combinedNote(type: nil, detail: "  Fixed it manually.  ") == "Fixed it manually.")
    }

    @Test("Type with no text uses the type's own label")
    func typeOnlyUsesLabel() {
        #expect(ResolutionType.combinedNote(type: .reconciledAccount, detail: "") == "Reconciled Account")
        #expect(ResolutionType.combinedNote(type: .reconciledAccount, detail: "   ") == "Reconciled Account")
    }

    @Test("Type and text combine as 'Label: text'")
    func typeAndTextCombine() {
        #expect(ResolutionType.combinedNote(type: .reclassifiedTransaction, detail: "Moved $4,254 to the correct AR account.") == "Reclassified Transaction: Moved $4,254 to the correct AR account.")
    }

    @Test("Every case has a real, non-empty label")
    func everyCaseHasARealLabel() {
        for type in ResolutionType.allCases {
            #expect(!type.label.isEmpty)
        }
    }
}
