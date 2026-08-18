import Testing
@testable import IntegrationsImports

@Suite("OFXParser")
struct OFXParserTests {
    /// A realistic OFX 1.x SGML sample — leaf tags with NO closing tag,
    /// relying on the newline as the terminator, the common real-world case.
    static let sgmlSample = """
    OFXHEADER:100
    DATA:OFXSGML
    VERSION:102

    <OFX>
    <BANKMSGSRSV1>
    <STMTTRNRS>
    <STMTRS>
    <CURDEF>USD
    <BANKTRANLIST>
    <DTSTART>20260701
    <DTEND>20260731
    <STMTTRN>
    <TRNTYPE>DEBIT
    <DTPOSTED>20260714
    <TRNAMT>-486.20
    <FITID>202607140001
    <NAME>PERMIAN SUPPLY
    <MEMO>Check payment
    </STMTTRN>
    <STMTTRN>
    <TRNTYPE>CREDIT
    <DTPOSTED>20260715
    <TRNAMT>1200.00
    <FITID>202607150002
    <NAME>CLIENT DEPOSIT
    </STMTTRN>
    </BANKTRANLIST>
    </STMTRS>
    </STMTTRNRS>
    </BANKMSGSRSV1>
    </OFX>
    """

    @Test("Extracts both transactions from a real-shaped OFX 1.x SGML sample with no closing leaf tags")
    func parsesSGMLTransactions() {
        let transactions = OFXParser.parseTransactions(Self.sgmlSample)
        #expect(transactions.count == 2)
        #expect(transactions[0].fitID == "202607140001")
        #expect(transactions[0].datePosted == "20260714")
        #expect(transactions[0].amount == "-486.20")
        #expect(transactions[0].name == "PERMIAN SUPPLY")
        #expect(transactions[0].memo == "Check payment")
        #expect(transactions[0].transactionType == "DEBIT")
        #expect(transactions[1].fitID == "202607150002")
        #expect(transactions[1].name == "CLIENT DEPOSIT")
    }

    @Test("Also handles a variant WITH closing tags on the same line")
    func parsesWithClosingTags() {
        let text = """
        <STMTTRN>
        <DTPOSTED>20260714</DTPOSTED>
        <TRNAMT>-486.20</TRNAMT>
        <FITID>1001</FITID>
        <NAME>PERMIAN SUPPLY</NAME>
        </STMTTRN>
        """
        let transactions = OFXParser.parseTransactions(text)
        #expect(transactions.count == 1)
        #expect(transactions[0].datePosted == "20260714")
        #expect(transactions[0].amount == "-486.20")
        #expect(transactions[0].fitID == "1001")
        #expect(transactions[0].name == "PERMIAN SUPPLY")
    }

    @Test("A STMTTRN block missing DTPOSTED or TRNAMT is skipped, not half-produced")
    func skipsIncompleteBlock() {
        let text = """
        <STMTTRN>
        <FITID>1001</FITID>
        <NAME>NO DATE OR AMOUNT</NAME>
        </STMTTRN>
        """
        #expect(OFXParser.parseTransactions(text).isEmpty)
    }

    @Test("No STMTTRN blocks produces an empty result, not a crash")
    func noTransactionBlocks() {
        #expect(OFXParser.parseTransactions("<OFX><SIGNONMSGSRSV1></SIGNONMSGSRSV1></OFX>").isEmpty)
    }

    @Test("Extracts BALAMT/DTASOF from a LEDGERBAL block, no closing tags")
    func parsesLedgerBalance() {
        let text = """
        <LEDGERBAL>
        <BALAMT>1234.56
        <DTASOF>20260731
        </LEDGERBAL>
        """
        let balance = OFXParser.parseLedgerBalance(text)
        #expect(balance?.balanceAmount == "1234.56")
        #expect(balance?.asOfDate == "20260731")
    }

    @Test("A file with no LEDGERBAL block returns nil, not a defect")
    func noLedgerBalanceBlock() {
        #expect(OFXParser.parseLedgerBalance(Self.sgmlSample) == nil)
    }
}
