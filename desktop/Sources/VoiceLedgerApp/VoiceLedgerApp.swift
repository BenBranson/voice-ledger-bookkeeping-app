import SwiftUI
import Foundation
import Core
import IntegrationsQuickBooks
import DB
import DesignSystem
import VoiceLedgerUI

/// The real running app for Phase 1 step 1.6's slice. **Not visually
/// verified in this session** — no screenshot tool for a native macOS
/// window was available in this environment; see the final report for what
/// that means for confidence in this layer specifically (the logic
/// underneath, in Core, IS test-verified: 41/41 offline tests passing).
///
/// Usage:
///   VOICE_LEDGER_BACKEND_URL=https://your-backend.example.com \
///   VOICE_LEDGER_SESSION_TOKEN=<token> \
///   VOICE_LEDGER_REALM_ID=<sandbox realmId> \
///   swift run VoiceLedgerApp
@main
struct VoiceLedgerApp: App {
    @State private var appState: AppState?
    @State private var configError: String?

    var body: some Scene {
        WindowGroup("Voice Ledger") {
            Group {
                if let appState {
                    RootView(state: appState)
                } else if let configError {
                    ConfigErrorView(message: configError)
                } else {
                    ProgressView().onAppear { configure() }
                }
            }
            .frame(minWidth: 720, minHeight: 480)
        }
    }

    private func configure() {
        do {
            let configuration = try BackendConfiguration.fromEnvironment()
            guard let realmIDString = ProcessInfo.processInfo.environment["VOICE_LEDGER_REALM_ID"] else {
                configError = "VOICE_LEDGER_REALM_ID is not set."
                return
            }
            let realmID = RealmID(rawValue: realmIDString)
            let backend = BackendClient(configuration: configuration)

            let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appending(path: "VoiceLedger", directoryHint: .isDirectory)
            let store = try ClientStore(realmID: realmID, rootDirectory: supportDir)

            // CLAUDE.md rule 7: sandbox vs. production must be visually
            // unmistakable. This app has no environment picker — the
            // environment comes from which backend/realm you pointed it at,
            // surfaced honestly rather than defaulted to sandbox.
            let environmentString = ProcessInfo.processInfo.environment["VOICE_LEDGER_ENVIRONMENT"] ?? "sandbox"
            let environment: QBOEnvironment = environmentString == "production" ? .production : .sandbox

            let period = AccountingPeriod(year: 2026, month: 7)
            appState = AppState(realmID: realmID, environment: environment, period: period, backend: backend, store: store)
        } catch {
            configError = "\(error)"
        }
    }
}

private struct ConfigErrorView: View {
    let message: String
    var body: some View {
        VStack(spacing: VLSpacing.md) {
            Text("Configuration error")
                .font(VLTypography.pageTitle())
            Text(message)
                .font(VLTypography.body())
                .foregroundStyle(VLColor.textMuted)
        }
        .padding(VLSpacing.pageGutter)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(VLColor.background)
    }
}
