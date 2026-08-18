import Foundation
import CoreGraphics
import CoreText
import Core

/// A plain, paginated table PDF via CoreGraphics/CoreText directly — no
/// AppKit, no third-party PDF library. US Letter, fixed row height,
/// proportional column widths from content length, header row repeated on
/// every page. Deliberately basic: this mirrors what's already on screen
/// (title, columns, rows), not a branded/designed document — the full
/// spec's "branded client PDF" (Page 12) is a different, larger feature.
public enum PDFReportExporter {
    private static let pageWidth: CGFloat = 612
    private static let pageHeight: CGFloat = 792
    private static let margin: CGFloat = 36
    private static let rowHeight: CGFloat = 16
    private static let titleFontSize: CGFloat = 16
    private static let bodyFontSize: CGFloat = 9

    public static func export(_ table: ExportTable) -> Data {
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else { return Data() }
        var mediaBox = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return Data() }

        let titleFont = CTFontCreateWithName("Helvetica-Bold" as CFString, titleFontSize, nil)
        let headerFont = CTFontCreateWithName("Helvetica-Bold" as CFString, bodyFontSize, nil)
        let bodyFont = CTFontCreateWithName("Helvetica" as CFString, bodyFontSize, nil)
        let mutedColor = CGColor(gray: 0.4, alpha: 1)
        let textColor = CGColor(gray: 0, alpha: 1)

        let columnWidths = computeColumnWidths(table, availableWidth: pageWidth - 2 * margin)
        let usableHeight = pageHeight - 2 * margin

        var page = 0
        var rowIndex = 0
        let dateFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return formatter
        }()

        func drawHeaderArea() -> CGFloat {
            var y = pageHeight - margin - titleFontSize
            drawLine(table.title, x: margin, y: y, font: titleFont, color: textColor, in: context)
            y -= 14
            let generatedLabel = page == 0
                ? "Generated \(dateFormatter.string(from: table.generatedAt))"
                : "\(table.title) (continued) — page \(page + 1)"
            drawLine(generatedLabel, x: margin, y: y, font: bodyFont, color: mutedColor, in: context)
            y -= 16
            drawRow(table.columns.map { ExportCell(text: $0) }, x: margin, y: y, widths: columnWidths, font: headerFont, color: textColor, in: context)
            y -= rowHeight
            return y
        }

        context.beginPDFPage(nil)
        var y = drawHeaderArea()

        while rowIndex < table.rows.count {
            if y < margin {
                context.endPDFPage()
                page += 1
                context.beginPDFPage(nil)
                y = drawHeaderArea()
            }
            drawRow(table.rows[rowIndex], x: margin, y: y, widths: columnWidths, font: bodyFont, color: textColor, in: context)
            y -= rowHeight
            rowIndex += 1
        }

        if table.rows.isEmpty {
            drawLine("No data.", x: margin, y: y, font: bodyFont, color: mutedColor, in: context)
        }

        context.endPDFPage()
        context.closePDF()
        _ = usableHeight // reserved for future page-capacity precomputation
        return data as Data
    }

    private static func drawRow(_ cells: [ExportCell], x: CGFloat, y: CGFloat, widths: [CGFloat], font: CTFont, color: CGColor, in context: CGContext) {
        var currentX = x
        for (index, cell) in cells.enumerated() {
            let width = index < widths.count ? widths[index] : 80
            drawLine(cell.text, x: currentX, y: y, font: font, color: color, in: context, maxWidth: width)
            currentX += width
        }
    }

    /// CoreText's own attribute keys, not `NSAttributedString.Key.font`/
    /// `.foregroundColor` — those are AppKit extensions (expecting an
    /// `NSFont`/`NSColor`), not available without importing AppKit, which
    /// this file deliberately doesn't. `CTLineDraw` reads attributes via
    /// CoreText's own keys regardless, so these are the correct ones even
    /// where an AppKit key of the same apparent purpose exists.
    private static let fontAttributeKey = NSAttributedString.Key(kCTFontAttributeName as String)
    private static let foregroundColorAttributeKey = NSAttributedString.Key(kCTForegroundColorAttributeName as String)

    private static func drawLine(_ text: String, x: CGFloat, y: CGFloat, font: CTFont, color: CGColor, in context: CGContext, maxWidth: CGFloat? = nil) {
        let attributedString = NSAttributedString(string: text, attributes: [
            fontAttributeKey: font,
            foregroundColorAttributeKey: color
        ])
        let line = CTLineCreateWithAttributedString(attributedString)
        if let maxWidth {
            // Truncate visually rather than overlapping the next column —
            // a real column-width solver is out of scope for a basic export.
            let width = CTLineGetTypographicBounds(line, nil, nil, nil)
            if width > Double(maxWidth) {
                let truncated = CTLineCreateTruncatedLine(line, Double(maxWidth), .end, nil) ?? line
                context.textPosition = CGPoint(x: x, y: y)
                CTLineDraw(truncated, context)
                return
            }
        }
        context.textPosition = CGPoint(x: x, y: y)
        CTLineDraw(line, context)
    }

    /// Proportional to each column's longest content (header or cell text),
    /// clamped so no single column can starve the rest and the total never
    /// exceeds the page's usable width.
    private static func computeColumnWidths(_ table: ExportTable, availableWidth: CGFloat) -> [CGFloat] {
        guard !table.columns.isEmpty else { return [] }
        var maxLengths = table.columns.map { CGFloat($0.count) }
        for row in table.rows {
            for (index, cell) in row.enumerated() where index < maxLengths.count {
                maxLengths[index] = max(maxLengths[index], CGFloat(cell.text.count))
            }
        }
        let minWidth: CGFloat = 40
        let maxWidth: CGFloat = availableWidth * 0.5
        let clamped = maxLengths.map { min(max($0 * 5.5, minWidth), maxWidth) }
        let total = clamped.reduce(0, +)
        guard total > 0 else { return clamped }
        let scale = min(1, availableWidth / total)
        return clamped.map { $0 * scale }
    }
}
