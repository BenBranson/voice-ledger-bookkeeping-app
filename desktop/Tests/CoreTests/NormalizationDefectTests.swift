import Testing
@testable import Core

@Suite("NormalizationDefect")
struct NormalizationDefectTests {
    @Test("humanDescription is readable, not the raw enum dump, for every case")
    func humanDescriptionCoversEveryCase() {
        let cases: [NormalizationDefect] = [
            .ambiguousDateFormat(column: "Date", sampleValues: ["07/23/2026"]),
            .unparsableDate(row: 0, column: "Date", value: "NOTADATE"),
            .unparsableAmount(row: 0, column: "Amount", value: "abc"),
            .requiredMappingUnconfirmed(target: .date),
            .requiredFieldUnmapped(target: .amount),
            .emptyFile
        ]
        for defect in cases {
            #expect(!defect.humanDescription.isEmpty)
            #expect(!defect.humanDescription.contains("sampleValues:"), "should not look like a raw Swift enum dump: \(defect.humanDescription)")
        }
    }

    @Test("unparsableDate reports a 1-indexed row number, matching what a human sees in a spreadsheet")
    func unparsableDateUsesOneIndexedRow() {
        let defect = NormalizationDefect.unparsableDate(row: 0, column: "Date", value: "bad")
        #expect(defect.humanDescription.contains("Row 1"))
    }
}
