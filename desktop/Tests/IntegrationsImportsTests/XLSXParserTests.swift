import Testing
import Foundation
import Compression
@testable import IntegrationsImports

/// Builds a minimal, valid ZIP archive (STORED entries only — this file's
/// own throwaway writer, deliberately not reusing `Exporting`'s, to keep
/// this test target's dependencies untouched) so `XLSXParser.parse` can be
/// tested end-to-end without needing a real `.xlsx` file on disk. The
/// separate DEFLATE-specific test below exercises the compressed path
/// these fixtures don't, using the system `Compression` framework's own
/// encoder as an independent producer of real DEFLATE bytes.
private enum TestZipWriter {
    static func write(_ entries: [(path: String, contents: Data)]) -> Data {
        var body = Data()
        var central = Data()
        var offset: UInt32 = 0
        for entry in entries {
            let name = Data(entry.path.utf8)
            let size = UInt32(entry.contents.count)
            var local = Data()
            local.append(le32(0x04034b50)); local.append(le16(20)); local.append(le16(0)); local.append(le16(0))
            local.append(le16(0)); local.append(le16(0x21))
            local.append(le32(0)); local.append(le32(size)); local.append(le32(size))
            local.append(le16(UInt16(name.count))); local.append(le16(0))
            local.append(name)
            body.append(local)
            body.append(entry.contents)

            var centralEntry = Data()
            centralEntry.append(le32(0x02014b50)); centralEntry.append(le16(20)); centralEntry.append(le16(20))
            centralEntry.append(le16(0)); centralEntry.append(le16(0)); centralEntry.append(le16(0)); centralEntry.append(le16(0x21))
            centralEntry.append(le32(0)); centralEntry.append(le32(size)); centralEntry.append(le32(size))
            centralEntry.append(le16(UInt16(name.count))); centralEntry.append(le16(0)); centralEntry.append(le16(0))
            centralEntry.append(le16(0)); centralEntry.append(le16(0)); centralEntry.append(le32(0))
            centralEntry.append(le32(offset))
            centralEntry.append(name)
            central.append(centralEntry)
            offset += UInt32(local.count + entry.contents.count)
        }
        var end = Data()
        end.append(le32(0x06054b50)); end.append(le16(0)); end.append(le16(0))
        end.append(le16(UInt16(entries.count))); end.append(le16(UInt16(entries.count)))
        end.append(le32(UInt32(central.count))); end.append(le32(offset)); end.append(le16(0))
        return body + central + end
    }
    private static func le16(_ v: UInt16) -> Data { Data([UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF)]) }
    private static func le32(_ v: UInt32) -> Data { Data([UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8((v >> 24) & 0xFF)]) }
}

@Suite("XLSXParser")
struct XLSXParserTests {
    static let workbookXML = Data("""
    <workbook xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Sheet1" sheetId="1" r:id="rId1"/></sheets></workbook>
    """.utf8)

    static let relsXML = Data("""
    <Relationships><Relationship Id="rId1" Type=".../worksheet" Target="worksheets/sheet1.xml"/></Relationships>
    """.utf8)

    static let sharedStringsXML = Data("""
    <sst><si><t>Date</t></si><si><t>VL Spike Permian Supply</t></si><si><r><t>Office</t></r><r><t> Depot</t></r></si></sst>
    """.utf8)

    static let stylesXML = Data("""
    <styleSheet><cellXfs count="2"><xf numFmtId="0"/><xf numFmtId="14"/></cellXfs></styleSheet>
    """.utf8)

    @Test("End-to-end: resolves the first sheet via workbook.xml/rels, converts a date-styled numeric cell using the real Excel epoch, and reads shared + rich-text strings")
    func parsesFullArchiveEndToEnd() throws {
        // Row 1: headers (shared strings 0, blank). Row 2: date-styled
        // serial 46228 (independently computed: days from 1899-12-30 to
        // 2026-07-25 via Python's datetime — matches this project's usual
        // cross-check-with-an-independent-tool discipline), shared string 1
        // (name), and a plain numeric amount with no style.
        let sheetXML = Data("""
        <worksheet><sheetData>
        <row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1" t="s"><v>2</v></c></row>
        <row r="2"><c r="A2" s="1"><v>46228</v></c><c r="B2" t="s"><v>1</v></c><c r="C2"><v>120.00</v></c></row>
        </sheetData></worksheet>
        """.utf8)

        let archive = TestZipWriter.write([
            (path: "xl/workbook.xml", contents: Self.workbookXML),
            (path: "xl/_rels/workbook.xml.rels", contents: Self.relsXML),
            (path: "xl/worksheets/sheet1.xml", contents: sheetXML),
            (path: "xl/sharedStrings.xml", contents: Self.sharedStringsXML),
            (path: "xl/styles.xml", contents: Self.stylesXML)
        ])

        let rows = try XLSXParser.parse(archive)
        #expect(rows.count == 2)
        #expect(rows[0] == ["Date", "Office Depot"])
        #expect(rows[1][0] == "07/25/2026")
        #expect(rows[1][1] == "VL Spike Permian Supply")
        #expect(rows[1][2] == "120.00")
    }

    @Test("A row with a skipped (blank) middle column is padded so later columns still line up positionally")
    func skippedColumnIsPaddedNotShifted() throws {
        let sheetXML = Data("""
        <worksheet><sheetData>
        <row r="1"><c r="A1"><v>1</v></c><c r="C1"><v>3</v></c></row>
        </sheetData></worksheet>
        """.utf8)
        let archive = TestZipWriter.write([
            (path: "xl/workbook.xml", contents: Self.workbookXML),
            (path: "xl/_rels/workbook.xml.rels", contents: Self.relsXML),
            (path: "xl/worksheets/sheet1.xml", contents: sheetXML)
        ])
        let rows = try XLSXParser.parse(archive)
        #expect(rows == [["1", "", "3"]])
    }

    @Test("parseSharedStrings concatenates multiple rich-text runs within one <si> into one string")
    func sharedStringsConcatenatesRichTextRuns() {
        let strings = XLSXParser.parseSharedStrings(Self.sharedStringsXML)
        #expect(strings == ["Date", "VL Spike Permian Supply", "Office Depot"])
    }

    @Test("parseDateStyleIndices flags built-in date numFmtId 14 but not the default General format")
    func dateStyleIndicesFlagsBuiltInDateFormat() {
        let indices = XLSXParser.parseDateStyleIndices(Self.stylesXML)
        #expect(indices == [1])
    }

    @Test("A legacy .xls (OLE2/CFB magic bytes) throws unsupportedLegacyFormat, not a confusing zip error")
    func legacyXLSThrowsClearError() {
        let oleHeader = Data([0xD0, 0xCF, 0x11, 0xE0, 0x00, 0x00, 0x00, 0x00])
        #expect(throws: XLSXParser.ParseError.unsupportedLegacyFormat) {
            try XLSXParser.parse(oleHeader)
        }
    }

    @Test("Genuinely non-zip garbage throws notAZipFile")
    func garbageDataThrowsNotAZipFile() {
        let garbage = Data([0x01, 0x02, 0x03, 0x04])
        #expect(throws: (any Error).self) {
            try XLSXParser.parse(garbage)
        }
    }

    @Test("Real DEFLATE round-trip via the system Compression encoder — independent of any external zip tool — proves ZIPArchiveReader.inflate correctly decodes method-8 entries")
    func deflateRoundTripViaSystemEncoder() throws {
        let original = Data("""
        <worksheet><sheetData><row r="1"><c r="A1"><v>42</v></c></row></sheetData></worksheet>
        """.utf8)

        let compressed = try #require(Self.deflate(original))
        #expect(compressed.count < original.count) // sanity: it actually compressed something

        // Hand-build a single-entry zip with method 8 (deflate) and the
        // real compressed size, so ZIPArchiveReader must decompress it to
        // get the right answer, not just pass bytes through.
        let name = Data("test.xml".utf8)
        var localHeader = Data()
        localHeader.append(Self.le32(0x04034b50))
        localHeader.append(Self.le16(20))
        localHeader.append(Self.le16(0))
        localHeader.append(Self.le16(8)) // method: deflate
        localHeader.append(Self.le16(0))
        localHeader.append(Self.le16(0x21))
        localHeader.append(Self.le32(0))
        localHeader.append(Self.le32(UInt32(compressed.count)))
        localHeader.append(Self.le32(UInt32(original.count)))
        localHeader.append(Self.le16(UInt16(name.count)))
        localHeader.append(Self.le16(0))
        localHeader.append(name)

        var central = Data()
        central.append(Self.le32(0x02014b50))
        central.append(Self.le16(20)); central.append(Self.le16(20)); central.append(Self.le16(0))
        central.append(Self.le16(8)); central.append(Self.le16(0)); central.append(Self.le16(0x21))
        central.append(Self.le32(0))
        central.append(Self.le32(UInt32(compressed.count)))
        central.append(Self.le32(UInt32(original.count)))
        central.append(Self.le16(UInt16(name.count))); central.append(Self.le16(0)); central.append(Self.le16(0))
        central.append(Self.le16(0)); central.append(Self.le16(0)); central.append(Self.le32(0))
        central.append(Self.le32(0))
        central.append(name)

        let offset = UInt32(localHeader.count + compressed.count)
        var end = Data()
        end.append(Self.le32(0x06054b50)); end.append(Self.le16(0)); end.append(Self.le16(0))
        end.append(Self.le16(1)); end.append(Self.le16(1))
        end.append(Self.le32(UInt32(central.count))); end.append(Self.le32(offset)); end.append(Self.le16(0))

        let archive = localHeader + compressed + central + end
        let entries = try ZIPArchiveReader.readAll(archive)
        #expect(entries.count == 1)
        #expect(entries[0].contents == original)
    }

    private static func deflate(_ data: Data) -> Data? {
        data.withUnsafeBytes { (srcPtr: UnsafeRawBufferPointer) -> Data? in
            guard let srcBase = srcPtr.bindMemory(to: UInt8.self).baseAddress else { return nil }
            let capacity = data.count + 128
            let dstBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
            defer { dstBuffer.deallocate() }
            let count = compression_encode_buffer(dstBuffer, capacity, srcBase, data.count, nil, COMPRESSION_ZLIB)
            guard count > 0 else { return nil }
            return Data(bytes: dstBuffer, count: count)
        }
    }
    private static func le16(_ v: UInt16) -> Data { Data([UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF)]) }
    private static func le32(_ v: UInt32) -> Data { Data([UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8((v >> 24) & 0xFF)]) }
}
