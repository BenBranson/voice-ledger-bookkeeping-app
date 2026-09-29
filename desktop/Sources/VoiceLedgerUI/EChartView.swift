import SwiftUI
import WebKit
import AppKit
import Core
import DesignSystem

/// Where the bundled chart files live: the app's Resources/Charts when
/// packaged, otherwise copied once from <project>/report-renderer. Never
/// fetched from the network.
enum ChartAssets {
    static let files = ["chart-host.html", "vl-charts.js", "echarts.min.js"]

    @MainActor static let directory: URL? = {
        let fm = FileManager.default
        if let bundled = Bundle.main.resourceURL?.appending(path: "Charts"),
           files.allSatisfy({ fm.fileExists(atPath: bundled.appending(path: $0).path) }) {
            return bundled
        }
        var cursor = Bundle.main.bundleURL
        var renderer: URL?
        for _ in 0..<8 {
            cursor = cursor.deletingLastPathComponent()
            let candidate = cursor.appending(path: "report-renderer")
            if fm.fileExists(atPath: candidate.appending(path: "shared/vl-charts.js").path) { renderer = candidate; break }
        }
        guard let renderer else { return nil }
        let sources = [
            renderer.appending(path: "app-host/chart-host.html"),
            renderer.appending(path: "shared/vl-charts.js"),
            renderer.appending(path: "node_modules/echarts/dist/echarts.min.js")
        ]
        guard let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let target = caches.appending(path: "VoiceLedger/Charts")
        try? fm.createDirectory(at: target, withIntermediateDirectories: true)
        for (source, name) in zip(sources, files) {
            let destination = target.appending(path: name)
            try? fm.removeItem(at: destination)
            guard (try? fm.copyItem(at: source, to: destination)) != nil else { return nil }
        }
        return target
    }()
}

/// The same stable color the JavaScript picks (FNV-1a over the item ID),
/// so SwiftUI legends always match their chart.
public enum ChartPalette {
    static let dark: [UInt32] = [0x29D3F2, 0x2788D9, 0x32C7A3, 0xA67CF5, 0x67E8F9, 0xF2B84B, 0x5B8DEF, 0x7FD1AE, 0xC79BF2, 0x8FA8C8]
    static let negative: UInt32 = 0xF06C8B
    static let other: UInt32 = 0x5F7390
    static let negativeCategories: Set<String> = ["overdraft", "contra", "creditBalance", "debitBalance", "negativeEquity", "deficit", "netLoss", "draw"]

    static func hash(_ text: String) -> UInt32 {
        var h: UInt32 = 2_166_136_261
        for unit in text.utf16 {
            h ^= UInt32(unit)
            h = h &* 16_777_619
        }
        return h
    }

    public static func color(for item: ChartItem) -> Color {
        let hex: UInt32
        if item.category == "other" { hex = other }
        else if negativeCategories.contains(item.category) { hex = negative }
        else { hex = dark[Int(hash(item.id) % UInt32(dark.count))] }
        return Color(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

/// One live, interactive ECharts chart in a local WKWebView. Swift owns the
/// data and the selection; the page only reports clicks as stable IDs,
/// which are checked against the IDs Swift sent before being accepted.
public struct EChartView: NSViewRepresentable {
    public let kind: String
    public let payload: String
    public let allowedIDs: Set<String>
    public let selectedID: String?
    public let summary: String
    public let onSelect: (String?) -> Void

    /// `data` is Codable chart data from `ChartData`; `kind` names the
    /// shared builder in vl-charts.js.
    public init<T: Encodable>(kind: String, data: T, allowedIDs: Set<String>, selectedID: String?, summary: String, onSelect: @escaping (String?) -> Void) {
        self.kind = kind
        self.payload = (try? String(decoding: JSONEncoder().encode(data), as: UTF8.self)) ?? "null"
        self.allowedIDs = allowedIDs
        self.selectedID = selectedID
        self.summary = summary
        self.onSelect = onSelect
    }

    public func makeCoordinator() -> Coordinator { Coordinator() }

    public func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(WeakMessageHandler(context.coordinator), name: "vlChart")
        configuration.websiteDataStore = .nonPersistent()
        let view = ScrollPassthroughWebView(frame: .zero, configuration: configuration)
        view.setValue(false, forKey: "drawsBackground")
        view.navigationDelegate = context.coordinator
        view.setAccessibilityLabel(summary)
        context.coordinator.webView = view
        if let dir = ChartAssets.directory {
            view.loadFileURL(dir.appending(path: "chart-host.html"), allowingReadAccessTo: dir)
        }
        return view
    }

    public func updateNSView(_ view: WKWebView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onSelect = onSelect
        coordinator.allowedIDs = allowedIDs
        view.setAccessibilityLabel(summary)
        let envelope: [String: Any] = [
            "kind": kind,
            "selectedId": selectedID as Any,
            "reducedMotion": NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
            "summary": summary
        ]
        guard let envelopeData = try? JSONSerialization.data(withJSONObject: envelope.compactMapValues { $0 is NSNull ? nil : $0 }),
              var text = String(data: envelopeData, encoding: .utf8) else { return }
        // Splice the already-encoded chart data in as "data".
        text.removeLast()
        text += ",\"data\":\(payload)}"
        coordinator.push(text)
    }

    public static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) {
        view.configuration.userContentController.removeScriptMessageHandler(forName: "vlChart")
        view.navigationDelegate = nil
        view.stopLoading()
        coordinator.webView = nil
    }

    @MainActor
    public final class Coordinator: NSObject, WKNavigationDelegate {
        weak var webView: WKWebView?
        var onSelect: ((String?) -> Void)?
        var allowedIDs: Set<String> = []
        private var isReady = false
        private var pending: String?
        private var lastPushed: String?

        /// Only re-renders when the payload actually changed, so SwiftUI
        /// state updates elsewhere don't redraw the chart.
        func push(_ payload: String) {
            guard payload != lastPushed else { return }
            guard isReady, let webView else { pending = payload; return }
            lastPushed = payload
            let literal = (try? String(decoding: JSONSerialization.data(withJSONObject: [payload], options: .fragmentsAllowed), as: UTF8.self)) ?? "[]"
            webView.evaluateJavaScript("VLHost.render(\(literal)[0])")
        }

        func receive(_ body: Any) {
            guard let message = body as? [String: Any], let type = message["type"] as? String else { return }
            switch type {
            case "ready":
                isReady = true
                if let pending { self.pending = nil; push(pending) }
            case "select":
                if message["id"] is NSNull || message["id"] == nil { onSelect?(nil); return }
                guard let id = message["id"] as? String, id.count < 256, allowedIDs.contains(id) else { return }
                onSelect?(id)
            default:
                return
            }
        }

        public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            decisionHandler(navigationAction.request.url?.isFileURL == true ? .allow : .cancel)
        }
    }

    /// Charts never scroll themselves; wheel/trackpad scrolling goes to the
    /// page so scrolling over a chart doesn't get stuck.
    final class ScrollPassthroughWebView: WKWebView {
        override func scrollWheel(with event: NSEvent) {
            nextResponder?.scrollWheel(with: event)
        }
    }

    /// Breaks the WKUserContentController → handler retain cycle.
    final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
        weak var target: Coordinator?
        init(_ target: Coordinator) { self.target = target }
        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            let body = message.body
            MainActor.assumeIsolated { target?.receive(body) }
        }
    }
}
