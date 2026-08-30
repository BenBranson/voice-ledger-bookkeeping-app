import Testing
import Foundation
import Core
@testable import Exporting

@Suite("ReportHistoryLogger")
struct ReportHistoryLoggerTests {
    func tempRoot() -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("Writes a real, readable text file with the report body")
    func writesTextFile() throws {
        let root = tempRoot()
        ReportHistoryLogger.append(
            reportTitle: "Book Health Report",
            companyName: "Acme Landscaping",
            environment: "sandbox",
            period: AccountingPeriod(year: 2026, month: 7),
            providerLabel: "Gemma (local, free)",
            bodyText: "The books are in good shape this period.",
            baseDirectory: root
        )
        let fileURL = root.appending(path: "Voice Ledger Reports/Acme Landscaping/Book Health Report.txt")
        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        #expect(contents.contains("Book Health Report"))
        #expect(contents.contains("Acme Landscaping"))
        #expect(contents.contains("The books are in good shape this period."))
        #expect(contents.contains("SANDBOX"))
    }

    @Test("A second generation appends to the same file rather than overwriting it")
    func appendsRatherThanOverwrites() throws {
        let root = tempRoot()
        let input: (String) -> Void = { body in
            ReportHistoryLogger.append(
                reportTitle: "Book Health Report",
                companyName: "Acme Landscaping",
                environment: "sandbox",
                period: AccountingPeriod(year: 2026, month: 7),
                providerLabel: "Gemma (local, free)",
                bodyText: body,
                baseDirectory: root
            )
        }
        input("First month's report.")
        input("Second month's report.")

        let fileURL = root.appending(path: "Voice Ledger Reports/Acme Landscaping/Book Health Report.txt")
        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        #expect(contents.contains("First month's report."))
        #expect(contents.contains("Second month's report."))
    }

    @Test("Production environment does not print the SANDBOX note")
    func productionOmitsSandboxNote() throws {
        let root = tempRoot()
        ReportHistoryLogger.append(
            reportTitle: "Book Health Report",
            companyName: "Acme Landscaping",
            environment: "production",
            period: AccountingPeriod(year: 2026, month: 7),
            providerLabel: "Gemma (local, free)",
            bodyText: "Real client data.",
            baseDirectory: root
        )
        let fileURL = root.appending(path: "Voice Ledger Reports/Acme Landscaping/Book Health Report.txt")
        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        #expect(!contents.contains("SANDBOX"))
    }

    @Test("Different report titles for the same client go to different files")
    func differentReportTitlesGoToDifferentFiles() throws {
        let root = tempRoot()
        ReportHistoryLogger.append(reportTitle: "Book Health Report", companyName: "Acme Landscaping", environment: "sandbox", period: AccountingPeriod(year: 2026, month: 7), providerLabel: "Gemma (local, free)", bodyText: "Health.", baseDirectory: root)
        ReportHistoryLogger.append(reportTitle: "Client Value Summary", companyName: "Acme Landscaping", environment: "sandbox", period: AccountingPeriod(year: 2026, month: 7), providerLabel: "Gemma (local, free)", bodyText: "Value.", baseDirectory: root)

        let healthContents = try String(contentsOf: root.appending(path: "Voice Ledger Reports/Acme Landscaping/Book Health Report.txt"), encoding: .utf8)
        let valueContents = try String(contentsOf: root.appending(path: "Voice Ledger Reports/Acme Landscaping/Client Value Summary.txt"), encoding: .utf8)
        #expect(healthContents.contains("Health."))
        #expect(!healthContents.contains("Value."))
        #expect(valueContents.contains("Value."))
        #expect(!valueContents.contains("Health."))
    }
}
