import Foundation

/// docs/VOICE_LEDGER_SPEC.md's Tier 1 ingestion list includes Excel
/// (`.xlsx`/`.xls`) alongside CSV/OFX/QFX — this is that parser. `.xls`
/// (the pre-2007 binary format) is explicitly NOT supported: it's a
/// different binary container entirely (OLE2/CFB, not ZIP+XML), and real
/// bank exports overwhelmingly use `.xlsx` today; `parse` throws a clear
/// `.unsupportedLegacyFormat` rather than silently misreading it as a zip.
///
/// Produces the SAME `[[String]]` row shape `CSVParser.parse` does, so it
/// plugs directly into the existing `BankStatementCSVImporter.import(rows:...)`
/// and confirm-and-correct UI unchanged — a bank statement's cells are the
/// same "rows of text" regardless of which file format they arrived in.
///
/// Reads only the FIRST worksheet (resolved via `workbook.xml`'s sheet
/// order and `workbook.xml.rels`, not assumed to be literally named
/// `sheet1.xml` — a workbook can reorder/rename sheets) — a bank statement
/// export is a single-sheet file in practice, and Voice Ledger's import
/// flow has no UI for picking among multiple sheets. No formulas, no
/// merged-cell handling, no styles beyond the date-format detection below.
public enum XLSXParser {
    public enum ParseError: Error, Equatable {
        case notAZipFile
        case unsupportedLegacyFormat
        case missingWorkbook
        case missingWorksheet
        case malformedXML(String)
    }

    public static func parse(_ data: Data) throws -> [[String]] {
        if data.count >= 8, data[data.startIndex] == 0xD0, data[data.startIndex + 1] == 0xCF {
            // OLE2/CFB magic number (D0 CF 11 E0 ...) — a real legacy .xls.
            throw ParseError.unsupportedLegacyFormat
        }

        let entries: [ZIPArchiveReader.Entry]
        do {
            entries = try ZIPArchiveReader.readAll(data)
        } catch ZIPArchiveReader.ReadError.notAZipFile {
            throw ParseError.notAZipFile
        }
        var byPath: [String: Data] = [:]
        for entry in entries { byPath[entry.path] = entry.contents }

        guard let workbookXML = byPath["xl/workbook.xml"] else {
            throw ParseError.missingWorkbook
        }
        let firstSheetRID = try Self.firstSheetRelationshipID(workbookXML)

        let sheetPath: String
        if let rID = firstSheetRID, let relsXML = byPath["xl/_rels/workbook.xml.rels"],
           let target = Self.relationshipTarget(relsXML, id: rID) {
            sheetPath = target.hasPrefix("/") ? String(target.dropFirst()) : "xl/\(target)"
        } else {
            // Fallback for a workbook.xml.rels this parser couldn't read —
            // sheet1.xml is the overwhelmingly common real-world name for
            // a single-sheet export, but this path is a fallback, not the
            // primary resolution strategy.
            sheetPath = "xl/worksheets/sheet1.xml"
        }
        guard let sheetXML = byPath[sheetPath] else {
            throw ParseError.missingWorksheet
        }

        let sharedStrings = byPath["xl/sharedStrings.xml"].map { Self.parseSharedStrings($0) } ?? []
        let dateStyleIndices = byPath["xl/styles.xml"].map { Self.parseDateStyleIndices($0) } ?? []

        return try Self.parseSheet(sheetXML, sharedStrings: sharedStrings, dateStyleIndices: dateStyleIndices)
    }

    // MARK: - workbook.xml / rels

    private static func firstSheetRelationshipID(_ xml: Data) throws -> String? {
        final class Delegate: NSObject, XMLParserDelegate {
            var firstRID: String?
            func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
                guard firstRID == nil, elementName == "sheet" else { return }
                firstRID = attributeDict["r:id"] ?? attributeDict["r:embedId"]
            }
        }
        let delegate = Delegate()
        let parser = XMLParser(data: xml)
        parser.delegate = delegate
        guard parser.parse() else { throw ParseError.malformedXML("workbook.xml") }
        return delegate.firstRID
    }

    private static func relationshipTarget(_ xml: Data, id: String) -> String? {
        final class Delegate: NSObject, XMLParserDelegate {
            let wantedID: String
            var target: String?
            init(wantedID: String) { self.wantedID = wantedID }
            func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
                guard elementName == "Relationship", attributeDict["Id"] == wantedID else { return }
                target = attributeDict["Target"]
            }
        }
        let delegate = Delegate(wantedID: id)
        let parser = XMLParser(data: xml)
        parser.delegate = delegate
        _ = parser.parse()
        return delegate.target
    }

    // MARK: - sharedStrings.xml

    /// Each `<si>` can hold either a plain `<t>` or multiple rich-text
    /// `<r><t>...</t></r>` runs (formatting changes mid-string) — all `<t>`
    /// text within one `<si>` is concatenated, matching how Excel itself
    /// renders it as one cell value.
    static func parseSharedStrings(_ xml: Data) -> [String] {
        final class Delegate: NSObject, XMLParserDelegate {
            var strings: [String] = []
            private var currentText = ""
            private var insideSI = false
            private var insideT = false

            func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
                if elementName == "si" { insideSI = true; currentText = "" }
                if elementName == "t" { insideT = true }
            }
            func parser(_ parser: XMLParser, foundCharacters string: String) {
                if insideSI && insideT { currentText += string }
            }
            func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
                if elementName == "t" { insideT = false }
                if elementName == "si" { strings.append(currentText); insideSI = false }
            }
        }
        let delegate = Delegate()
        let parser = XMLParser(data: xml)
        parser.delegate = delegate
        _ = parser.parse()
        return delegate.strings
    }

    // MARK: - styles.xml (date-format detection)

    /// Built-in ECMA-376 date numFmtIds (14-17, 22 — the standard short/
    /// long date and date+time formats; 18-21/45-47 are time-only/elapsed,
    /// deliberately excluded — a bank statement date column is a date, not
    /// a time-of-day). A custom numFmt (id >= 164, defined in this same
    /// file) counts as a date only if its format code contains a
    /// date-pattern letter (y/m/d) and no `0`/`#` numeric-only marker,
    /// which would indicate a plain number format that happens to reuse
    /// those letters is not the case in practice for `y`/`d` (only `m` is
    /// ambiguous with "minutes," which is why `y` or `d` alone is the
    /// signal checked for, not `m` alone).
    static func parseDateStyleIndices(_ xml: Data) -> Set<Int> {
        final class Delegate: NSObject, XMLParserDelegate {
            var customDateFormatIDs: Set<Int> = []
            var dateStyleIndices: Set<Int> = []
            private var cellXfsDepth = 0
            private var xfIndex = -1

            func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
                switch elementName {
                case "numFmt":
                    if let idString = attributeDict["numFmtId"], let id = Int(idString),
                       let code = attributeDict["formatCode"] {
                        let lower = code.lowercased()
                        let looksLikeDate = (lower.contains("y") || lower.contains("d")) && !lower.contains("#") && !lower.contains("0.0")
                        if looksLikeDate { customDateFormatIDs.insert(id) }
                    }
                case "cellXfs":
                    cellXfsDepth += 1
                case "xf":
                    guard cellXfsDepth > 0 else { return }
                    xfIndex += 1
                    if let idString = attributeDict["numFmtId"], let id = Int(idString) {
                        let builtInDateIDs: Set<Int> = [14, 15, 16, 17, 22]
                        if builtInDateIDs.contains(id) || customDateFormatIDs.contains(id) {
                            dateStyleIndices.insert(xfIndex)
                        }
                    }
                default:
                    break
                }
            }
            func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
                if elementName == "cellXfs" { cellXfsDepth -= 1 }
            }
        }
        let delegate = Delegate()
        let parser = XMLParser(data: xml)
        parser.delegate = delegate
        _ = parser.parse()
        return delegate.dateStyleIndices
    }

    // MARK: - sheetN.xml

    /// Excel's 1900 date system: serial 1 = 1900-01-01, but the system
    /// treats 1900 as a leap year (a deliberate Lotus 1-2-3 compatibility
    /// bug Excel preserved), which nets out to epoch day 0 = 1899-12-30 in
    /// the proleptic Gregorian calendar — the standard, well-documented
    /// conversion every spreadsheet-reading library uses.
    private static func excelSerialToDateString(_ serial: Double) -> String? {
        guard serial > 0, serial < 2_958_466 else { return nil } // valid through year 9999
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        guard let epoch = calendar.date(from: DateComponents(year: 1899, month: 12, day: 30)) else { return nil }
        guard let date = calendar.date(byAdding: .day, value: Int(serial), to: epoch) else { return nil }
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year, let month = components.month, let day = components.day else { return nil }
        return String(format: "%02d/%02d/%04d", month, day, year)
    }

    /// Cell references (`A1`, `B1`, ...) can skip columns when a cell is
    /// empty — Excel omits `<c>` elements for blank cells rather than
    /// emitting an empty one. Rows are padded out to the row's own highest
    /// referenced column so every row in the returned `[[String]]` lines
    /// up positionally, matching what `CSVParser` naturally produces for a
    /// well-formed CSV (ragged CSV rows are a defect there too — see
    /// `ImportBankStatementView`'s column-count handling).
    static func parseSheet(_ xml: Data, sharedStrings: [String], dateStyleIndices: Set<Int>) throws -> [[String]] {
        final class Delegate: NSObject, XMLParserDelegate {
            let sharedStrings: [String]
            let dateStyleIndices: Set<Int>
            var rows: [[String]] = []
            var parseFailed = false

            private var currentRow: [String] = []
            private var currentColumnIndex = -1
            private var cellType: String?
            private var cellStyleIndex: Int?
            private var cellValue = ""
            private var insideValue = false
            private var insideInlineStr = false

            init(sharedStrings: [String], dateStyleIndices: Set<Int>) {
                self.sharedStrings = sharedStrings
                self.dateStyleIndices = dateStyleIndices
            }

            func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
                switch elementName {
                case "row":
                    currentRow = []
                case "c":
                    cellType = attributeDict["t"]
                    cellStyleIndex = attributeDict["s"].flatMap { Int($0) }
                    cellValue = ""
                    currentColumnIndex = attributeDict["r"].flatMap { Self.columnIndex(fromCellReference: $0) } ?? (currentColumnIndex + 1)
                case "v":
                    insideValue = true
                case "is":
                    insideInlineStr = true
                case "t":
                    if insideInlineStr { insideValue = true }
                default:
                    break
                }
            }
            func parser(_ parser: XMLParser, foundCharacters string: String) {
                if insideValue { cellValue += string }
            }
            func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
                switch elementName {
                case "v":
                    insideValue = false
                case "t":
                    if insideInlineStr { insideValue = false }
                case "is":
                    insideInlineStr = false
                case "c":
                    while currentRow.count < currentColumnIndex { currentRow.append("") }
                    currentRow.append(Self.resolvedText(type: cellType, styleIndex: cellStyleIndex, rawValue: cellValue, sharedStrings: sharedStrings, dateStyleIndices: dateStyleIndices))
                case "row":
                    rows.append(currentRow)
                    currentColumnIndex = -1
                default:
                    break
                }
            }
            func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
                parseFailed = true
            }

            static func resolvedText(type: String?, styleIndex: Int?, rawValue: String, sharedStrings: [String], dateStyleIndices: Set<Int>) -> String {
                switch type {
                case "s":
                    guard let index = Int(rawValue), sharedStrings.indices.contains(index) else { return "" }
                    return sharedStrings[index]
                case "inlineStr", "str":
                    return rawValue
                case "b":
                    return rawValue == "1" ? "TRUE" : "FALSE"
                default:
                    // Numeric (no `t` attribute) — the common case. If the
                    // cell's style is a date format, convert the serial to
                    // a real calendar date string; otherwise leave the raw
                    // number as-is (an amount column).
                    if let styleIndex, dateStyleIndices.contains(styleIndex), let serial = Double(rawValue),
                       let dateString = XLSXParser.excelSerialToDateString(serial) {
                        return dateString
                    }
                    return rawValue
                }
            }

            /// `"A1"` -> 0, `"B12"` -> 1, `"AA3"` -> 26. Column letters are
            /// base-26 with no zero digit (A=1, ..., Z=26, AA=27) —
            /// standard spreadsheet column addressing.
            static func columnIndex(fromCellReference ref: String) -> Int? {
                var index = 0
                for char in ref {
                    guard let ascii = char.asciiValue, char.isLetter else { break }
                    index = index * 26 + Int(ascii - Character("A").asciiValue!) + 1
                }
                return index > 0 ? index - 1 : nil
            }
        }

        let delegate = Delegate(sharedStrings: sharedStrings, dateStyleIndices: dateStyleIndices)
        let parser = XMLParser(data: xml)
        parser.delegate = delegate
        guard parser.parse(), !delegate.parseFailed else {
            throw ParseError.malformedXML("worksheet")
        }
        return delegate.rows
    }
}
