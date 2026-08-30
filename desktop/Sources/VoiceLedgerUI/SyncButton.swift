import SwiftUI
import DesignSystem

/// Owner directive (2026-08-30): "a lot of the sections say unsynced yet
/// there is no refresh button for them to sync." Several pages
/// (Cleanup Assessment, Balance Sheet Integrity, Chart of Accounts
/// Cleanup, Bank Feed Cleanup, Batch Fixes, the Client Dashboard,
/// Month-End Close, Close Package) render `state.findings`/`state.accounts`
/// directly and had no way to trigger a resync themselves — only the
/// sidebar's global sync control could, which isn't visible as "the
/// button for this page" when you're staring at a page that says "not
/// synced yet." Same icon/label/disabled pattern `FindingsListView`'s own
/// Refresh button already used, extracted so every page gets the exact
/// same behavior instead of eight slightly different copies.
public struct SyncButton: View {
    private let isSyncing: Bool
    private let onSync: () -> Void

    public init(isSyncing: Bool, onSync: @escaping () -> Void) {
        self.isSyncing = isSyncing
        self.onSync = onSync
    }

    public var body: some View {
        Button(action: onSync) {
            HStack(spacing: VLSpacing.xxs) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .rotationEffect(.degrees(isSyncing ? 360 : 0))
                    .animation(isSyncing ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: isSyncing)
                Text(isSyncing ? "Syncing…" : "Sync")
            }
            .font(VLTypography.label())
        }
        .buttonStyle(.bordered)
        .disabled(isSyncing)
        .help("Re-scan QBO for new or changed discrepancies")
    }
}
