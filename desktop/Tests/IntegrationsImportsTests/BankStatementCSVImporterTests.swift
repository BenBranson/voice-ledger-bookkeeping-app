import Testing
import Foundation
import Core
@testable import IntegrationsImports

@Suite("BankStatementCSVImporter")
struct BankStatementCSVImporterTests {
    let realm = RealmID(rawValue: "9341456442848752")
    let docID = ImportedDocumentID(rawValue: "doc-1")

    func mappings(dateCol: Int = 0, descCol: Int? = 1, amountCol: Int = 2, confirmed: Bool = true) -> [ColumnMapping] {
        var result = [
            ColumnMapping(sourceColumn: dateCol, sourceHeader: "Date", target: .date, origin: .userSpecified, confirmed: confirmed),
            ColumnMapping(sourceColumn: amountCol, sourceHeader: "Amount", target: .amount, origin: .userSpecified, confirmed: confirmed)
        ]
        if let descCol {
            result.append(ColumnMapping(sourceColumn: descCol, sourceHeader: "Description", target: .description, origin: .userSpecified, confirmed: confirmed))
        }
        return result
    }

    @Test("A disambiguated MM/DD/YYYY column parses correctly and produces entityKind == .importedBankStatementLine")
    func parsesUnambiguousMonthDayColumn() {
        // Row 2's day (25) exceeds 12, disambiguating the whole column as MM/DD.
        let csv = "Date,Description,Amount\n07/14/2026,PERMIAN SUPPLY,486.20\n07/25/2026,ODESSA WATER,120.00\n"
        let result = BankStatementCSVImporter.import(csvText: csv, mappings: mappings(), hasHeaderRow: true, realmID: realm, documentID: docID, importedAt: Date())

        #expect(result.defects.isEmpty)
        #expect(result.transactions.count == 2)
        #expect(result.transactions[0].entityKind == .importedBankStatementLine)
        #expect(result.transactions[0].txnDate == AccountingDate(year: 2026, month: 7, day: 14))
        #expect(result.transactions[0].vendorName == "PERMIAN SUPPLY")
        #expect(result.transactions[0].totalAmount == Money(minorUnits: 48_620, currency: .usd))
    }

    @Test("A disambiguated DD/MM/YYYY column parses in day-month order")
    func parsesUnambiguousDayMonthColumn() {
        // Row 2's first component (25) exceeds 12, disambiguating as DD/MM.
        let csv = "Date,Description,Amount\n14/07/2026,PERMIAN SUPPLY,486.20\n25/07/2026,ODESSA WATER,120.00\n"
        let result = BankStatementCSVImporter.import(csvText: csv, mappings: mappings(), hasHeaderRow: true, realmID: realm, documentID: docID, importedAt: Date())

        #expect(result.defects.isEmpty)
        #expect(result.transactions[0].txnDate == AccountingDate(year: 2026, month: 7, day: 14))
        #expect(result.transactions[1].txnDate == AccountingDate(year: 2026, month: 7, day: 25))
    }

    @Test("A genuinely ambiguous date column (every day value <= 12) produces .ambiguousDateFormat, not a guess")
    func ambiguousDateColumnProducesDefect() {
        let csv = "Date,Description,Amount\n03/04/2026,PERMIAN SUPPLY,486.20\n01/02/2026,ODESSA WATER,120.00\n"
        let result = BankStatementCSVImporter.import(csvText: csv, mappings: mappings(), hasHeaderRow: true, realmID: realm, documentID: docID, importedAt: Date())

        #expect(result.transactions.isEmpty)
        guard case .ambiguousDateFormat(let column, _) = result.defects.first else {
            Issue.record("expected .ambiguousDateFormat, got \(result.defects)")
            return
        }
        #expect(column == "Date")
    }

    @Test("A parenthesized amount is treated as negative — the common bank-export debit convention")
    func parenthesizedAmountIsNegative() {
        let csv = "Date,Description,Amount\n07/14/2026,ATM WITHDRAWAL,(60.00)\n07/25/2026,DEPOSIT,500.00\n"
        let result = BankStatementCSVImporter.import(csvText: csv, mappings: mappings(), hasHeaderRow: true, realmID: realm, documentID: docID, importedAt: Date())

        #expect(result.transactions[0].totalAmount == Money(minorUnits: -6_000, currency: .usd))
        #expect(result.transactions[1].totalAmount == Money(minorUnits: 50_000, currency: .usd))
    }

    @Test("A dollar sign and thousands separator are stripped before parsing")
    func stripsDollarSignAndThousandsSeparator() {
        let csv = "Date,Description,Amount\n07/14/2026,PAYROLL,\"$1,234.56\"\n07/25/2026,X,120.00\n"
        let result = BankStatementCSVImporter.import(csvText: csv, mappings: mappings(), hasHeaderRow: true, realmID: realm, documentID: docID, importedAt: Date())

        #expect(result.transactions[0].totalAmount == Money(minorUnits: 123_456, currency: .usd))
    }

    @Test("An unmapped required field (amount) produces .requiredFieldUnmapped and imports nothing")
    func unmappedAmountProducesDefect() {
        let csv = "Date,Description,Amount\n07/14/2026,X,486.20\n07/25/2026,Y,120.00\n"
        let onlyDate = [ColumnMapping(sourceColumn: 0, sourceHeader: "Date", target: .date, origin: .userSpecified, confirmed: true)]
        let result = BankStatementCSVImporter.import(csvText: csv, mappings: onlyDate, hasHeaderRow: true, realmID: realm, documentID: docID, importedAt: Date())

        #expect(result.transactions.isEmpty)
        #expect(result.defects == [.requiredFieldUnmapped(target: .amount)])
    }

    @Test("An unconfirmed mapping is refused, not silently trusted")
    func unconfirmedMappingIsRefused() {
        let csv = "Date,Description,Amount\n07/14/2026,X,486.20\n07/25/2026,Y,120.00\n"
        let result = BankStatementCSVImporter.import(csvText: csv, mappings: mappings(confirmed: false), hasHeaderRow: true, realmID: realm, documentID: docID, importedAt: Date())

        #expect(result.transactions.isEmpty)
        #expect(result.defects == [.requiredMappingUnconfirmed(target: .date)])
    }

    @Test("An empty file produces .emptyFile and nothing else")
    func emptyFileProducesDefect() {
        let result = BankStatementCSVImporter.import(csvText: "", mappings: mappings(), hasHeaderRow: true, realmID: realm, documentID: docID, importedAt: Date())
        #expect(result.transactions.isEmpty)
        #expect(result.defects == [.emptyFile])
    }

    @Test("Every produced transaction carries Provenance.importedFile with the source documentID")
    func carriesImportedFileProvenance() {
        let csv = "Date,Description,Amount\n07/14/2026,X,486.20\n07/25/2026,Y,120.00\n"
        let result = BankStatementCSVImporter.import(csvText: csv, mappings: mappings(), hasHeaderRow: true, realmID: realm, documentID: docID, importedAt: Date())

        guard case .importedFile(let documentID, _, let method, _) = result.transactions[0].provenance else {
            Issue.record("expected .importedFile provenance")
            return
        }
        #expect(documentID == "doc-1")
        #expect(method == .deterministicParse)
    }
}
