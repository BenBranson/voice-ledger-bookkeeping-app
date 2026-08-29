import Foundation
import Vision
import PDFKit
import ImageIO
import CoreGraphics

/// docs/VOICE_LEDGER_SPEC.md's Universal Ingestion §Tier 2: "Apple Vision
/// on-device OCR (PDFs, screenshots)... macOS 15+ `RecognizeDocumentsRequest`
/// returns structured document data rather than a flat line dump." The
/// document never leaves the machine — no network call anywhere in this
/// file, matching the same privacy property Tier 1 (CSV/OFX/XLSX) already
/// has.
///
/// **`RecognizeDocumentsRequest`'s exact shape was verified by compiling
/// against the real SDK** (`swiftc -typecheck` against a throwaway file
/// using this exact API), not recalled from memory alone — CLAUDE.md's
/// working style ("verify against sandbox before designing around it")
/// applied to a compile-time API the same way it applies to a live QBO
/// endpoint. **That check also disproved spec's own claim**: the compiler
/// refuses this API below macOS 26.0 ("only available in macOS 26.0 or
/// newer"), not macOS 15 as spec states — confirmed against the actual
/// SDK, not a documentation page. Gated `@available(macOS 26.0, *)` to
/// match reality; every call site checks `#available` and degrades to a
/// clear "requires a newer macOS" message on an older system, never a
/// crash. The owner's own machine runs macOS 26.6.2, well past this.
///
/// **Table-only, deliberately** — spec's own framing prefers structured
/// table data over "a flat line dump." A document with no detected table
/// throws `.noTableDetected` rather than falling back to a guessed
/// column split of raw paragraph text, matching this codebase's general
/// "never guess" discipline. This is Tier 2's extraction stage only —
/// once rows come back, they feed the SAME `BankStatementCSVImporter
/// .import(rows:...)` Tier 1 already uses (confirm-and-correct column
/// mapping, cross-foot posture, everything downstream), not a second,
/// parallel normalization path.
@available(macOS 26.0, *)
public enum VisionDocumentOCR {
    public enum OCRError: Error, Equatable {
        case unsupportedFile
        case noTableDetected
    }

    /// Every table detected on the page, rows concatenated in the order
    /// Vision returns them. A page with multiple tables (e.g. a header
    /// summary table plus the real transaction table) produces one
    /// combined row list — the confirm-and-correct column-mapping screen
    /// is where a human sorts out which rows are real transaction data,
    /// same as it already handles an oddly-shaped CSV.
    public static func extractRows(from image: CGImage) async throws -> [[String]] {
        let request = RecognizeDocumentsRequest()
        let observations = try await request.perform(on: image)
        guard let document = observations.first?.document else { throw OCRError.noTableDetected }
        var rows: [[String]] = []
        for table in document.tables {
            for row in table.rows {
                rows.append(row.map { $0.content.text.transcript })
            }
        }
        guard !rows.isEmpty else { throw OCRError.noTableDetected }
        return rows
    }

    /// A screenshot or photo of a statement — PNG/JPEG/HEIC/whatever
    /// `ImageIO` already reads.
    public static func extractRows(fromImageFileAt url: URL) async throws -> [[String]] {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw OCRError.unsupportedFile
        }
        return try await extractRows(from: image)
    }

    /// Every page of a PDF, rows concatenated in page order — a
    /// multi-page bank statement produces one continuous row list, the
    /// same shape a single CSV file would. A page whose own OCR fails
    /// (blank page, a summary page with no table) is skipped rather than
    /// failing the whole document — matches this codebase's "one source
    /// failing must not fail the whole operation" posture elsewhere
    /// (`AppState.syncAndEvaluate`'s per-report `try?`). Only throws when
    /// EVERY page contributed nothing.
    public static func extractRows(fromPDFAt url: URL) async throws -> [[String]] {
        guard let document = PDFDocument(url: url) else { throw OCRError.unsupportedFile }
        var allRows: [[String]] = []
        for pageIndex in 0..<document.pageCount {
            guard let image = renderPDFPage(document: document, pageIndex: pageIndex) else { continue }
            if let rows = try? await extractRows(from: image) {
                allRows.append(contentsOf: rows)
            }
        }
        guard !allRows.isEmpty else { throw OCRError.noTableDetected }
        return allRows
    }

    /// Renders one PDF page to a bitmap at 2x scale — Vision's document
    /// recognizer works on pixels, not vector PDF content, so a real
    /// rasterization step is unavoidable before OCR can run at all.
    static func renderPDFPage(document: PDFDocument, pageIndex: Int, scale: CGFloat = 2.0) -> CGImage? {
        guard let page = document.page(at: pageIndex) else { return nil }
        let bounds = page.bounds(for: .mediaBox)
        let width = Int(bounds.width * scale)
        let height = Int(bounds.height * scale)
        guard width > 0, height > 0,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }
        context.scaleBy(x: scale, y: scale)
        context.setFillColor(CGColor.white)
        context.fill(CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height))
        page.draw(with: .mediaBox, to: context)
        return context.makeImage()
    }
}
