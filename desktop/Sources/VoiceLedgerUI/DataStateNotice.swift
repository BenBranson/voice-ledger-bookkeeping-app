import SwiftUI
import Core
import DesignSystem

/// The one way every page says "nothing to show" — always naming which of
/// three things is true (not synced / synced but empty / not loaded here)
/// and offering the single action that fixes it.
/// docs/MONEYPENNY_CONSISTENCY_DESIGN.md, "Cached-vs-synced, made boring".
public struct DataStateNotice: View {
    public enum Kind {
        /// A report or dataset that loads on demand (e.g. "the Balance Sheet").
        case notLoaded(what: String, onLoad: () -> Void)
        /// Loaded from QuickBooks and genuinely empty.
        case empty(what: String)
    }

    private let kind: Kind
    private let isLoading: Bool
    @Environment(\.dataFreshness) private var freshness
    @Environment(\.syncNow) private var syncNow

    public init(_ kind: Kind, isLoading: Bool = false) {
        self.kind = kind
        self.isLoading = isLoading
    }

    public var body: some View {
        VLCard(accentRail: accent) {
            VStack(alignment: .leading, spacing: VLSpacing.xs) {
                Text(headline).font(VLTypography.cardTitle()).foregroundStyle(VLColor.textPrimary)
                Text(detail).font(VLTypography.caption()).foregroundStyle(VLColor.textSecondary)
                HStack(spacing: VLSpacing.sm) {
                    if isLoading {
                        ProgressView().controlSize(.small)
                        Text("Loading…").font(VLTypography.caption()).foregroundStyle(VLColor.textMuted)
                    } else {
                        switch (freshness, kind) {
                        case (.neverSynced, _), (.cached, _):
                            if let syncNow { Button("Sync with QuickBooks") { syncNow() }.buttonStyle(.borderedProminent) }
                            if case .notLoaded(_, let onLoad) = kind { Button("Load anyway") { onLoad() } }
                        case (_, .notLoaded(_, let onLoad)):
                            Button("Load") { onLoad() }.buttonStyle(.borderedProminent)
                        case (_, .empty):
                            if let syncNow { Button("Sync again") { syncNow() } }
                        }
                    }
                }
            }
        }
    }

    private var accent: Color {
        switch freshness {
        case .neverSynced, .cached: return .orange
        case .syncing: return VLColor.cyan
        case .synced: return VLColor.textMuted
        }
    }

    private var what: String {
        switch kind {
        case .notLoaded(let w, _), .empty(let w): return w
        }
    }

    private var headline: String {
        switch (freshness, kind) {
        case (.neverSynced, _): return "Not synced with QuickBooks yet"
        case (.syncing, _): return "Syncing with QuickBooks…"
        case (.cached, _): return "Showing saved data from an earlier sync"
        case (.synced, .notLoaded): return "\(what.prefix(1).uppercased() + what.dropFirst()) isn't loaded on this page yet"
        case (.synced, .empty): return "QuickBooks returned nothing for \(what)"
        }
    }

    private var detail: String {
        switch (freshness, kind) {
        case (.neverSynced, _): return "Nothing has been read from QuickBooks in this session, so \(what) can't be shown. Sync to load it."
        case (.syncing, _): return "\(what.prefix(1).uppercased() + what.dropFirst()) will appear when the sync finishes."
        case (.cached(let at), _): return "The last sync was \(at.formatted(.relative(presentation: .named))). \(what.prefix(1).uppercased() + what.dropFirst()) is loaded fresh on request; sync first so it reflects QuickBooks now."
        case (.synced, .notLoaded): return "The sync is current; this page loads \(what) separately when asked."
        case (.synced, .empty): return "The sync is current and \(what) is genuinely empty in QuickBooks for this period."
        }
    }
}

private struct DataFreshnessKey: EnvironmentKey { static let defaultValue: Freshness = .neverSynced }
private struct SyncNowKey: EnvironmentKey { nonisolated(unsafe) static let defaultValue: (() -> Void)? = nil }

public extension EnvironmentValues {
    var dataFreshness: Freshness {
        get { self[DataFreshnessKey.self] }
        set { self[DataFreshnessKey.self] = newValue }
    }
    var syncNow: (() -> Void)? {
        get { self[SyncNowKey.self] }
        set { self[SyncNowKey.self] = newValue }
    }
}
