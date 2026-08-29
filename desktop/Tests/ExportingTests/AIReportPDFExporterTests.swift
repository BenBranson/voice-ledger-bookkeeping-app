import Testing
import Foundation
import Core
@testable import Exporting

@Suite("AIReportPDFExporter")
struct AIReportPDFExporterTests {
    func input(environment: String = "production", bodyText: String = "This is a short report body.") -> AIReportPDFExporter.Input {
        AIReportPDFExporter.Input(
            reportTitle: "Book Health Report",
            companyName: "Acme Landscaping",
            environment: environment,
            period: AccountingPeriod(year: 2026, month: 7),
            providerLabel: "Gemma (local, free)",
            bodyText: bodyText
        )
    }

    @Test("Produces a valid PDF (starts with the %PDF- magic bytes)")
    func producesValidPDFHeader() {
        let data = AIReportPDFExporter.export(input())
        #expect(String(data: data.prefix(5), encoding: .ascii) == "%PDF-")
    }

    @Test("Does not crash or produce empty output with entirely empty body text")
    func handlesEmptyBodyText() {
        let data = AIReportPDFExporter.export(input(bodyText: ""))
        #expect(!data.isEmpty)
    }

    @Test("A sandbox environment produces a different (larger) page than production — the extra banner line")
    func sandboxBannerChangesOutput() {
        let sandboxData = AIReportPDFExporter.export(input(environment: "sandbox"))
        let productionData = AIReportPDFExporter.export(input(environment: "production"))
        #expect(sandboxData.count != productionData.count)
    }

    /// "/Type /Page" is a real substring of "/Type /Pages" too (the one
    /// Pages-tree root object every PDF has, regardless of leaf-page
    /// count) — a naive `components(separatedBy: "/Type /Page")` count is
    /// always inflated by exactly 1. Counting leaf pages only.
    private static func leafPageCount(in data: Data) -> Int {
        let text = String(data: data, encoding: .isoLatin1) ?? ""
        return text.components(separatedBy: "/Type /Pages").count - 1 == 0
            ? 0
            : text.components(separatedBy: "/Type /Page").count - 1 - (text.contains("/Type /Pages") ? 1 : 0)
    }

    @Test("A very long report body paginates across multiple PDF pages, not truncated onto one")
    func longBodyPaginates() {
        let longBody = Array(repeating: "This is a long paragraph of AI-generated report prose meant to force pagination across several pages of the exported document, repeated many times over to exceed a single page's capacity.", count: 60).joined(separator: "\n\n")
        let data = AIReportPDFExporter.export(input(bodyText: longBody))
        #expect(Self.leafPageCount(in: data) >= 2)
    }

    @Test("A short report body fits on one page")
    func shortBodyFitsOnePage() {
        let data = AIReportPDFExporter.export(input(bodyText: "A single short sentence."))
        #expect(Self.leafPageCount(in: data) == 1)
    }
}
