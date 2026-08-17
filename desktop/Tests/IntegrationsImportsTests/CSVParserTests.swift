import Testing
@testable import IntegrationsImports

@Suite("CSVParser")
struct CSVParserTests {
    @Test("Parses a simple comma-delimited file with a header row")
    func parsesSimpleCSV() {
        let text = "Date,Description,Amount\n07/14/2026,PERMIAN SUPPLY,486.20\n07/15/2026,ODESSA WATER,120.00\n"
        let rows = CSVParser.parse(text)
        #expect(rows.count == 3)
        #expect(rows[0] == ["Date", "Description", "Amount"])
        #expect(rows[1] == ["07/14/2026", "PERMIAN SUPPLY", "486.20"])
        #expect(rows[2] == ["07/15/2026", "ODESSA WATER", "120.00"])
    }

    @Test("Handles a quoted field containing an embedded comma")
    func handlesQuotedFieldWithComma() {
        let text = "Date,Description,Amount\n07/14/2026,\"SUPPLY, PERMIAN INC\",486.20\n"
        let rows = CSVParser.parse(text)
        #expect(rows[1] == ["07/14/2026", "SUPPLY, PERMIAN INC", "486.20"])
    }

    @Test("Handles an escaped double-quote inside a quoted field")
    func handlesEscapedQuote() {
        let text = "Description\n\"Bob's \"\"Best\"\" Supply\"\n"
        let rows = CSVParser.parse(text)
        #expect(rows[1] == ["Bob's \"Best\" Supply"])
    }

    @Test("Handles CRLF line endings the same as LF")
    func handlesCRLF() {
        let text = "A,B\r\n1,2\r\n3,4\r\n"
        let rows = CSVParser.parse(text)
        #expect(rows == [["A", "B"], ["1", "2"], ["3", "4"]])
    }

    @Test("A file with no trailing newline still parses the last row")
    func noTrailingNewline() {
        let text = "A,B\n1,2"
        let rows = CSVParser.parse(text)
        #expect(rows == [["A", "B"], ["1", "2"]])
    }

    @Test("Empty input produces no rows")
    func emptyInput() {
        #expect(CSVParser.parse("").isEmpty)
    }
}
