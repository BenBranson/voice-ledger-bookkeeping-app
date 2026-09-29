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
        public init(id: String, title: String, subtitle: String) {
            self.id = id
            self.title = title
            self.subtitle = subtitle
        }
    }

    let isGenerating: Bool
    let stageText: String?
    let error: String?
    let history: [HistoryItem]
    let onGenerate: () -> Void
    let onOpen: (String) -> Void

    public init(isGenerating: Bool, stageText: String?, error: String?, history: [HistoryItem], onGenerate: @escaping () -> Void, onOpen: @escaping (String) -> Void) {
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
                        Text("A designed, client-ready PDF: KPIs, trends, revenue-to-net-income bridge, expenses, cash and receivables, findings, and supporting tables.")
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
                            Button("Open") { onOpen(item.id) }.buttonStyle(.link)
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
    let url: URL
    let title: String
    let onClose: () -> Void

    public init(url: URL, title: String, onClose: @escaping () -> Void) {
        self.url = url
        self.title = title
        self.onClose = onClose
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).font(VLTypography.cardTitle())
                Spacer()
                Button("Save a Copy…") { saveCopy() }
                Button("Open in Preview") { NSWorkspace.shared.open(url) }
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                Button("Close") { onClose() }.keyboardShortcut(.cancelAction)
            }
            .padding(VLSpacing.sm)
            PDFKitView(url: url)
        }
        .frame(minWidth: 760, idealWidth: 900, minHeight: 700, idealHeight: 920)
    }

    private func saveCopy() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(title).pdf"
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
