import Testing
import Foundation
import Core
@testable import IntegrationsImports

@Suite("OFXBankStatementImporter")
struct OFXBankStatementImporterTests {
    let realm = RealmID(rawValue: "9341456442848752")
    let docID = ImportedDocumentID(rawValue: "doc-ofx-1")

    @Test("Parses a real-shaped OFX sample into LedgerTransaction with entityKind == .importedBankStatementLine")
    func importsOFXTransactions() {
        let result = OFXBankStatementImporter.import(ofxText: OFXParserTests.sgmlSample, realmID: realm, documentID: docID, importedAt: Date())

        #expect(result.defects.isEmpty)
        #expect(result.transactions.count == 2)
        #expect(result.transactions[0].entityKind == .importedBankStatementLine)
        #expect(result.transactions[0].id == "doc-ofx-1-202607140001")
        #expect(result.transactions[0].txnDate == AccountingDate(year: 2026, month: 7, day: 14))
        #expect(result.transactions[0].vendorName == "PERMIAN SUPPLY")
        #expect(result.transactions[0].totalAmount == Money(minorUnits: -48_620, currency: .usd))
        #expect(result.transactions[1].totalAmount == Money(minorUnits: 120_000, currency: .usd))
    }

    @Test("statementAccountID is stored as paymentAccountID on every produced line")
    func storesStatementAccountID() {
        let result = OFXBankStatementImporter.import(ofxText: OFXParserTests.sgmlSample, realmID: realm, documentID: docID, importedAt: Date(), statementAccountID: "checking-1")
        #expect(result.transactions.allSatisfy { $0.paymentAccountID == "checking-1" })
    }

    @Test("A FITID-less transaction falls back to a row-index id, still unique")
    func fallsBackToRowIndexWithoutFITID() {
        let text = """
        <STMTTRN>
        <DTPOSTED>20260714
        <TRNAMT>-100.00
        <NAME>NO FITID
        </STMTTRN>
        """
        let result = OFXBankStatementImporter.import(ofxText: text, realmID: realm, documentID: docID, importedAt: Date())
        #expect(result.transactions.first?.id == "doc-ofx-1-row0")
    }

    @Test("An empty file produces .emptyFile")
    func emptyFileProducesDefect() {
        let result = OFXBankStatementImporter.import(ofxText: "", realmID: realm, documentID: docID, importedAt: Date())
        #expect(result.transactions.isEmpty)
        #expect(result.defects == [.emptyFile])
        #expect(result.statedEndingBalance == nil)
        #expect(result.statedAsOfDate == nil)
    }

    @Test("A file with a LEDGERBAL block surfaces statedEndingBalance/statedAsOfDate — extraction only, not compared against the transactions")
    func surfacesStatedEndingBalance() {
        let text = OFXParserTests.sgmlSample + "\n<LEDGERBAL>\n<BALAMT>5000.00\n<DTASOF>20260731\n</LEDGERBAL>"
        let result = OFXBankStatementImporter.import(ofxText: text, realmID: realm, documentID: docID, importedAt: Date())
        #expect(result.statedEndingBalance == Money(minorUnits: 500_000, currency: .usd))
        #expect(result.statedAsOfDate == AccountingDate(year: 2026, month: 7, day: 31))
    }

    @Test("A file with no LEDGERBAL block leaves statedEndingBalance nil, not a defect")
    func noLedgerBalanceLeavesFieldsNil() {
        let result = OFXBankStatementImporter.import(ofxText: OFXParserTests.sgmlSample, realmID: realm, documentID: docID, importedAt: Date())
        #expect(result.defects.isEmpty)
        #expect(result.statedEndingBalance == nil)
        #expect(result.statedAsOfDate == nil)
    }

    @Test("An unparsable date produces .unparsableDate and skips that transaction, not the whole file")
    func unparsableDateSkipsOnlyThatTransaction() {
        let text = """
        <STMTTRN>
        <DTPOSTED>NOTADATE
        <TRNAMT>-100.00
        <FITID>1001
        </STMTTRN>
        <STMTTRN>
        <DTPOSTED>20260714
        <TRNAMT>-50.00
        <FITID>1002
        </STMTTRN>
        """
        let result = OFXBankStatementImporter.import(ofxText: text, realmID: realm, documentID: docID, importedAt: Date())
        #expect(result.transactions.count == 1)
        #expect(result.transactions[0].id == "doc-ofx-1-1002")
        guard case .unparsableDate = result.defects.first else {
            Issue.record("expected .unparsableDate, got \(result.defects)")
            return
        }
    }
}
