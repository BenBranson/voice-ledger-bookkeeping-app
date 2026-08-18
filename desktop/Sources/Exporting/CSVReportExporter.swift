import Foundation
import Core

/// The simplest, most universally-compatible export — opens directly in
/// Google Sheets or Excel with no conversion step. Uses `ExportCell
/// .numericValue` when present so a value like a dollar amount lands as a
/// real number a spreadsheet can sum, not text that merely looks like one.
public enum CSVReportExporter {
    public static func export(_ table: ExportTable) -> Data {
        var lines: [String] = [table.columns.map(escape).joined(separator: ",")]
        for row in table.rows {
            lines.append(row.map { cellText($0) }.map(escape).joined(separator: ","))
        }
        let text = lines.joined(separator: "\r\n") + "\r\n"
        return Data(text.utf8)
    }

    private static func cellText(_ cell: ExportCell) -> String {
        if let numericValue = cell.numericValue {
            return String(numericValue)
        }
        return cell.text
    }

    /// RFC 4180: a field containing a comma, quote, or newline is wrapped
    /// in quotes, with internal quotes doubled.
    private static func escape(_ field: String) -> String {
        guard field.contains(",") || field.contains("\"") || field.contains("\n") || field.contains("\r") else {
            return field
        }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
