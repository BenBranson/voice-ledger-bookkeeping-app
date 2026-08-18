import Testing
import Foundation
import Core
@testable import Exporting

@Suite("XLSXReportExporter")
struct XLSXReportExporterTests {
    func table() -> ExportTable {
        ExportTable(
            title: "Balance Sheet",
            columns: ["Label", "Amount"],
            rows: [
                [ExportCell(text: "Checking"), ExportCell.money(Money(minorUnits: 123_456, currency: .usd))]
            ]
        )
    }

    @Test("columnLetter converts a 0-indexed column to spreadsheet letters")
    func columnLetterConvertsCorrectly() {
        #expect(XLSXReportExporter.columnLetter(0) == "A")
        #expect(XLSXReportExporter.columnLetter(25) == "Z")
        #expect(XLSXReportExporter.columnLetter(26) == "AA")
        #expect(XLSXReportExporter.columnLetter(27) == "AB")
    }

    @Test("Produces a valid ZIP (starts with the local file header signature)")
    func producesValidZipSignature() {
        let data = XLSXReportExporter.export(table())
        #expect(Array(data.prefix(4)) == [0x50, 0x4b, 0x03, 0x04])
    }

    @Test("Contains all five required OOXML parts")
    func containsRequiredParts() {
        let data = XLSXReportExporter.export(table())
        let text = String(data: data, encoding: .isoLatin1) ?? ""
        for path in ["[Content_Types].xml", "_rels/.rels", "xl/workbook.xml", "xl/_rels/workbook.xml.rels", "xl/worksheets/sheet1.xml"] {
            #expect(text.contains(path), "missing \(path)")
        }
    }

    @Test("A numeric cell is written as a real number, not an inline string")
    func numericCellIsRealNumber() {
        let data = XLSXReportExporter.export(table())
        let text = String(data: data, encoding: .isoLatin1) ?? ""
        #expect(text.contains("<c r=\"B2\"><v>1234.56</v></c>"))
    }

    @Test("A text cell is written as an inline string")
    func textCellIsInlineString() {
        let data = XLSXReportExporter.export(table())
        let text = String(data: data, encoding: .isoLatin1) ?? ""
        #expect(text.contains("t=\"inlineStr\""))
        #expect(text.contains("<t xml:space=\"preserve\">Checking</t>"))
    }

    @Test("XML special characters in cell text are escaped")
    func xmlSpecialCharactersAreEscaped() {
        let table = ExportTable(title: "T", columns: ["A"], rows: [[ExportCell(text: "Tom & Jerry <ltd>")]])
        let data = XLSXReportExporter.export(table)
        let text = String(data: data, encoding: .isoLatin1) ?? ""
        #expect(text.contains("Tom &amp; Jerry &lt;ltd&gt;"))
    }

    @Test("A sheet title longer than 31 characters or with invalid characters is sanitized")
    func sheetTitleIsSanitized() {
        let table = ExportTable(title: "This/Title:Has*Invalid[Characters]And?IsWayTooLongForExcel", columns: ["A"], rows: [])
        let data = XLSXReportExporter.export(table)
        let text = String(data: data, encoding: .isoLatin1) ?? ""
        #expect(!text.contains(":Has"))
        #expect(!text.contains("*Invalid"))
    }
}
