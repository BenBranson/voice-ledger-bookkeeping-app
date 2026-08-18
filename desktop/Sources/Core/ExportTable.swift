import Foundation

/// The one shared shape every export format (CSV, XLSX, PDF) renders from.
/// Lives in Core (pure data, no rendering dependency) so any view/AppState
/// code can build one without depending on the `Exporting` target directly
/// — only the actual file-writing code needs that.
///
/// A cell carries both a display string (what's already shown on screen,
/// so exports never contradict the UI) and an optional raw numeric value.
/// The numeric value is what makes an exported spreadsheet actually usable
/// for further math in Google Sheets/Excel rather than just a visual dump —
/// CSV and XLSX use it when present (a real number cell, not text that
/// happens to look like one); PDF always uses the display string, since a
/// PDF has no cell types to begin with.
public struct ExportCell: Sendable {
    public let text: String
    public let numericValue: Double?

    public init(text: String, numericValue: Double? = nil) {
        self.text = text
        self.numericValue = numericValue
    }

    public static func money(_ amount: Money?) -> ExportCell {
        guard let amount else { return ExportCell(text: "") }
        return ExportCell(text: amount.description, numericValue: Double(amount.minorUnits) / 100)
    }
}

public struct ExportTable: Sendable {
    public let title: String
    public let columns: [String]
    public let rows: [[ExportCell]]
    public let generatedAt: Date

    public init(title: String, columns: [String], rows: [[ExportCell]], generatedAt: Date = Date()) {
        self.title = title
        self.columns = columns
        self.rows = rows
        self.generatedAt = generatedAt
    }
}
