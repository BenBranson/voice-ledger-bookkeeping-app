import Testing
import Foundation
import Core
@testable import Exporting

@Suite("CSVReportExporter")
struct CSVReportExporterTests {
    func table() -> ExportTable {
        ExportTable(
            title: "Test Report",
            columns: ["Label", "Amount"],
            rows: [
                [ExportCell(text: "Rent"), ExportCell.money(Money(minorUnits: 150_000, currency: .usd))],
                [ExportCell(text: "Utilities, Water"), ExportCell.money(Money(minorUnits: 5_000, currency: .usd))]
            ],
            generatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    @Test("Header row matches the table's columns")
    func headerRowMatchesColumns() {
        let csv = String(data: CSVReportExporter.export(table()), encoding: .utf8)!
        let firstLine = csv.components(separatedBy: "\r\n").first!
        #expect(firstLine == "Label,Amount")
    }

    @Test("A field containing a comma is quoted per RFC 4180")
    func commaFieldIsQuoted() {
        let csv = String(data: CSVReportExporter.export(table()), encoding: .utf8)!
        #expect(csv.contains("\"Utilities, Water\""))
    }

    @Test("A numeric cell writes the raw number, not the formatted display string")
    func numericCellWritesRawNumber() {
        let csv = String(data: CSVReportExporter.export(table()), encoding: .utf8)!
        #expect(csv.contains("1500.0"))
        #expect(!csv.contains("$1,500.00"))
    }

    @Test("A quote inside a field is doubled and the field is quoted")
    func quoteInFieldIsDoubled() {
        let table = ExportTable(title: "T", columns: ["A"], rows: [[ExportCell(text: "She said \"hi\"")]])
        let csv = String(data: CSVReportExporter.export(table), encoding: .utf8)!
        #expect(csv.contains("\"She said \"\"hi\"\"\""))
    }

    @Test("Empty rows produce just the header line")
    func emptyRowsProduceHeaderOnly() {
        let table = ExportTable(title: "T", columns: ["A", "B"], rows: [])
        let csv = String(data: CSVReportExporter.export(table), encoding: .utf8)!
        #expect(csv.trimmingCharacters(in: .whitespacesAndNewlines) == "A,B")
    }
}
