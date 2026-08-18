import Foundation

/// A minimal ZIP writer producing STORED (uncompressed) entries only.
/// STORED is a fully valid entry method per the ZIP spec — Excel, Google
/// Sheets, and every archive tool accept it — and choosing it deliberately
/// avoids needing a DEFLATE implementation: this writer only ever creates
/// its OWN files (for `XLSXReportExporter`), never reads arbitrary ones, so
/// there's no need to handle compressed input at all. Deliberately not a
/// general-purpose zip library — just enough to produce a valid .xlsx.
enum ZIPArchiveWriter {
    struct Entry {
        let path: String
        let contents: Data
    }

    /// CRC-32 (ISO 3309 / ITU-T V.42), the polynomial ZIP itself specifies.
    /// Table-based, computed once per process.
    private static let crcTable: [UInt32] = {
        (0...255).map { i -> UInt32 in
            var c = UInt32(i)
            for _ in 0..<8 {
                c = (c & 1 != 0) ? (0xEDB88320 ^ (c >> 1)) : (c >> 1)
            }
            return c
        }
    }()

    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            let index = Int((crc ^ UInt32(byte)) & 0xFF)
            crc = crcTable[index] ^ (crc >> 8)
        }
        return crc ^ 0xFFFFFFFF
    }

    /// Builds the complete archive: local file header + data per entry, in
    /// order, followed by the central directory and end-of-central-
    /// directory record. DOS date/time is fixed (not "now") — an export's
    /// byte content should be deterministic for the same input, matching
    /// this project's general preference for reproducible output; nothing
    /// downstream reads a zip entry's timestamp anyway.
    static func write(_ entries: [Entry]) -> Data {
        var body = Data()
        var centralDirectory = Data()
        var offset: UInt32 = 0

        for entry in entries {
            let nameData = Data(entry.path.utf8)
            let crc = crc32(entry.contents)
            let size = UInt32(entry.contents.count)

            var localHeader = Data()
            localHeader.append(le32(0x04034b50))       // local file header signature
            localHeader.append(le16(20))                // version needed to extract
            localHeader.append(le16(0))                 // flags
            localHeader.append(le16(0))                 // method: 0 = stored
            localHeader.append(le16(0))                 // mod time
            localHeader.append(le16(0x21))               // mod date (a fixed, valid DOS date)
            localHeader.append(le32(crc))
            localHeader.append(le32(size))               // compressed size == size (stored)
            localHeader.append(le32(size))               // uncompressed size
            localHeader.append(le16(UInt16(nameData.count)))
            localHeader.append(le16(0))                  // extra field length
            localHeader.append(nameData)

            body.append(localHeader)
            body.append(entry.contents)

            var centralEntry = Data()
            centralEntry.append(le32(0x02014b50))        // central directory header signature
            centralEntry.append(le16(20))                 // version made by
            centralEntry.append(le16(20))                 // version needed to extract
            centralEntry.append(le16(0))                  // flags
            centralEntry.append(le16(0))                  // method: stored
            centralEntry.append(le16(0))                  // mod time
            centralEntry.append(le16(0x21))
            centralEntry.append(le32(crc))
            centralEntry.append(le32(size))
            centralEntry.append(le32(size))
            centralEntry.append(le16(UInt16(nameData.count)))
            centralEntry.append(le16(0))                  // extra field length
            centralEntry.append(le16(0))                  // comment length
            centralEntry.append(le16(0))                  // disk number start
            centralEntry.append(le16(0))                  // internal attributes
            centralEntry.append(le32(0))                  // external attributes
            centralEntry.append(le32(offset))             // relative offset of local header
            centralEntry.append(nameData)

            centralDirectory.append(centralEntry)
            offset += UInt32(localHeader.count + entry.contents.count)
        }

        var end = Data()
        end.append(le32(0x06054b50))                     // end of central directory signature
        end.append(le16(0))                               // disk number
        end.append(le16(0))                               // disk with central directory
        end.append(le16(UInt16(entries.count)))           // entries on this disk
        end.append(le16(UInt16(entries.count)))           // total entries
        end.append(le32(UInt32(centralDirectory.count)))  // size of central directory
        end.append(le32(offset))                          // offset of central directory
        end.append(le16(0))                               // comment length

        return body + centralDirectory + end
    }

    private static func le16(_ value: UInt16) -> Data {
        Data([UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF)])
    }

    private static func le32(_ value: UInt32) -> Data {
        Data([
            UInt8(value & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 24) & 0xFF)
        ])
    }
}
