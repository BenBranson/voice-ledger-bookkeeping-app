import SwiftUI
import DesignSystem

/// A UI-only selection — which file format the human wants — not an export
/// itself. `VoiceLedgerUI` has no dependency on `Exporting`; the app layer
/// (which does) turns this into an actual `CSVReportExporter`/
/// `XLSXReportExporter`/`PDFReportExporter` call.
public enum ReportExportFormat: String, CaseIterable, Identifiable {
    case csv, xlsx, pdf
    public var id: Self { self }
    public var label: String {
        switch self {
        case .csv: return "CSV"
        case .xlsx: return "Excel (.xlsx)"
        case .pdf: return "PDF"
        }
    }
}

/// A single small "Export" control reused across every report-style page —
/// Balance Sheet, P&L, Close Package, Cleanup Assessment, Activity Log —
/// so the choice always looks and behaves the same rather than each page
/// inventing its own.
public struct ExportMenuButton: View {
    private let onExport: (ReportExportFormat) -> Void

    public init(onExport: @escaping (ReportExportFormat) -> Void) {
        self.onExport = onExport
    }

    public var body: some View {
        Menu("Export") {
            ForEach(ReportExportFormat.allCases) { format in
                Button(format.label) { onExport(format) }
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}
