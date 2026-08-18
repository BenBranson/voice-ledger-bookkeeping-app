import Testing
import Foundation
@testable import Exporting

@Suite("ZIPArchiveWriter")
struct ZIPArchiveWriterTests {
    @Test("crc32 matches the well-known test vector for the ASCII string \"123456789\"")
    func crc32MatchesKnownVector() {
        // The standard CRC-32 (ISO-3309/ITU-T V.42, same polynomial ZIP uses)
        // check value for "123456789" is 0xCBF43926 — used across every
        // CRC-32 implementation's own test suite as the canonical vector.
        let crc = ZIPArchiveWriter.crc32(Data("123456789".utf8))
        #expect(crc == 0xCBF43926)
    }

    @Test("crc32 of empty data is 0")
    func crc32OfEmptyDataIsZero() {
        #expect(ZIPArchiveWriter.crc32(Data()) == 0)
    }

    @Test("Written archive starts with the local file header signature")
    func archiveStartsWithLocalFileHeaderSignature() {
        let data = ZIPArchiveWriter.write([.init(path: "test.txt", contents: Data("hello".utf8))])
        #expect(data.count >= 4)
        let signature = data.prefix(4)
        #expect(Array(signature) == [0x50, 0x4b, 0x03, 0x04])
    }

    @Test("Written archive ends with the end-of-central-directory signature")
    func archiveEndsWithEndOfCentralDirectorySignature() {
        let data = ZIPArchiveWriter.write([.init(path: "test.txt", contents: Data("hello".utf8))])
        // EOCD record is 22 bytes with no comment — its signature is the
        // first 4 bytes of that trailing block.
        let eocd = data.suffix(22).prefix(4)
        #expect(Array(eocd) == [0x50, 0x4b, 0x05, 0x06])
    }

    @Test("A STORED entry's bytes appear verbatim right after its local file header (no compression)")
    func storedEntryBytesAppearVerbatim() {
        let contents = Data("the quick brown fox".utf8)
        let data = ZIPArchiveWriter.write([.init(path: "a.txt", contents: contents)])
        // Local file header is 30 bytes + filename length ("a.txt" = 5 bytes).
        let headerSize = 30 + 5
        let start = data.index(data.startIndex, offsetBy: headerSize)
        let end = data.index(start, offsetBy: contents.count)
        let extracted = data.subdata(in: start..<end)
        #expect(extracted == contents)
    }

    @Test("Multiple entries each appear in the archive and the entry count is recorded correctly")
    func multipleEntriesRecordedCorrectly() {
        let data = ZIPArchiveWriter.write([
            .init(path: "one.xml", contents: Data("<a/>".utf8)),
            .init(path: "two.xml", contents: Data("<b/>".utf8))
        ])
        // Entry count (total entries) is a 2-byte field 10 bytes into the EOCD record.
        let eocd = data.suffix(22)
        let countBytes = eocd.dropFirst(10).prefix(2)
        let count = UInt16(countBytes.first!) | (UInt16(countBytes.dropFirst().first!) << 8)
        #expect(count == 2)
    }
}
