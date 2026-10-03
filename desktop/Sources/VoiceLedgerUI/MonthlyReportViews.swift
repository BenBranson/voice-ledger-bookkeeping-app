import SwiftUI
import PDFKit
import AppKit
import DesignSystem

/// Monthly Client Report card: generate, progress, errors, and history.
public struct MonthlyReportCard: View {
    public struct HistoryItem: Identifiable {
        public let id: String
        public let title: String
        public let subtitle: String
        public let hasSummary: Bool
        public init(id: String, title: String, subtitle: String, hasSummary: Bool = false) {
            self.id = id
            self.title = title
            self.subtitle = subtitle
            self.hasSummary = hasSummary
        }
    }

    let isGenerating: Bool
    let stageText: String?
    let error: String?
    let history: [HistoryItem]
    let onGenerate: () -> Void
    let onOpen: (String) -> Void
    let onExport: (String) -> Void
    /// Preview / save the 2-page Client Summary of a generated report.
    let onOpenSummary: (String) -> Void
    let onExportSummary: (String) -> Void

    public init(isGenerating: Bool, stageText: String?, error: String?, history: [HistoryItem], onGenerate: @escaping () -> Void, onOpen: @escaping (String) -> Void, onExport: @escaping (String) -> Void = { _ in }, onOpenSummary: @escaping (String) -> Void = { _ in }, onExportSummary: @escaping (String) -> Void = { _ in }) {
        self.onExport = onExport
        self.onOpenSummary = onOpenSummary
        self.onExportSummary = onExportSummary
        self.isGenerating = isGenerating
        self.stageText = stageText
        self.error = error
        self.history = history
        self.onGenerate = onGenerate
        self.onOpen = onOpen
    }

    public var body: some View {
        VLCard(accentRail: VLColor.cyan) {
            VStack(alignment: .leading, spacing: VLSpacing.sm) {
                HStack {
                    VStack(alignment: .leading, spacing: VLSpacing.xxs) {
                        Text("MONTHLY CLIENT REPORT")
                            .font(VLTypography.eyebrow())
                            .tracking(VLTypography.eyebrowTracking)
                            .foregroundStyle(VLColor.textMuted)
                        Text("Makes two PDFs from the same numbers: a 2-page Client Summary to send every month, and the full report (profit, expenses, cash, customers, bills, open items, financial statements).")
                            .font(VLTypography.caption())
                            .foregroundStyle(VLColor.textSecondary)
                    }
                    Spacer()
                    Button(isGenerating ? "Generating…" : "Generate Report") { onGenerate() }
                        .buttonStyle(.borderedProminent)
                        .disabled(isGenerating)
                }
                if isGenerating {
                    HStack(spacing: VLSpacing.xs) {
                        ProgressView().controlSize(.small)
                        Text(stageText ?? "Starting…").font(VLTypography.caption()).foregroundStyle(VLColor.textMuted)
                    }
                }
                if let error {
                    Text(error).font(VLTypography.caption()).foregroundStyle(.red).textSelection(.enabled)
                }
                if !history.isEmpty {
                    Divider().overlay(VLColor.border)
                    Text("PREVIOUS REPORTS")
                        .font(VLTypography.eyebrow())
                        .tracking(VLTypography.eyebrowTracking)
                        .foregroundStyle(VLColor.textMuted)
                    ForEach(history.prefix(6)) { item in
                        HStack {
                            Text(item.title).foregroundStyle(VLColor.textPrimary)
                            Text(item.subtitle).foregroundStyle(VLColor.textMuted)
                            Spacer()
                            if item.hasSummary {
                                Text("Summary:").foregroundStyle(VLColor.textMuted)
                                Button("Preview") { onOpenSummary(item.id) }.buttonStyle(.link)
                                Button("Export…") { onExportSummary(item.id) }.buttonStyle(.link)
                                Text("·").foregroundStyle(VLColor.textMuted)
                                Text("Full report:").foregroundStyle(VLColor.textMuted)
                            }
                            Button("Preview") { onOpen(item.id) }.buttonStyle(.link)
                            Button(item.hasSummary ? "Export…" : "Export PDF…") { onExport(item.id) }.buttonStyle(.link)
                        }
                        .font(VLTypography.caption())
                    }
                }
                Text("Generated locally from read-only QuickBooks data; each PDF is saved with the exact data snapshot it was built from.")
                    .font(VLTypography.caption())
                    .foregroundStyle(VLColor.textMuted)
            }
        }
    }
}

/// Shows the generated PDF itself — Save/Open use this same file, so the
/// preview and the export can never differ.
public struct PDFPreviewSheet: View {
    /// One PDF the sheet can show: the 2-page Client Summary or the full report.
    public struct Variant: Identifiable, Equatable {
        public let id: String
        public let label: String
        public let url: URL
        public let title: String
        public init(id: String, label: String, url: URL, title: String) {
            self.id = id; self.label = label; self.url = url; self.title = title
        }
    }

    let variants: [Variant]
    let onClose: () -> Void
    @State private var selected: String

    public init(url: URL, title: String, onClose: @escaping () -> Void) {
        self.init(variants: [Variant(id: "only", label: title, url: url, title: title)], onClose: onClose)
    }

    /// Several PDFs from the same snapshot; a switch at the top flips between them.
    public init(variants: [Variant], initial: String? = nil, onClose: @escaping () -> Void) {
        self.variants = variants
        self.onClose = onClose
        _selected = State(initialValue: initial ?? variants.first?.id ?? "")
    }

    private var current: Variant? { variants.first { $0.id == selected } ?? variants.first }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: VLSpacing.sm) {
                if variants.count > 1 {
                    Picker("", selection: $selected) {
                        ForEach(variants) { Text($0.label).tag($0.id) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                } else if let current {
                    Text(current.title).font(VLTypography.cardTitle())
                }
                Spacer()
                Button {
                    if let current { PDFExport.save(current.url, suggestedName: current.title) }
                } label: { Label("Download PDF", systemImage: "arrow.down.doc") }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut("d", modifiers: .command)
                Button("Open in Preview") { if let current { NSWorkspace.shared.open(current.url) } }
                Button("Show in Finder") { if let current { NSWorkspace.shared.activateFileViewerSelecting([current.url]) } }
                Button("Close") { onClose() }.keyboardShortcut(.cancelAction)
            }
            .padding(VLSpacing.sm)
            if let current { PDFKitView(url: current.url).id(current.id) }
        }
        .frame(minWidth: 760, idealWidth: 900, minHeight: 700, idealHeight: 920)
    }
}

/// Saves a copy of an already-generated report PDF wherever the user picks.
@MainActor
public enum PDFExport {
    public static func save(_ url: URL, suggestedName: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(suggestedName).pdf"
        panel.allowedContentTypes = [.pdf]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let target = panel.url else { return }
        try? FileManager.default.removeItem(at: target)
        try? FileManager.default.copyItem(at: url, to: target)
    }
}

private struct PDFKitView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.document = PDFDocument(url: url)
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        if view.document?.documentURL != url { view.document = PDFDocument(url: url) }
    }
}
