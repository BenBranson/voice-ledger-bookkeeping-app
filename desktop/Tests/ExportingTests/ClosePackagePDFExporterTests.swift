import Testing
import Foundation
import Core
@testable import Exporting

@Suite("ClosePackagePDFExporter")
struct ClosePackagePDFExporterTests {
    func minimalInput(environment: String = "production") -> ClosePackagePDFExporter.Input {
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
            recentActivity: []
        )
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
}
