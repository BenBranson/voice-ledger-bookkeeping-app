import Testing
import Foundation
import Core
@testable import Exporting

@Suite("PDFReportExporter")
struct PDFReportExporterTests {
    @Test("Produces a valid PDF (starts with the %PDF- magic bytes)")
    func producesValidPDFHeader() {
        let table = ExportTable(title: "Test", columns: ["A", "B"], rows: [[ExportCell(text: "x"), ExportCell(text: "y")]])
        let data = PDFReportExporter.export(table)
        let header = String(data: data.prefix(5), encoding: .ascii)
        #expect(header == "%PDF-")
    }

    @Test("Does not crash on an empty table")
    func handlesEmptyTable() {
        let table = ExportTable(title: "Empty", columns: ["A"], rows: [])
        let data = PDFReportExporter.export(table)
        #expect(!data.isEmpty)
        #expect(String(data: data.prefix(5), encoding: .ascii) == "%PDF-")
    }

    @Test("Produces multiple pages when there are enough rows to overflow one page")
    func producesMultiplePagesForManyRows() {
        let manyRows = (0..<200).map { [ExportCell(text: "Row \($0)"), ExportCell(text: "value")] }
        let table = ExportTable(title: "Long Report", columns: ["Label", "Value"], rows: manyRows)
        let data = PDFReportExporter.export(table)
        let text = String(data: data, encoding: .isoLatin1) ?? ""
        // Every page object declares /Type /Page — a crude but reliable
        // signal of page count without a real PDF parser.
        let pageCount = text.components(separatedBy: "/Type /Page").count - 1
        #expect(pageCount > 1)
    }
}
