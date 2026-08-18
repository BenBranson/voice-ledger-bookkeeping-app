import Foundation
import Core

/// Minimal single-sheet OOXML (.xlsx) writer — no third-party spreadsheet
/// library. Opens natively in both Excel and Google Sheets (Sheets imports
/// .xlsx directly, no conversion step), which is what actually matters
/// here rather than picking one format per app. Cell values are written
/// inline (`t="inlineStr"`) rather than via a shared-strings table — a
/// second, more complex OOXML part this doesn't need for report-sized
/// data. A cell with `ExportCell.numericValue` is written as a real number
/// cell (no `t` attribute, OOXML's default), so a bookkeeper can sum an
/// exported column directly in the spreadsheet rather than re-typing it.
public enum XLSXReportExporter {
    public static func export(_ table: ExportTable) -> Data {
        let sheetXML = sheetXML(for: table)

        let entries: [ZIPArchiveWriter.Entry] = [
            .init(path: "[Content_Types].xml", contents: Data(contentTypesXML.utf8)),
            .init(path: "_rels/.rels", contents: Data(rootRelsXML.utf8)),
            .init(path: "xl/workbook.xml", contents: Data(workbookXML(title: table.title).utf8)),
            .init(path: "xl/_rels/workbook.xml.rels", contents: Data(workbookRelsXML.utf8)),
            .init(path: "xl/worksheets/sheet1.xml", contents: Data(sheetXML.utf8))
        ]
        return ZIPArchiveWriter.write(entries)
    }

    private static func sheetXML(for table: ExportTable) -> String {
        var rowsXML = ""

        rowsXML += rowXML(rowIndex: 1, cells: table.columns.map { ExportCell(text: $0) })
        for (offset, row) in table.rows.enumerated() {
            rowsXML += rowXML(rowIndex: offset + 2, cells: row)
        }

        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
        <sheetData>
        \(rowsXML)</sheetData>
        </worksheet>
        """
    }

    private static func rowXML(rowIndex: Int, cells: [ExportCell]) -> String {
        var cellsXML = ""
        for (columnOffset, cell) in cells.enumerated() {
            let reference = columnLetter(columnOffset) + String(rowIndex)
            if let numericValue = cell.numericValue {
                cellsXML += "<c r=\"\(reference)\"><v>\(numericValue)</v></c>"
            } else {
                cellsXML += "<c r=\"\(reference)\" t=\"inlineStr\"><is><t xml:space=\"preserve\">\(xmlEscape(cell.text))</t></is></c>"
            }
        }
        return "<row r=\"\(rowIndex)\">\(cellsXML)</row>\n"
    }

    /// 0-indexed column -> spreadsheet letter (0 -> A, 25 -> Z, 26 -> AA...).
    static func columnLetter(_ index: Int) -> String {
        var n = index
        var letters = ""
        repeat {
            letters = String(UnicodeScalar(UInt8(65 + n % 26))) + letters
            n = n / 26 - 1
        } while n >= 0
        return letters
    }

    private static func xmlEscape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    private static let contentTypesXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
    <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
    <Default Extension="xml" ContentType="application/xml"/>
    <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
    <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
    </Types>
    """

    private static let rootRelsXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
    <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
    </Relationships>
    """

    /// Excel sheet names: max 31 characters, and `: \ / ? * [ ]` are all
    /// invalid — stripped rather than left in to produce a file Excel
    /// itself would refuse to open correctly.
    private static func sanitizedSheetName(_ title: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: ":\\/?*[]")
        let cleaned = title.components(separatedBy: invalidCharacters).joined()
        let trimmed = String(cleaned.prefix(31))
        return trimmed.isEmpty ? "Sheet1" : trimmed
    }

    private static func workbookXML(title: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
        <sheets>
        <sheet name="\(xmlEscape(sanitizedSheetName(title)))" sheetId="1" r:id="rId1"/>
        </sheets>
        </workbook>
        """
    }

    private static let workbookRelsXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
    <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
    </Relationships>
    """
}
