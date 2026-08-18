import Foundation
import Compression

/// A minimal ZIP reader for `XLSXParser` — the read-side counterpart to
/// `Exporting/ZIPArchiveWriter.swift`, which only ever writes its OWN
/// STORED-only archives and deliberately never needed a DEFLATE
/// implementation. This reader has to handle real-world input: a `.xlsx`
/// exported by Excel or Google Sheets uses DEFLATE (method 8), not STORED
/// (method 0), for its internal parts. Rather than hand-rolling inflate,
/// this uses Apple's system `Compression` framework — `COMPRESSION_ZLIB`'s
/// decode path implements raw DEFLATE with no zlib/gzip wrapper, which is
/// exactly what a ZIP entry's compressed bytes are (verified live against
/// real `zip`-produced archives, see `XLSXParserTests`).
enum ZIPArchiveReader {
    struct Entry {
        let path: String
        let contents: Data
    }

    enum ReadError: Error {
        case notAZipFile
        case unsupportedCompressionMethod(UInt16)
        case truncatedEntry(String)
        case decompressionFailed(String)
    }

    /// Reads every entry via the CENTRAL DIRECTORY (found by scanning
    /// backward for the End-Of-Central-Directory signature), not by
    /// walking local file headers sequentially — the central directory is
    /// the authoritative index per the ZIP spec, and some writers include
    /// data descriptors after an entry's data that would otherwise need
    /// separate handling if local headers were parsed one after another.
    static func readAll(_ data: Data) throws -> [Entry] {
        guard let eocdOffset = findEndOfCentralDirectory(data) else {
            throw ReadError.notAZipFile
        }
        let centralDirectoryOffset = Int(readUInt32LE(data, at: eocdOffset + 16))
        let entryCount = Int(readUInt16LE(data, at: eocdOffset + 10))

        var entries: [Entry] = []
        var cursor = centralDirectoryOffset
        for _ in 0..<entryCount {
            guard readUInt32LE(data, at: cursor) == 0x02014b50 else { break }
            let method = readUInt16LE(data, at: cursor + 10)
            let compressedSize = Int(readUInt32LE(data, at: cursor + 20))
            let nameLength = Int(readUInt16LE(data, at: cursor + 28))
            let extraLength = Int(readUInt16LE(data, at: cursor + 30))
            let commentLength = Int(readUInt16LE(data, at: cursor + 32))
            let localHeaderOffset = Int(readUInt32LE(data, at: cursor + 42))
            let nameStart = cursor + 46
            guard let name = String(data: data.subdata(in: nameStart..<(nameStart + nameLength)), encoding: .utf8) else {
                cursor = nameStart + nameLength + extraLength + commentLength
                continue
            }

            let contents = try readEntryData(
                data,
                localHeaderOffset: localHeaderOffset,
                compressedSize: compressedSize,
                method: method,
                path: name
            )
            entries.append(Entry(path: name, contents: contents))

            cursor = nameStart + nameLength + extraLength + commentLength
        }
        return entries
    }

    private static func readEntryData(_ data: Data, localHeaderOffset: Int, compressedSize: Int, method: UInt16, path: String) throws -> Data {
        guard readUInt32LE(data, at: localHeaderOffset) == 0x04034b50 else {
            throw ReadError.truncatedEntry(path)
        }
        // The local header repeats name/extra lengths, which can differ
        // from the central directory's copy (e.g. a Zip64 extra field only
        // present locally) — read them fresh rather than trusting the
        // central directory's values for locating the actual data.
        let localNameLength = Int(readUInt16LE(data, at: localHeaderOffset + 26))
        let localExtraLength = Int(readUInt16LE(data, at: localHeaderOffset + 28))
        let dataStart = localHeaderOffset + 30 + localNameLength + localExtraLength
        guard dataStart + compressedSize <= data.count else {
            throw ReadError.truncatedEntry(path)
        }
        let compressed = data.subdata(in: dataStart..<(dataStart + compressedSize))

        switch method {
        case 0:
            return compressed
        case 8:
            return try inflate(compressed, path: path)
        default:
            throw ReadError.unsupportedCompressionMethod(method)
        }
    }

    /// Apple's `COMPRESSION_ZLIB` algorithm, despite the name, decodes raw
    /// DEFLATE (no zlib 2-byte header, no Adler-32 trailer) — exactly a ZIP
    /// entry's method-8 bytes. Output buffer starts at 4x input size and
    /// doubles until decoding succeeds or a sane cap is hit, since the ZIP
    /// entry doesn't carry its uncompressed size to this call site in a
    /// way that's trustworthy to allocate exactly (central directory DOES
    /// have it, but a defensively-sized buffer costs nothing here).
    private static func inflate(_ compressed: Data, path: String) throws -> Data {
        var capacity = max(compressed.count * 4, 4096)
        let maxCapacity = 512 * 1024 * 1024
        while capacity <= maxCapacity {
            let result = compressed.withUnsafeBytes { (srcPtr: UnsafeRawBufferPointer) -> Data? in
                guard let srcBase = srcPtr.bindMemory(to: UInt8.self).baseAddress else { return nil }
                let dstBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
                defer { dstBuffer.deallocate() }
                let decodedCount = compression_decode_buffer(
                    dstBuffer, capacity,
                    srcBase, compressed.count,
                    nil, COMPRESSION_ZLIB
                )
                guard decodedCount > 0 else { return nil }
                return Data(bytes: dstBuffer, count: decodedCount)
            }
            if let result {
                return result
            }
            capacity *= 2
        }
        throw ReadError.decompressionFailed(path)
    }

    /// Scans backward from the end of the file for the EOCD signature
    /// rather than assuming it's at a fixed offset — a zip comment (rare,
    /// but legal, and some tools add one) shifts it. Searches at most the
    /// last 64KB + the fixed EOCD record size, per the zip spec's own
    /// maximum comment length.
    private static func findEndOfCentralDirectory(_ data: Data) -> Int? {
        let minEOCDSize = 22
        guard data.count >= minEOCDSize else { return nil }
        let searchStart = max(0, data.count - minEOCDSize - 65536)
        var i = data.count - minEOCDSize
        while i >= searchStart {
            if readUInt32LE(data, at: i) == 0x06054b50 {
                return i
            }
            i -= 1
        }
        return nil
    }

    private static func readUInt16LE(_ data: Data, at offset: Int) -> UInt16 {
        guard offset + 2 <= data.count else { return 0 }
        return UInt16(data[data.startIndex + offset]) | (UInt16(data[data.startIndex + offset + 1]) << 8)
    }

    private static func readUInt32LE(_ data: Data, at offset: Int) -> UInt32 {
        guard offset + 4 <= data.count else { return 0 }
        return UInt32(data[data.startIndex + offset])
            | (UInt32(data[data.startIndex + offset + 1]) << 8)
            | (UInt32(data[data.startIndex + offset + 2]) << 16)
            | (UInt32(data[data.startIndex + offset + 3]) << 24)
    }
}
