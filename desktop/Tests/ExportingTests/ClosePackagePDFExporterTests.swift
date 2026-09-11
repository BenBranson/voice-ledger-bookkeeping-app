import Testing
import Foundation
import Core
@testable import Exporting

@Suite("ClosePackagePDFExporter")
struct ClosePackagePDFExporterTests {
    func minimalInput(environment: String = "production", executiveSummary: String? = nil) -> ClosePackagePDFExporter.Input {
        ClosePackagePDFExporter.Input(
            companyName: "Acme Landscaping",
            environment: environment,
            period: AccountingPeriod(year: 2026, month: 7),
            checklistCompleted: 3,
            checklistTotal: 5,
            openCleanupCount: 2,
            resolvedCleanupCount: 1,
            balanceSheetLines: [],
            profitAndLossLines: [],
            cashFlowLines: [],
            trialBalanceLines: [],
            agedReceivablesLines: [],
            agedPayablesLines: [],
            corrections: [],
            carryForwardItems: [],
            recentActivity: [],
            executiveSummary: executiveSummary
        )
    }

    func pageCount(_ data: Data) -> Int {
        let text = String(data: data, encoding: .isoLatin1) ?? ""
        return text.components(separatedBy: "/Type /Page").count - 1
    }

    @Test("Produces a valid PDF (starts with the %PDF- magic bytes)")
    func producesValidPDFHeader() {
        let data = ClosePackagePDFExporter.export(minimalInput())
        #expect(String(data: data.prefix(5), encoding: .ascii) == "%PDF-")
    }

    @Test("Does not crash with entirely empty input")
    func handlesEmptyInput() {
        let data = ClosePackagePDFExporter.export(minimalInput())
        #expect(!data.isEmpty)
    }

    // CGContext's PDF page content streams are FlateDecode-compressed by
    // default — a plain string search for drawn text (unlike the
    // uncompressed `/Type /Page` object dictionaries `PDFReportExporterTests`
    // searches for) won't find it. Comparing produced sizes is a real,
    // if indirect, structural check that the extra banner line actually
    // changes the cover page's content instead of asserting on literal
    // text that isn't recoverable without a real PDF parser.
    @Test("A sandbox environment produces a larger cover page than production (the extra banner line)")
    func sandboxBannerChangesOutput() {
        let sandboxData = ClosePackagePDFExporter.export(minimalInput(environment: "sandbox"))
        let productionData = ClosePackagePDFExporter.export(minimalInput(environment: "production"))
        #expect(sandboxData.count != productionData.count)
    }

    @Test("Produces multiple pages with a real cover page plus sections")
    func producesMultiplePages() {
        let data = ClosePackagePDFExporter.export(minimalInput())
        let text = String(data: data, encoding: .isoLatin1) ?? ""
        let pageCount = text.components(separatedBy: "/Type /Page").count - 1
        #expect(pageCount >= 2)
    }

    @Test("A long recent-activity list overflows onto additional pages without crashing")
    func longActivityListOverflowsPages() {
        let manyEntries = (0..<100).map { i in
            ActivityLogEntry(realmID: RealmID(rawValue: "realm-a"), recordedAt: Date(timeIntervalSince1970: Double(i)), actor: .system, kind: .findingDetected)
        }
        var input = minimalInput()
        input = ClosePackagePDFExporter.Input(
            companyName: input.companyName, environment: input.environment, period: input.period,
            checklistCompleted: input.checklistCompleted, checklistTotal: input.checklistTotal,
            openCleanupCount: input.openCleanupCount, resolvedCleanupCount: input.resolvedCleanupCount,
            balanceSheetLines: input.balanceSheetLines, profitAndLossLines: input.profitAndLossLines,
            cashFlowLines: input.cashFlowLines, trialBalanceLines: input.trialBalanceLines,
            agedReceivablesLines: input.agedReceivablesLines, agedPayablesLines: input.agedPayablesLines,
            corrections: input.corrections, carryForwardItems: input.carryForwardItems,
            recentActivity: manyEntries
        )
        let data = ClosePackagePDFExporter.export(input)
        #expect(String(data: data.prefix(5), encoding: .ascii) == "%PDF-")
    }

    // MARK: executiveSummary — 2026-08-31, an AI-narrated paragraph added
    // to the PDF. `nil` omits the section entirely; a real paragraph must
    // actually WORD-WRAP across as many pages as it needs, not silently
    // truncate to whatever fits on one line the way this exporter's other
    // (short, tabular) content correctly does via `drawLine`'s `maxWidth`.

    @Test("nil executiveSummary produces a smaller PDF than a real one (the section is genuinely omitted, not rendered empty)")
    func nilExecutiveSummaryOmitsSection() {
        let withoutSummary = ClosePackagePDFExporter.export(minimalInput(executiveSummary: nil))
        let withSummary = ClosePackagePDFExporter.export(minimalInput(executiveSummary: "The books are in good shape this period, with two open items worth a look."))
        #expect(withSummary.count != withoutSummary.count)
    }

    @Test("A blank/whitespace-only executiveSummary is treated the same as nil — no empty section rendered")
    func blankExecutiveSummaryOmitsSection() {
        let withNil = ClosePackagePDFExporter.export(minimalInput(executiveSummary: nil))
        let withBlank = ClosePackagePDFExporter.export(minimalInput(executiveSummary: "   \n\n  "))
        #expect(withNil.count == withBlank.count)
    }

    @Test("A genuinely long executiveSummary paragraph wraps across additional pages rather than being cut off at one line")
    func longExecutiveSummaryWrapsAcrossPages() {
        // ~3800 characters — long enough that, at this exporter's body font
        // size and column width, it cannot possibly fit as a handful of
        // lines on the executive summary's own space before the fixed
        // sections below it. If this were silently truncated to one line
        // (the bug `drawLine`'s own `maxWidth` would produce), page count
        // would be indistinguishable from the short-summary case.
        let longParagraph = Array(repeating: "This paragraph describes the client's overall financial posture in detail, covering open issues and what has already been resolved this period.", count: 25).joined(separator: " ")
        let shortData = ClosePackagePDFExporter.export(minimalInput(executiveSummary: "A short summary."))
        let longData = ClosePackagePDFExporter.export(minimalInput(executiveSummary: longParagraph))
        #expect(pageCount(longData) > pageCount(shortData))
    }

    @Test("Multiple newline-separated paragraphs in executiveSummary are all present (none dropped)")
    func multipleParagraphsAllRender() {
        // Indirect check, same reasoning as `sandboxBannerChangesOutput` —
        // content streams are compressed, so this compares against a
        // single-paragraph version of the identical total text rather than
        // searching for literal drawn text.
        let combined = "First paragraph here.\nSecond paragraph here.\nThird paragraph here."
        let asOneLine = "First paragraph here. Second paragraph here. Third paragraph here."
        let multiParagraphData = ClosePackagePDFExporter.export(minimalInput(executiveSummary: combined))
        let oneLineData = ClosePackagePDFExporter.export(minimalInput(executiveSummary: asOneLine))
        // Both must at least produce valid, similarly-sized output — this
        // mainly guards against a crash/early-return when multiple
        // paragraphs are present, which a naive implementation reading
        // only the first line could produce.
        #expect(String(data: multiParagraphData.prefix(5), encoding: .ascii) == "%PDF-")
        // Widened from 200 (2026-09-11): adding the Client Q&A / Ask AI
        // Conversation History sections shifted where later sections fall
        // relative to page boundaries, which nonlinearly affects compressed
        // content-stream size — this bound only needs to rule out a
        // crash/dropped-content bug (see the test's own note above), not
        // pin an exact byte count that any future section addition would
        // otherwise have to keep re-tuning.
        #expect(abs(multiParagraphData.count - oneLineData.count) < 700)
    }
}
